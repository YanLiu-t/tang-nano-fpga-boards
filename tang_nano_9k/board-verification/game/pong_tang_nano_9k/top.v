//============================================================================
// TOP MODULE - Pong for Tang Nano 9K (Keyboard Version)
//============================================================================
// 控制: Player 1 = 8键键盘 (KEY1↑, KEY2↓)
//       Player 2 = AI (自动对战)
// 输出: HDMI @ 1024x600 @ 60Hz
//============================================================================
`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module top(
    //----------------------------------------------------------------------
    // Clock & Reset
    //----------------------------------------------------------------------
    input clk,              // 27 MHz from crystal
    input resetn,           // Reset button (active low)

    //----------------------------------------------------------------------
    // Keyboard (74HC165 shift register)
    //----------------------------------------------------------------------
    output keyboard_pl,     // Parallel Load  (Pin 48)
    output keyboard_cp,     // Clock          (Pin 49)
    input  keyboard_q7,     // Serial Data    (Pin 47)

    //----------------------------------------------------------------------
    // HDMI Output (differential)
    //----------------------------------------------------------------------
    output tmds_clk_n,
    output tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

//============================================================================
// VIDEO PARAMETERS
//============================================================================
parameter SVO_MODE             = "640x480";
parameter SVO_FRAMERATE        = 60;
parameter SVO_BITS_PER_PIXEL   = 24;
parameter SVO_BITS_PER_RED     = 8;
parameter SVO_BITS_PER_GREEN   = 8;
parameter SVO_BITS_PER_BLUE    = 8;
parameter SVO_BITS_PER_ALPHA   = 0;

//============================================================================
// INTERNAL SIGNALS
//============================================================================
wire pll_lock;
wire clk_p5;            // 250 MHz
wire clk_p;             // 50 MHz pixel clock
wire sys_resetn;

//============================================================================
// PLL - Generate 250 MHz
//============================================================================
Gowin_rPLL pll_inst (
    .clkout(clk_p5),
    .lock(pll_lock),
    .clkin(clk)
);

//============================================================================
// CLOCK DIVIDER - 250 MHz / 5 = 50 MHz
//============================================================================
Gowin_CLKDIV clkdiv_inst (
    .clkout(clk_p),
    .hclkin(clk_p5),
    .resetn(pll_lock)
);

//============================================================================
// RESET SYNC
//============================================================================
Reset_Sync reset_sync_inst (
    .resetn(sys_resetn),
    .ext_reset(resetn & pll_lock),
    .clk(clk_p)
);

//============================================================================
// KEYBOARD (74HC165) - Read 8 keys
//============================================================================
wire [7:0] keys;
wire keys_valid;

keyboard_74hc165 u_keyboard (
    .clk    (clk_p),
    .resetn (sys_resetn),
    .pl     (keyboard_pl),
    .cp     (keyboard_cp),
    .q7     (keyboard_q7),
    .keys   (keys),
    .valid  (keys_valid)
);

//============================================================================
// PADDLE CONTROL - Convert keys to paddle position (0-255)
//============================================================================
wire [7:0] paddle_pos;
wire       game_reset;  // KEY3 触发游戏重置

paddle_ctrl u_paddle_ctrl (
    .clk        (clk_p),
    .resetn     (sys_resetn),
    .keys       (keys),
    .keys_valid (keys_valid),
    .paddle_pos (paddle_pos),
    .game_reset (game_reset)
);

//============================================================================
// BACKGROUND GENERATOR (black)
//============================================================================
wire bg_tvalid, bg_tready;
wire [SVO_BITS_PER_PIXEL-1:0] bg_tdata;
wire [0:0] bg_tuser;

background_gen #( `SVO_PASS_PARAMS ) bg_inst (
    .clk(clk_p),
    .resetn(sys_resetn),
    .out_axis_tvalid(bg_tvalid),
    .out_axis_tready(bg_tready),
    .out_axis_tdata(bg_tdata),
    .out_axis_tuser(bg_tuser)
);

//============================================================================
// PONG GAME
//============================================================================
wire pong_tvalid, pong_tready;
wire [SVO_BITS_PER_PIXEL-1:0] pong_tdata;
wire [0:0] pong_tuser;

pong_game #( `SVO_PASS_PARAMS ) pong_inst (
    .clk(clk_p),
    .resetn(sys_resetn),
    .resetn_game(resetn),   // Button resets the game
    .enable(1'b1),
    .p1_paddle_pos(paddle_pos),
    .game_reset_ext(game_reset),
    .in_axis_tvalid(bg_tvalid),
    .in_axis_tready(bg_tready),
    .in_axis_tdata(bg_tdata),
    .in_axis_tuser(bg_tuser),
    .out_axis_tvalid(pong_tvalid),
    .out_axis_tready(pong_tready),
    .out_axis_tdata(pong_tdata),
    .out_axis_tuser(pong_tuser)
);

//============================================================================
// VIDEO ENCODER (timing HSync/VSync)
//============================================================================
wire enc_tvalid, enc_tready;
wire [SVO_BITS_PER_PIXEL-1:0] enc_tdata;
wire [3:0] enc_tuser;

