//============================================================================
// APB2 SLAVE REGISTER BRIDGE - Color Pong (Tang Nano 4K, PSRAM framebuffer)
//============================================================================
//
// Runs in the EMPU APB2 master clock domain (master_pclk, 27 MHz).
// The Cortex-M3 firmware reads keys and renders RGB888 pixels into the
// HyperRAM framebuffer through this bridge.
//
// Register map:
//   0x04 KEY        RO key values, key[0]=KEY1 key[1]=KEY2 key[2]=KEY3
//                      (pressed = 0)
//   0x08 HP_STATUS  RO bit0 = HyperRAM init_calib done (2-flop synced)
//   0x0C FRAME      RO [7:0] display frame counter, +1 per 640x480 frame
//                      (2-flop synced; firmware polls it for the 60 Hz tick)
//   0x24 FB_BLK     WO [12:0] 128-byte block index (0..7199); sets the
//                      target of the next 32 FB_DATA writes
//   0x28 FB_DATA    WO [31:0] one framebuffer word; writing toggles fb_req
//   0x2C FB_STATUS  RO bit0 = fb_ack sync, bit1 = fb_req sync
//   0x30 BUF_SWAP   WO write toggles: ask the fabric to flip the displayed
//                      framebuffer at the next frame boundary (double buffer)
//   0x34 BUF_DISP   RO bit0 = framebuffer currently being scanned out (0/1)
//                      (2-flop synced from the hp_clkout domain)
//   0x38 FB_READY   WO write toggles: the framebuffer now holds a whole
//                      composed scene; the fabric uses the FIRST toggle to
//                      stop blanking the HDMI output (no power-up garbage)
//   0x40 SP_P1_Y    WO [9:0] P1 paddle top row  (hardware sprite overlay)
//   0x44 SP_P2_Y    WO [9:0] P2 paddle top row  (hardware sprite overlay)
//   0x48 SP_BALL_X  WO [9:0] ball centre x      (hardware sprite overlay)
//   0x4C SP_BALL_Y  WO [9:0] ball centre y      (hardware sprite overlay)
//
// Framebuffer write protocol (LEVEL handshake):
//   C writes FB_BLK once, then writes FB_DATA exactly 32 times (the 128
//   bytes of that block, word k = bytes 4k..4k+3, MSB first). Each FB_DATA
//   write toggles fb_req; the fabric two-flop synchronizes data+req into
//   the hp_clkout domain, stores the word in the pack array and toggles
//   fb_ack. C polls FB_STATUS bit0 until it matches the toggled request
//   value before writing the next word. After the 32nd word the fabric
//   commits one 128-byte HyperRAM burst (blk * 64 half-word units).
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
    input  wire        hp_init,        // HyperRAM init_calib (hp_clkout domain)
    input  wire [7:0]  frame_cnt,      // display frame counter (clk_p domain)

    // Framebuffer write window (level handshake, see top.v)
    output reg  [12:0] fb_blk,         // 128-byte block index
    output reg  [31:0] fb_data,
    output reg         fb_req,         // toggles once per written word
    input  wire        fb_ack,         // toggles once per stored word

    // Double-buffer control (hp_clkout domain crosses below)
    output reg         buf_swap,       // toggles on a write to 0x30
    input  wire        disp_buf,       // framebuffer index being scanned out

    // First-frame gate for the HDMI blank (clk_p domain crosses in top.v)
    output reg         fb_ready,       // toggles on a write to 0x38

    // Hardware sprite overlay positions (x/y of the ball, top row of each
    // paddle). These cross into the clk_p domain in top.v, where the pixel
    // path overlays the objects on top of the framebuffer content.
    output reg  [9:0]  sp_p1_y,        // 0x40 P1 paddle top row
    output reg  [9:0]  sp_p2_y,        // 0x44 P2 paddle top row
    output reg  [9:0]  sp_bx,          // 0x48 ball centre x
    output reg  [9:0]  sp_by           // 0x4C ball centre y
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
    // CDC: 2-flop syncs into the pclk domain
    //   ack_s0/ack_s1: fb_ack from the hp_clkout domain.
    //   req_s0/req_s1: same-domain pipeline of fb_req, so FB_STATUS read
    //                  timing matches ack_s1.
    //   init_s0/init_s1: HyperRAM init_calib (quasi-static level).
    //   fc_s0/fc_s1: display frame counter from the pixel domain.
    //----------------------------------------------------------------------
    reg ack_s0, ack_s1;
    reg req_s0, req_s1;
    reg init_s0, init_s1;
    reg [7:0] fc_s0, fc_s1;
    reg db_s0, db_s1;
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ack_s0 <= 1'b0; ack_s1 <= 1'b0;
            req_s0 <= 1'b0; req_s1 <= 1'b0;
            init_s0 <= 1'b0; init_s1 <= 1'b0;
            fc_s0 <= 8'd0;  fc_s1 <= 8'd0;
            db_s0 <= 1'b0;  db_s1 <= 1'b0;
        end else begin
            ack_s0 <= fb_ack; ack_s1 <= ack_s0;
            req_s0 <= fb_req; req_s1 <= req_s0;
            init_s0 <= hp_init; init_s1 <= init_s0;
            fc_s0 <= frame_cnt; fc_s1 <= fc_s0;
            db_s0 <= disp_buf; db_s1 <= db_s0;
        end
    end

    //----------------------------------------------------------------------
    // Combinational read mux (no registered read data race)
    //----------------------------------------------------------------------
    always @(*) begin
        case (paddr)
            8'h04: prdata = {24'b0, key_reg};
            8'h08: prdata = {31'b0, init_s1};
            8'h0C: prdata = {24'b0, fc_s1};
            8'h2C: prdata = {30'b0, req_s1, ack_s1};
            8'h34: prdata = {31'b0, db_s1};
            default: prdata = 32'b0;
        endcase
    end

    //----------------------------------------------------------------------
    // Writes
    //----------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            fb_blk  <= 13'd0;
            fb_data  <= 32'd0;
            fb_req   <= 1'b0;
            buf_swap <= 1'b0;
            fb_ready <= 1'b0;
            sp_p1_y  <= 10'd190;   /* match main.c game_reset() */
            sp_p2_y  <= 10'd190;
            sp_bx    <= 10'd320;
            sp_by    <= 10'd240;
        end else if (psel && penable && pwrite) begin
            case (paddr)
                8'h24: fb_blk  <= pwdata[12:0];
                8'h28: begin
                          fb_data <= pwdata;
                          fb_req  <= ~fb_req;   /* toggle: one word written */
                       end
                8'h30: buf_swap <= ~buf_swap;   /* toggle: request buffer flip */
                8'h38: fb_ready <= ~fb_ready;   /* toggle: first frame is up */
                8'h40: sp_p1_y  <= pwdata[9:0];
                8'h44: sp_p2_y  <= pwdata[9:0];
                8'h48: sp_bx    <= pwdata[9:0];
                8'h4C: sp_by    <= pwdata[9:0];
                default: ;
            endcase
        end
    end

endmodule
