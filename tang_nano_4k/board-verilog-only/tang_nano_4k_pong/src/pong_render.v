//============================================================================
// PONG RENDERER - register driven video pipeline (Tang Nano 4K)
//============================================================================
//
// Copy of the SVO pong video composition pipeline (svo_pong_video), driven
// by register values written by the Cortex-M3 over the APB2 bridge.
//
// Clock domains:
//   - All *_raw inputs come from the 27 MHz APB domain and are
//     two-flop synchronized into this module's clock domain (clk_p).
//
// Flash/blink:
//   - flash_en (ctrl[0]) is set by the firmware when the game is over.
//   - A free running counter produces a ~0.75 Hz blink phase.
//   - A final svo_dim stage halves every pixel when NOT flashing, so the
//     whole screen is half bright during play and full bright when the
//     score blinks on game over.
//
//============================================================================
`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module pong_render #( `SVO_DEFAULT_PARAMS ) (
    input clk, resetn,

    // raw register values (27 MHz APB domain)
    input flash_en,
    input [11:0] p1_pos_raw,
    input [11:0] p2_pos_raw,
    input [11:0] puck_x_raw,
    input [11:0] puck_y_raw,
    input [6:0] p1_points_raw,
    input [6:0] p2_points_raw,

    // input stream (background, black)
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

    //----------------------------------------------------------------------
    // CDC: two-flop sync of every register value
    //----------------------------------------------------------------------
    reg [11:0] p1_pos_s, p1_pos;
    reg [11:0] p2_pos_s, p2_pos;
    reg [11:0] puck_x_s, puck_x;
    reg [11:0] puck_y_s, puck_y;
    reg [6:0] p1_points_s, p1_points;
    reg [6:0] p2_points_s, p2_points;
    reg flash_en_s, flash_en_sync;

    always @(posedge clk) begin
        p1_pos_s   <= p1_pos_raw;   p1_pos   <= p1_pos_s;
        p2_pos_s   <= p2_pos_raw;   p2_pos   <= p2_pos_s;
        puck_x_s   <= puck_x_raw;   puck_x   <= puck_x_s;
        puck_y_s   <= puck_y_raw;   puck_y   <= puck_y_s;
        p1_points_s<= p1_points_raw;p1_points<= p1_points_s;
        p2_points_s<= p2_points_raw;p2_points<= p2_points_s;
        flash_en_s <= flash_en;     flash_en_sync <= flash_en_s;
    end

    //----------------------------------------------------------------------
    // SOF-sampled latches: values are captured only on the first pixel of
    // each frame (sof), so all rect coordinates stay constant during the
    // whole frame. A value torn by the clock domain crossing can therefore
    // never flip the rect coordinates mid-frame (which made svo_rect draw
    // a full-height stripe when y1 > y2).
    //----------------------------------------------------------------------
    wire sof = in_axis_tvalid && in_axis_tready && in_axis_tuser[0];

    reg [11:0] p1_pos_l, p2_pos_l, puck_x_l, puck_y_l;
    reg [6:0] p1_points_l, p2_points_l;
    reg flash_en_l;

    always @(posedge clk) begin
        if (sof) begin
            p1_pos_l    <= p1_pos;
            p2_pos_l    <= p2_pos;
            puck_x_l    <= puck_x;
            puck_y_l    <= puck_y;
            p1_points_l <= p1_points;
            p2_points_l <= p2_points;
            flash_en_l  <= flash_en_sync;
        end
    end

    //----------------------------------------------------------------------
    // Score blink phase (~0.75 Hz full cycles at 25.2 MHz)
    //----------------------------------------------------------------------
    reg [24:0] blink_cnt;
    always @(posedge clk)
        blink_cnt <= blink_cnt + 1'b1;

    wire flash = flash_en_l && blink_cnt[23];

    //----------------------------------------------------------------------
    // Rectangle coordinates (from SOF-latched values, clamped into the
    // visible area so y1 < y2 and x1 < x2 always hold)
    //----------------------------------------------------------------------
    reg [11:0] rect1_x1, rect1_x2, rect1_y1, rect1_y2;
    reg [11:0] rect2_x1, rect2_x2, rect2_y1, rect2_y2;
    reg [11:0] rect3_x1, rect3_x2, rect3_y1, rect3_y2;

    wire [11:0] p1_y = (p1_pos_l > SVO_VER_PIXELS - 100) ? (SVO_VER_PIXELS - 100) : p1_pos_l;
    wire [11:0] p2_y = (p2_pos_l > SVO_VER_PIXELS - 100) ? (SVO_VER_PIXELS - 100) : p2_pos_l;
    wire [11:0] bx = (puck_x_l > SVO_HOR_PIXELS) ? SVO_HOR_PIXELS : puck_x_l;
    wire [11:0] by = (puck_y_l > SVO_VER_PIXELS) ? SVO_VER_PIXELS : puck_y_l;

    always @(posedge clk) begin
        rect1_x1 <= 10;
        rect1_x2 <= 20;
        rect1_y1 <= p1_y;
        rect1_y2 <= p1_y + 100;

        rect2_x1 <= SVO_HOR_PIXELS - 20;
        rect2_x2 <= SVO_HOR_PIXELS - 10;
        rect2_y1 <= p2_y;
        rect2_y2 <= p2_y + 100;

        rect3_x1 <= (bx >= 5) ? bx - 5 : 0;
        rect3_x2 <= (bx < SVO_HOR_PIXELS) ? bx + 5 : SVO_HOR_PIXELS;
        rect3_y1 <= (by >= 5) ? by - 5 : 0;
        rect3_y2 <= (by < SVO_VER_PIXELS) ? by + 5 : SVO_VER_PIXELS;
    end

    //----------------------------------------------------------------------
    // Video pipeline (svo_pong_video + final whole-screen dim stage)
    //----------------------------------------------------------------------
    localparam s_maxidx = 10;

    wire s_tvalid [0:s_maxidx], s_tready [0:s_maxidx];
    wire [SVO_BITS_PER_PIXEL-1:0] s_tdata [0:s_maxidx];
    wire [2:0] s_tuser [0:s_maxidx];

    assign s_tvalid[0] = in_axis_tvalid;
    assign in_axis_tready = s_tready[0];
    assign s_tdata[0] = in_axis_tdata;
    assign s_tuser[0] = in_axis_tuser;

    `define IN(_idx, _ubits)   .in_axis_tvalid(s_tvalid[_idx]),   .in_axis_tready(s_tready[_idx]),   .in_axis_tdata(s_tdata[_idx]),   .in_axis_tuser(s_tuser[_idx][(_ubits)-1:0])
    `define OVER(_idx, _ubits) .over_axis_tvalid(s_tvalid[_idx]), .over_axis_tready(s_tready[_idx]), .over_axis_tdata(s_tdata[_idx]), .over_axis_tuser(s_tuser[_idx][(_ubits)-1:0])
    `define OUT(_idx, _ubits)  .out_axis_tvalid(s_tvalid[_idx]),  .out_axis_tready(s_tready[_idx]),  .out_axis_tdata(s_tdata[_idx]),  .out_axis_tuser(s_tuser[_idx][(_ubits)-1:0])

    // stage 1: alignment buffer (base stream is black, no dim needed here)
    svo_dim #( `SVO_PASS_PARAMS ) compose_1 (
        .clk(clk), .resetn(resetn),
        .enable(1'b0),
        `IN(0, 1), `OUT(1, 1)
    );

    // stage 2: player 1 paddle rectangle
    svo_rect #( `SVO_PASS_PARAMS ) compose_2 (
        .clk(clk), .resetn(resetn),
        .x1(rect1_x1), .y1(rect1_y1),
        .x2(rect1_x2), .y2(rect1_y2),
        `OUT(2, 3)
    );

    svo_overlay #( `SVO_PASS_PARAMS ) compose_3 (
        .clk(clk), .resetn(resetn), .enable(1'b1),
        `IN(1, 1), `OVER(2, 2), `OUT(3, 1)
    );

    // stage 4: player 2 paddle rectangle
    svo_rect #( `SVO_PASS_PARAMS ) compose_4 (
        .clk(clk), .resetn(resetn),
        .x1(rect2_x1), .y1(rect2_y1),
        .x2(rect2_x2), .y2(rect2_y2),
        `OUT(4, 3)
    );

    svo_overlay #( `SVO_PASS_PARAMS ) compose_5 (
        .clk(clk), .resetn(resetn), .enable(1'b1),
        `IN(3, 1), `OVER(4, 2), `OUT(5, 1)
    );

    // stage 6: score digits (latched + clamped)
    wire [6:0] p1_pts_c = (p1_points_l > 7'd15) ? 7'd15 : p1_points_l;
    wire [6:0] p2_pts_c = (p2_points_l > 7'd15) ? 7'd15 : p2_points_l;

    pong_scores #( `SVO_PASS_PARAMS ) compose_6 (
        .clk(clk), .resetn(resetn),
        .p1_points(p1_pts_c),
        .p2_points(p2_pts_c),
        `OUT(6, 2)
    );

    svo_overlay #( `SVO_PASS_PARAMS ) compose_7 (
        .clk(clk), .resetn(resetn), .enable(1'b1),
        `IN(5, 1), `OVER(6, 2), `OUT(7, 1)
    );

    // stage 8: ball rectangle
    svo_rect #( `SVO_PASS_PARAMS ) compose_8 (
        .clk(clk), .resetn(resetn),
        .x1(rect3_x1), .y1(rect3_y1),
        .x2(rect3_x2), .y2(rect3_y2),
        `OUT(8, 3)
    );

    svo_overlay #( `SVO_PASS_PARAMS ) compose_9 (
        .clk(clk), .resetn(resetn), .enable(1'b1),
        `IN(7, 1), `OVER(8, 2), `OUT(9, 1)
    );

    // stage 10: whole-screen dim. Half bright during play,
    //           full bright while the score blinks on game over.
    svo_dim #( `SVO_PASS_PARAMS ) compose_10 (
        .clk(clk), .resetn(resetn),
        .enable(!flash),
        `IN(9, 1), `OUT(10, 1)
    );

    `undef IN
    `undef OVER
    `undef OUT

    assign out_axis_tvalid = s_tvalid[s_maxidx];
    assign s_tready[s_maxidx] = out_axis_tready;
    assign out_axis_tdata = s_tdata[s_maxidx];
    assign out_axis_tuser = s_tuser[s_maxidx];
endmodule


// ----------------------------------------------------------------------
// module pong_scores
//
// creates the overlay video stream with the current score
// (renamed copy of svo_pong_scores)
// ----------------------------------------------------------------------

module pong_scores #( `SVO_DEFAULT_PARAMS ) (
    input clk, resetn,

    input [6:0] p1_points, p2_points,

    // output stream
    //   tuser[0] ... start of frame
    output out_axis_tvalid,
    input out_axis_tready,
    output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
    output [1:0] out_axis_tuser
);
    `SVO_DECLS

    wire pipeline_enable = out_axis_tready || !out_axis_tvalid;

    reg [3:0] digit0, digit1, digit2, digit3;

    always @(posedge clk) begin
        digit0 = p1_points / 10;
        digit1 = p1_points % 10;
        digit2 = p2_points / 10;
        digit3 = p2_points % 10;
    end

    // ----------------------------------------------------------
    // first pipeline stage: create stream of x/y coordinates

    reg p1_valid;
    reg [`SVO_XYBITS-1:0] p1_x;
    reg [`SVO_XYBITS-1:0] p1_y;

    always @(posedge clk) begin:p1
        if (!resetn) begin
            p1_valid <= 0;
            p1_x <= 0;
            p1_y <= 0;
        end else if (pipeline_enable) begin
            if (p1_valid) begin
                if (p1_x == SVO_HOR_PIXELS-1) begin
                    p1_x <= 0;
                    p1_y <= (p1_y == SVO_VER_PIXELS-1) ? 0 : p1_y + 1;
                end else begin
                    p1_x <= p1_x + 1;
                end
            end else
                p1_valid <= 1;
        end
    end


    // ----------------------------------------------------------
    // second stage: translate into relative digit coordinates

    reg p2_valid;
    reg p2_fstart;
    reg p2_outside;
    reg [1:0] p2_digit;
    reg [7:0] p2_x;
    reg [7:0] p2_y;

    localparam digit0_xoff =  80;
    localparam digit1_xoff = 180;
    localparam digit2_xoff = SVO_HOR_PIXELS - 270;
    localparam digit3_xoff = SVO_HOR_PIXELS - 170;

    localparam digit0_yoff = 15;
    localparam digit1_yoff = 15;
    localparam digit2_yoff = 15;
    localparam digit3_yoff = 15;

    localparam digit_width = 3*30 + 1;
    localparam digit_height = 5*30 + 1;

    always @(posedge clk) begin:p2
        if (!resetn) begin
            p2_valid <= 0;
        end else if (pipeline_enable) begin
            p2_valid <= p1_valid;
            p2_fstart <= !p1_x && !p1_y;
            if (digit0_xoff <= p1_x && p1_x < digit0_xoff + digit_width &&
                digit0_yoff <= p1_y && p1_y < digit0_yoff + digit_height) begin
                p2_outside <= 0;
                p2_digit <= 0;
                p2_x <= p1_x - digit0_xoff;
                p2_y <= p1_y - digit0_yoff;
            end else
            if (digit1_xoff <= p1_x && p1_x < digit1_xoff + digit_width &&
                digit1_yoff <= p1_y && p1_y < digit1_yoff + digit_height) begin
                p2_outside <= 0;
                p2_digit <= 1;
                p2_x <= p1_x - digit1_xoff;
                p2_y <= p1_y - digit1_yoff;
            end else
            if (digit2_xoff <= p1_x && p1_x < digit2_xoff + digit_width &&
                digit2_yoff <= p1_y && p1_y < digit2_yoff + digit_height) begin
                p2_outside <= 0;
                p2_digit <= 2;
                p2_x <= p1_x - digit2_xoff;
                p2_y <= p1_y - digit2_yoff;
            end else
            if (digit3_xoff <= p1_x && p1_x < digit3_xoff + digit_width &&
                digit3_yoff <= p1_y && p1_y < digit3_yoff + digit_height) begin
                p2_outside <= 0;
                p2_digit <= 3;
                p2_x <= p1_x - digit3_xoff;
                p2_y <= p1_y - digit3_yoff;
            end else begin
                p2_outside <= 1;
                p2_digit <= 'bx;
                p2_x <= 'bx;
                p2_y <= 'bx;
            end
        end
    end


    // ----------------------------------------------------------
    // third stage: translate into coarse grid coordinates

    reg p3_valid;
    reg p3_fstart;
    reg p3_outside;
    reg [1:0] p3_digit;
    reg [3:0] p3_value;
    reg [2:0] p3_x;
    reg [3:0] p3_y;

    always @(posedge clk) begin:p3
        reg [3:0] per_digit_y [0:3];
        if (!resetn) begin
            p3_valid <= 0;
        end else if (pipeline_enable) begin
            p3_valid <= p2_valid;
            p3_fstart <= p2_fstart;
            p3_outside <= p2_outside;
            p3_digit <= p2_digit;

            case (p2_x)
                 0: p3_x <= 0;
                30: p3_x <= 2;
                60: p3_x <= 4;
                90: p3_x <= 6;
            default:
                case (p3_x)
                    0: p3_x <= 1;
                    2: p3_x <= 3;
                    4: p3_x <= 5;
                endcase
            endcase

            if (!p2_outside) begin
                case (p2_y)
                      0: per_digit_y[p2_digit] =  0;
                     30: per_digit_y[p2_digit] =  2;
                     60: per_digit_y[p2_digit] =  4;
                     90: per_digit_y[p2_digit] =  6;
                    120: per_digit_y[p2_digit] =  8;
                    150: per_digit_y[p2_digit] = 10;
                default:
                    case (per_digit_y[p2_digit])
                        0: per_digit_y[p2_digit] = 1;
                        2: per_digit_y[p2_digit] = 3;
                        4: per_digit_y[p2_digit] = 5;
                        6: per_digit_y[p2_digit] = 7;
                        8: per_digit_y[p2_digit] = 9;
                    endcase
                endcase
            end

            p3_y <= per_digit_y[p2_digit];

            case (p2_digit)
                0: p3_value <= digit0;
                1: p3_value <= digit1;
                2: p3_value <= digit2;
                3: p3_value <= digit3;
            endcase
        end
    end


    // ----------------------------------------------------------
    // stage four: calc font addresses

    reg p4_valid;
    reg p4_fstart;
    reg p4_outside;
    reg p4_ongrid;
    reg [1:0] p4_digit;
    reg [3:0] p4_value;
    reg [3:0] p4_addr;
    reg [3:0] p4_addr_left_up;
    reg [3:0] p4_addr_right_up;
    reg [3:0] p4_addr_left_down;
    reg [3:0] p4_addr_right_down;

    always @(posedge clk) begin:p4
        reg [1:0] x_left;
        reg [1:0] x_right;
        reg [2:0] y_up;
        reg [2:0] y_down;
        if (!resetn) begin
            p4_valid <= 0;
        end else if (pipeline_enable) begin
            p4_valid <= p3_valid;
            p4_fstart <= p3_fstart;
            p4_outside <= p3_outside;
            p4_ongrid <= !p3_y[0] || !p3_x[0];
            p4_digit <= p3_digit;
            p4_value <= p3_value;

            case (p3_x)
                0: begin x_left = 3; x_right = 0; end
                1: begin x_left = 0; x_right = 0; end
                2: begin x_left = 0; x_right = 1; end
                3: begin x_left = 1; x_right = 1; end
                4: begin x_left = 1; x_right = 2; end
                5: begin x_left = 2; x_right = 2; end
                6: begin x_left = 2; x_right = 3; end
            endcase

            case (p3_y)
                 0: begin y_up = 7; y_down = 0; end
                 1: begin y_up = 0; y_down = 0; end
                 2: begin y_up = 0; y_down = 1; end
                 3: begin y_up = 1; y_down = 1; end
                 4: begin y_up = 1; y_down = 2; end
                 5: begin y_up = 2; y_down = 2; end
                 6: begin y_up = 2; y_down = 3; end
                 7: begin y_up = 3; y_down = 3; end
                 8: begin y_up = 3; y_down = 4; end
                 9: begin y_up = 4; y_down = 4; end
                10: begin y_up = 4; y_down = 7; end
            endcase

            p4_addr <= p3_y[3:1] + p3_x[2:1]*5;
            p4_addr_left_up    <= x_left  != 3 && y_up   != 7 ? y_up   + x_left  * 5 : 15;
            p4_addr_right_up   <= x_right != 3 && y_up   != 7 ? y_up   + x_right * 5 : 15;
            p4_addr_left_down  <= x_left  != 3 && y_down != 7 ? y_down + x_left  * 5 : 15;
            p4_addr_right_down <= x_right != 3 && y_down != 7 ? y_down + x_right * 5 : 15;
        end
    end


    // ----------------------------------------------------------
    // stage five: translate to rgb values

    reg p5_valid;
    reg p5_fstart;
    reg p5_outside;
    reg [SVO_BITS_PER_PIXEL-1:0] p5_color;

    reg [15:0] font [0:9];

    initial begin
        font[0] = { 1'b0,
            5'b 11111,
            5'b 10001,
            5'b 11111
        };
        font[1] = { 1'b0,
            5'b 00000,
            5'b 11111,
            5'b 00000
        };
        font[2] = { 1'b0,
            5'b 10111,
            5'b 10101,
            5'b 11101
        };
        font[3] = { 1'b0,
            5'b 11111,
            5'b 10101,
            5'b 10101
        };
        font[4] = { 1'b0,
            5'b 11111,
            5'b 00100,
            5'b 00111
        };
        font[5] = { 1'b0,
            5'b 11101,
            5'b 10101,
            5'b 10111
        };
        font[6] = { 1'b0,
            5'b 11101,
            5'b 10101,
            5'b 11111
        };
        font[7] = { 1'b0,
            5'b 11111,
            5'b 00001,
            5'b 00001
        };
        font[8] = { 1'b0,
            5'b 11111,
            5'b 10101,
            5'b 11111
        };
        font[9] = { 1'b0,
            5'b 11111,
            5'b 10101,
            5'b 10111
        };
    end

    always @(posedge clk) begin:p5
        reg [3:0] neigh;
        if (!resetn) begin
            p5_valid <= 0;
        end else if (pipeline_enable) begin
            p5_valid <= p4_valid;
            p5_fstart <= p4_fstart;
            if (p4_ongrid) begin
                neigh[0] = font[p4_value][p4_addr_left_up];
                neigh[1] = font[p4_value][p4_addr_right_up];
                neigh[2] = font[p4_value][p4_addr_left_down];
                neigh[3] = font[p4_value][p4_addr_right_down];
                if (&neigh) begin
                    p5_outside <= p4_outside;
                    p5_color <= ~0;
                end else
                if (|neigh) begin
                    p5_outside <= p4_outside;
                    p5_color <= 0;
                end else begin
                    p5_outside <= 1;
                    p5_color <= 'bx;
                end
            end else begin
                p5_outside <= p4_outside || !font[p4_value][p4_addr];
                p5_color <= ~0;
            end
        end
    end

    // ----------------------------------------------------------

    assign out_axis_tvalid = p5_valid;
    assign out_axis_tuser = {!p5_outside, p5_fstart};
    assign out_axis_tdata = p5_color;
endmodule


//============================================================================
// BACKGROUND GENERATOR - Black background
//============================================================================
module background_gen #(
    parameter SVO_MODE             = "640x480",
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
