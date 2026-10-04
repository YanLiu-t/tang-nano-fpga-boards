//============================================================================
// PONG GAME - Versione con potenziometro per Player 1
//============================================================================
//
// Basato su svo_pong di Clifford Wolf, modificato per:
// - Player 1: controllo diretto della posizione tramite potenziometro (ADC)
// - Player 2: autopilot (AI)
//
//============================================================================

`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module pong_game #( `SVO_DEFAULT_PARAMS ) (
    input clk,
    input resetn,
    input resetn_game,   // Reset del gioco (riavvia partita)
    input enable,

    // Input Player 1 da potenziometro (0-255)
    input [7:0] p1_paddle_pos,
    input       game_reset_ext,  // 外部重置 (KEY3)

    // input stream
    input in_axis_tvalid,
    output in_axis_tready,
    input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
    input [0:0] in_axis_tuser,

    // output stream
    output out_axis_tvalid,
    input out_axis_tready,
    output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
    output [0:0] out_axis_tuser
);
    `SVO_DECLS

    wire [11:0] p1_pos, p2_pos;
    wire [6:0] p1_points, p2_points;
    wire [11:0] puck_x, puck_y;
    wire flash;

    pong_control #( `SVO_PASS_PARAMS ) pong_control_inst (
        .clk(clk),
        .resetn(resetn && resetn_game),
        .enable(in_axis_tvalid && in_axis_tready && in_axis_tuser && enable),

        .p1_paddle_pos(p1_paddle_pos),
        .game_reset_ext(game_reset_ext),

        .flash(flash),
        .game_over(),  // 暂不向外暴露
        .p1_pos(p1_pos),
        .p2_pos(p2_pos),
        .p1_points(p1_points),
        .p2_points(p2_points),
        .puck_x(puck_x),
        .puck_y(puck_y)
    );

    svo_pong_video #( `SVO_PASS_PARAMS ) pong_video_inst (
        .clk(clk),
        .resetn(resetn),
        .enable(enable),

        .flash(flash),
        .p1_pos(p1_pos),
        .p2_pos(p2_pos),
        .p1_points(p1_points),
        .p2_points(p2_points),
        .puck_x(puck_x),
        .puck_y(puck_y),

        .in_axis_tvalid(in_axis_tvalid),
        .in_axis_tready(in_axis_tready),
        .in_axis_tdata(in_axis_tdata),
        .in_axis_tuser(in_axis_tuser),

        .out_axis_tvalid(out_axis_tvalid),
        .out_axis_tready(out_axis_tready),
        .out_axis_tdata(out_axis_tdata),
        .out_axis_tuser(out_axis_tuser)
    );
endmodule


//============================================================================
// PONG CONTROL - Logica di gioco modificata
//============================================================================

