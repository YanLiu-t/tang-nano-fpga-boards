//============================================================================
// APB2 SLAVE REGISTER BRIDGE - Pong (Tang Nano 4K)
//============================================================================
//
// Runs in the EMPU APB2 master clock domain (master_pclk, 27 MHz).
// The Cortex-M3 firmware reads/writes these registers to control the
// renderer and to read the keyboard.
//
// Register map:
//   0x00 CTRL        RW bit0 = flash_en (score blink on game over)
//   0x04 KEY         RO inverted key values, key[0]=KEY1 key[1]=KEY2 key[2]=KEY3
//   0x08 P1_PADDLE   RW [11:0]   (kept for debug, no longer used by the renderer)
//   0x0C P2_PADDLE   RW [11:0]
//   0x10 BALL_X      RW [11:0]
//   0x14 BALL_Y      RW [11:0]
//   0x18 SCORE1      RW [6:0]
//   0x1C SCORE2      RW [6:0]
//   0x20 GAME_STATE  RO bit0 = game_over (score1>=15 || score2>=15)
//   0x24 FB_ADDR     RW [13:0] word index (0..599), 32 pixels per word
//   0x28 FB_DATA     RW [31:0] write data; writing this toggles fb_req
//   0x2C FB_STATUS   RO bit0 = fb_ack sync, bit1 = fb_req sync
//
// Framebuffer write handshake (LEVEL, see framebuffer.v):
//   C writes FB_ADDR, then FB_DATA (fb_req toggles). The framebuffer two-flop
//   synchronizes addr/data/req into the pixel-clock domain, stores the word
//   and toggles ack. C polls FB_STATUS bit0 until it matches the toggled req.
//
// NOTE: prdata is a COMBINATIONAL mux and pready is tied high, so the
// master samples stable read data on the APB setup phase.
//
//============================================================================

module apb_pong_reg (
    input  wire        pclk,
    input  wire        presetn,        // fabric reset synced to pclk domain

    // APB2 slave interface
    input  wire        psel,
    input  wire        penable,
    input  wire [7:0]  paddr,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Inputs
    input  wire [7:0]  keys_raw,       // from keyboard (Q7-first order)

    // Register outputs
    output reg  [11:0] p1_paddle,
    output reg  [11:0] p2_paddle,
    output reg  [11:0] ball_x,
    output reg  [11:0] ball_y,
    output reg  [6:0]  score1,
    output reg  [6:0]  score2,
    output reg  [7:0]  ctrl,

    // Frame-buffer write window (level handshake, see framebuffer.v)
    output reg  [13:0] fb_addr,
    output reg  [31:0] fb_data,
    output reg         fb_req,         // toggles once per written word
    input  wire        fb_ack          // toggles once per stored word
);

    //----------------------------------------------------------------------
    // APB protocol (always ready, no decode errors)
    //----------------------------------------------------------------------
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    //----------------------------------------------------------------------
    // Key inversion: 74HC165 shifts D7 first, so keys_raw[0] holds KEY8.
    // Reversing gives key_reg[0]=KEY1, key_reg[1]=KEY2, key_reg[2]=KEY3.
    // Key pressed = 0 (active low).
    //----------------------------------------------------------------------
    wire [7:0] key_reg = {keys_raw[0], keys_raw[1], keys_raw[2], keys_raw[3],
                          keys_raw[4], keys_raw[5], keys_raw[6], keys_raw[7]};

    //----------------------------------------------------------------------
    // Framebuffer handshake sync (clk_p <-> pclk)
    //   ack_s0/ack_s1: 2-flop sync of fb_ack from the pixel-clock domain.
    //   req_s0/req_s1: same-domain pipeline of fb_req, so FB_STATUS read
    //                  timing matches ack_s1.
    //----------------------------------------------------------------------
    reg ack_s0, ack_s1;
    reg req_s0, req_s1;
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ack_s0 <= 0; ack_s1 <= 0;
            req_s0 <= 0; req_s1 <= 0;
        end else begin
            ack_s0 <= fb_ack; ack_s1 <= ack_s0;
            req_s0 <= fb_req; req_s1 <= req_s0;
        end
    end

    //----------------------------------------------------------------------
    // Combinational read mux (no registered read data race)
    //----------------------------------------------------------------------
    always @(*) begin
        case (paddr)
            8'h00: prdata = {24'b0, ctrl};
            8'h04: prdata = {24'b0, key_reg};
            8'h08: prdata = {20'b0, p1_paddle};
            8'h0C: prdata = {20'b0, p2_paddle};
            8'h10: prdata = {20'b0, ball_x};
            8'h14: prdata = {20'b0, ball_y};
            8'h18: prdata = {25'b0, score1};
            8'h1C: prdata = {25'b0, score2};
            8'h20: prdata = {31'b0, (score1 >= 7'd15) || (score2 >= 7'd15)};
            8'h2C: prdata = {30'b0, req_s1, ack_s1};
            default: prdata = 32'b0;
        endcase
    end

    //----------------------------------------------------------------------
    // Writes + hardware defaults (screen is already sane before CPU runs)
    //----------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ctrl      <= 8'h00;
            p1_paddle <= 12'd190;
            p2_paddle <= 12'd190;
            ball_x    <= 12'd320;
            ball_y    <= 12'd240;
            score1    <= 7'd0;
            score2    <= 7'd0;
            fb_addr   <= 14'd0;
            fb_data   <= 32'd0;
            fb_req    <= 1'b0;
        end else if (psel && penable && pwrite) begin
            case (paddr)
                8'h00: ctrl      <= pwdata[7:0];
                8'h08: p1_paddle <= pwdata[11:0];
                8'h0C: p2_paddle <= pwdata[11:0];
                8'h10: ball_x    <= pwdata[11:0];
                8'h14: ball_y    <= pwdata[11:0];
                8'h18: score1    <= pwdata[6:0];
                8'h1C: score2    <= pwdata[6:0];
                8'h24: fb_addr   <= pwdata[13:0];
                8'h28: begin
                          fb_data <= pwdata;
                          fb_req  <= ~fb_req;   /* toggle: one word written */
                      end
                default: ;
            endcase
        end
    end

endmodule