svo_enc #( `SVO_PASS_PARAMS ) enc_inst (
    .clk(clk_p),
    .resetn(sys_resetn),
    .in_axis_tvalid(pong_tvalid),
    .in_axis_tready(pong_tready),
    .in_axis_tdata(pong_tdata),
    .in_axis_tuser(pong_tuser),
    .out_axis_tvalid(enc_tvalid),
    .out_axis_tready(enc_tready),
    .out_axis_tdata(enc_tdata),
    .out_axis_tuser(enc_tuser)
);
assign enc_tready = 1;

//============================================================================
// TMDS ENCODER (3 channels)
//============================================================================
wire [2:0] tmds_d;
wire [2:0] tmds_d0, tmds_d1, tmds_d2, tmds_d3, tmds_d4;
wire [2:0] tmds_d5, tmds_d6, tmds_d7, tmds_d8, tmds_d9;

// Channel 0: Blue + control
svo_tmds tmds_0 (
    .clk(clk_p),
    .resetn(sys_resetn),
    .de(!enc_tuser[3]),
    .ctrl(enc_tuser[2:1]),
    .din(enc_tdata[23:16]),
    .dout({tmds_d9[0], tmds_d8[0], tmds_d7[0], tmds_d6[0], tmds_d5[0],
           tmds_d4[0], tmds_d3[0], tmds_d2[0], tmds_d1[0], tmds_d0[0]})
);

// Channel 1: Green
svo_tmds tmds_1 (
    .clk(clk_p),
    .resetn(sys_resetn),
    .de(!enc_tuser[3]),
    .ctrl(2'b0),
    .din(enc_tdata[15:8]),
    .dout({tmds_d9[1], tmds_d8[1], tmds_d7[1], tmds_d6[1], tmds_d5[1],
           tmds_d4[1], tmds_d3[1], tmds_d2[1], tmds_d1[1], tmds_d0[1]})
);

// Channel 2: Red
svo_tmds tmds_2 (
    .clk(clk_p),
    .resetn(sys_resetn),
    .de(!enc_tuser[3]),
    .ctrl(2'b0),
    .din(enc_tdata[7:0]),
    .dout({tmds_d9[2], tmds_d8[2], tmds_d7[2], tmds_d6[2], tmds_d5[2],
           tmds_d4[2], tmds_d3[2], tmds_d2[2], tmds_d1[2], tmds_d0[2]})
);

//============================================================================
// SERIALIZER 10:1
//============================================================================
OSER10 tmds_serdes [2:0] (
    .Q(tmds_d),
    .D0(tmds_d0), .D1(tmds_d1), .D2(tmds_d2), .D3(tmds_d3), .D4(tmds_d4),
    .D5(tmds_d5), .D6(tmds_d6), .D7(tmds_d7), .D8(tmds_d8), .D9(tmds_d9),
    .PCLK(clk_p),
    .FCLK(clk_p5),
    .RESET(~sys_resetn)
);

//============================================================================
// OUTPUT BUFFER DIFFERENTIAL
//============================================================================
ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_p, tmds_d}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

endmodule


//============================================================================
// BACKGROUND GENERATOR - Black background
//============================================================================
module background_gen #(
    parameter SVO_MODE             = "1024x600",
    parameter SVO_FRAMERATE        = 60,
    parameter SVO_BITS_PER_PIXEL   = 24,
    parameter SVO_BITS_PER_RED     = 8,
    parameter SVO_BITS_PER_GREEN   = 8,
    parameter SVO_BITS_PER_BLUE    = 8,
    parameter SVO_BITS_PER_ALPHA   = 0
) (
    input clk,
    input resetn,
    output reg out_axis_tvalid,
    input out_axis_tready,
    output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
    output reg [0:0] out_axis_tuser
);
    `SVO_DECLS
    reg [`SVO_XYBITS-1:0] x, y;
    assign out_axis_tdata = 24'h000000;
    always @(posedge clk) begin
        if (!resetn) begin
            out_axis_tvalid <= 0;
            out_axis_tuser <= 0;
            x <= 0;
            y <= 0;
        end else if (!out_axis_tvalid || out_axis_tready) begin
            out_axis_tvalid <= 1;
            out_axis_tuser <= (x == 0 && y == 0);
            if (x == SVO_HOR_PIXELS - 1) begin
                x <= 0;
                if (y == SVO_VER_PIXELS - 1)
                    y <= 0;
                else
                    y <= y + 1;
            end else begin
                x <= x + 1;
            end
        end
    end
endmodule


//============================================================================
// RESET SYNC
//============================================================================
module Reset_Sync (
    input clk,
    input ext_reset,
    output resetn
);
    reg [3:0] reset_cnt = 0;
    always @(posedge clk or negedge ext_reset) begin
        if (~ext_reset)
            reset_cnt <= 4'b0;
        else
            reset_cnt <= reset_cnt + !resetn;
    end
    assign resetn = &reset_cnt;
endmodule