module pong_control #( `SVO_DEFAULT_PARAMS ) (
    input clk,
    input resetn,
    input enable,

    // Posizione diretta Player 1 (0-255 dal potenziometro)
    input [7:0] p1_paddle_pos,
    input        game_reset_ext,  // 外部重置 (KEY3)

    output flash,
    output reg   game_over,       // 任一方 >= 15 分
    output reg [11:0] p1_pos, p2_pos,
    output reg [6:0] p1_points, p2_points,
    output reg [11:0] puck_x, puck_y
);
    `SVO_DECLS

    //------------------------------------------------------------------------
    // Calcolo velocità ottimale per la pallina
    //------------------------------------------------------------------------
    function integer score_max_vy;
        input integer max_vx, max_vy, max_x, max_y;
        begin
            score_max_vy = (2*max_x*max_vy / max_vx) % (2*max_y) - max_y;
            score_max_vy = score_max_vy < 0 ? -score_max_vy : score_max_vy;
        end
    endfunction

    function integer best_max_vy;
        input integer max_vx, max_x, max_y, from_i, to_i;
        integer i;
        begin
            best_max_vy = from_i;
            for (i = from_i; i != to_i; i = i+1)
                if (score_max_vy(max_vx, i, max_x, max_y) < score_max_vy(max_vx, best_max_vy, max_x, max_y))
                    best_max_vy = i;
        end
    endfunction

    localparam max_vx = 15;
    localparam max_vy = best_max_vy(max_vx, SVO_HOR_PIXELS, SVO_VER_PIXELS, 8, 12);
    localparam WIN_SCORE = 15;  // 谁先到 15 分谁赢

    //------------------------------------------------------------------------
    // Parametri paddle
    //------------------------------------------------------------------------
    localparam PADDLE_HEIGHT = 100;
    localparam MAX_PADDLE_Y = SVO_VER_PIXELS - PADDLE_HEIGHT - 2;

    //------------------------------------------------------------------------
    // Registri di stato
    //------------------------------------------------------------------------
    reg signed [11:0] p1y, p2y;
    reg signed [4:0] p2vy;
    reg signed [11:0] px, py;
    reg signed [4:0] pvx, pvy;
    reg [7:0] rng_q;

    reg signed [11:0] ppx, ppy;
    reg pp_state;

    reg [3:0] flash_count;
    assign flash = |flash_count;

    reg [2:0] state;

    reg detect_left_paddle;
    reg detect_right_paddle;

    // game_over 检测 (15分)
    wire game_over_now = (p1_points >= WIN_SCORE) || (p2_points >= WIN_SCORE);

    //------------------------------------------------------------------------
    // Conversione posizione potenziometro → posizione paddle
    //------------------------------------------------------------------------
    // p1_paddle_pos: 0-255
    // p1y target: 0 a MAX_PADDLE_Y
    wire [11:0] p1_target = (p1_paddle_pos * MAX_PADDLE_Y) >> 8;

    //------------------------------------------------------------------------
    // Auto-pilot per Player 2
    //------------------------------------------------------------------------
    reg [1:0] auto_btn_p2;  // [1]=up, [0]=down

    //------------------------------------------------------------------------
    // Logica principale
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn)
            rng_q <= 1;
        else if (^{p1_paddle_pos, ppx, ppy})
            rng_q <= {rng_q[6:0], rng_q[7] ^ rng_q[5] ^ rng_q[4] ^ rng_q[3]};

        if (!resetn) begin
            flash_count <= 0;
            game_over   <= 0;
            p1_points <= 0;
            p2_points <= 0;
            p1_pos <= SVO_VER_PIXELS / 2 - 50;
            p2_pos <= SVO_VER_PIXELS / 2 - 50;
            puck_x <= SVO_HOR_PIXELS / 2;
            puck_y <= SVO_VER_PIXELS / 2;
            pp_state <= 0;
            state <= 0;

            px = SVO_HOR_PIXELS / 2;
            py = SVO_VER_PIXELS / 2;
            pvx = 3;
            pvy = 4;
            p1y = SVO_VER_PIXELS / 2 - 50;
            p2y = SVO_VER_PIXELS / 2 - 50;
            p2vy = 0;
            ppx = SVO_HOR_PIXELS / 2;
            ppy = SVO_VER_PIXELS / 2;
            auto_btn_p2 <= 0;

        end else if (game_reset_ext) begin
            // KEY3 外部重置: 归零所有状态
            flash_count <= 0;
            game_over   <= 0;
            p1_points <= 0;
            p2_points <= 0;
            p1_pos <= SVO_VER_PIXELS / 2 - 50;
            p2_pos <= SVO_VER_PIXELS / 2 - 50;
            puck_x <= SVO_HOR_PIXELS / 2;
            puck_y <= SVO_VER_PIXELS / 2;
            pp_state <= 0;
            state <= 0;
            px = SVO_HOR_PIXELS / 2;
            py = SVO_VER_PIXELS / 2;
            pvx = 3;
            pvy = 4;
            p1y = SVO_VER_PIXELS / 2 - 50;
            p2y = SVO_VER_PIXELS / 2 - 50;
            p2vy = 0;
            ppx = SVO_HOR_PIXELS / 2;
            ppy = SVO_VER_PIXELS / 2;
            auto_btn_p2 <= 0;

        end else if (game_over) begin
            // GAME OVER: 球停住, 分数开始高亮闪烁
            flash_count <= 6;  // 持续闪烁
            state <= 0;

        end else if (state == 0) begin
            // Handle goals (left) - P2 得分
            if (pvx < 0 && px < 5) begin
                px = SVO_HOR_PIXELS-6;
                pvx = rng_q[0] ? -2 : -3;
                pvy = pvy < 0 ? (rng_q[1] ? -3 : -4) : (rng_q[2] ? 3 : 4);
                if (p2_points < WIN_SCORE - 1)
                    p2_points <= p2_points + 1;
                else
                    game_over <= 1;  // P2 达到 15 分, 游戏结束
                flash_count <= 6;
            end
            state <= 1;

        end else if (state == 1) begin
            // Handle goals (right) - P1 得分
            if (pvx > 0 && px > SVO_HOR_PIXELS-6) begin
                px = 5;
                pvx = rng_q[0] ? 2 : 3;
                pvy = pvy < 0 ? (rng_q[1] ? -3 : -4) : (rng_q[2] ? 3 : 4);
                if (p1_points < WIN_SCORE - 1)
                    p1_points <= p1_points + 1;
                else
                    game_over <= 1;  // P1 达到 15 分, 游戏结束
                flash_count <= 6;
            end
            state <= 2;

        end else if (state == 2) begin
            // Move puck (1/3)
            px = px + pvx;
            py = py + pvy;

            if (py < 5) begin
                py = 2*5 - py;
                pvy = -pvy == max_vy ? max_vy : -pvy+1;
                pp_state <= 0;
            end else if (py > SVO_VER_PIXELS-6) begin
                py = 2*(SVO_VER_PIXELS-6) - py;
                pvy = pvy == max_vy ? -max_vy : -pvy-1;
                pp_state <= 0;
            end
            state <= 3;

        end else if (state == 3) begin
            // Move puck (2/3) - collision detection
            detect_left_paddle = pvx < 0 && 5 < px && px < 22 && p1y - 5 < py && py < p1y + 105;
            detect_right_paddle = pvx > 0 && SVO_HOR_PIXELS-23 < px && px < SVO_HOR_PIXELS-6 && p2y - 5 < py && py < p2y + 105;
            state <= 4;

        end else if (state == 4) begin
            // Move puck (3/3) - bounce off paddles
            if (detect_left_paddle) begin
                px = 2*22 - px;
                pvx = -pvx == max_vx ? max_vx : -pvx+1;
                pp_state <= 0;
            end else if (detect_right_paddle) begin
                px = 2*(SVO_HOR_PIXELS-23) - px;
                pvx = pvx == max_vx ? -max_vx : -pvx-1;
                pp_state <= 0;
            end
            state <= 5;

        end else if (state == 5) begin
            //----------------------------------------------------------
            // Player 1: CONTROLLO DIRETTO DA POTENZIOMETRO
            //----------------------------------------------------------
            // Movimento smooth verso la posizione target
            if (p1y < p1_target) begin
                p1y = p1y + 3;  // Velocità movimento
                if (p1y > p1_target) p1y = p1_target;
            end else if (p1y > p1_target) begin
                p1y = p1y - 3;
                if (p1y < p1_target) p1y = p1_target;
            end

            // Limiti
            if (p1y < 0) p1y = 0;
            if (p1y > MAX_PADDLE_Y) p1y = MAX_PADDLE_Y;

            state <= 6;

        end else if (state == 6) begin
            //----------------------------------------------------------
            // Player 2: AUTOPILOT
            //----------------------------------------------------------
            p2y = p2y + p2vy;
            if (p2y < 0) p2y = 0;
            if (p2y > MAX_PADDLE_Y) p2y = MAX_PADDLE_Y;

            p2vy = p2vy + auto_btn_p2[0] - auto_btn_p2[1];
            if (!auto_btn_p2 && p2vy)
                p2vy = p2vy < 0 ? p2vy+1 : p2vy-1;

            if (p2vy > +3) p2vy = +3;
            if (p2vy < -3) p2vy = -3;

            state <= 7;

        end else if (enable) begin
            //----------------------------------------------------------
            // Autopilot logic per Player 2
            //----------------------------------------------------------
            auto_btn_p2 <= 0;
            if (pvx > 0) begin  // Pallina va verso P2
                if (px > SVO_HOR_PIXELS - 60) begin  // 球很近了才启动 AI (只有最后60像素的水平距离)
                    if (ppy < p2y + 20) auto_btn_p2[1] <= 1;  // up (死区更大)
                    if (ppy > p2y + 80) auto_btn_p2[0] <= 1;  // down
                end
            end

            // Update output signals
            p1_pos <= p1y;
            p2_pos <= p2y;
            puck_x <= px < 5 ? 5 : px > SVO_HOR_PIXELS-6 ? SVO_HOR_PIXELS-6 : px;
            puck_y <= py;

            if (flash_count > 0) flash_count <= flash_count-1;
            state <= 0;

        end else begin
            //----------------------------------------------------------
            // Proiezione pallina per autopilot
            //----------------------------------------------------------
            if (!pp_state) begin
                ppx = px;
                ppy = py + $signed(rng_q[4:0]);
                pp_state <= 1;
            end else begin
                if (20 < ppx && ppx < SVO_HOR_PIXELS-21) begin
                    ppy = ppy + pvy;
                    ppx = ppx + pvx;
                end else if (ppy < 5)
                    ppy = 2*5 - ppy;
                else if (ppy > SVO_VER_PIXELS-6)
                    ppy = 2*(SVO_VER_PIXELS-6) - ppy;
            end
        end
    end
endmodule
