//============================================================================
// APB2 SLAVE REGISTER BRIDGE - game-agnostic framebuffer front end
//============================================================================
//
// Runs in the EMPU APB2 master clock domain (master_pclk, 27 MHz). This block
// knows NOTHING about any game: it is a plain "framebuffer + palette + object
// table" peripheral. The C firmware owns every game rule, every object's size
// and position, and the whole colour scheme.
//
// Register map:
//   0x04 KEY        RO key values, key[0]=KEY1 key[1]=KEY2 key[2]=KEY3
//                      (pressed = 0). The MEANING of each key is decided in C.
//   0x08 HP_STATUS  RO bit0 = HyperRAM init_calib done (2-flop synced)
//   0x0C FRAME      RO [7:0] display frame counter, +1 per 640x480 frame
//                      (2-flop synced; firmware polls it for the 60 Hz tick)
//   0x24 FB_BLK     WO [12:0] 128-byte block index (0..599); sets the
//                      target of the next 32 FB_DATA writes
//   0x28 FB_DATA    WO [31:0] one framebuffer word; writing toggles fb_req
//   0x2C FB_STATUS  RO bit0 = fb_ack sync, bit1 = fb_req sync
//   0x30 BUF_POST   WO [1:0] the buffer the M3 has just finished rendering.
//                      The fabric shows it at the next frame boundary and
//                      publishes the new free buffer in BUF_FREE (triple
//                      buffering: front / middle / back).
//   0x34 BUF_DISP   RO [1:0] framebuffer currently being scanned out (0..2)
//   0x3C BUF_FREE   RO [1:0] framebuffer the M3 must render into next (0..2)
//   0x38 FB_READY   WO write toggles: the framebuffer now holds a whole
//                      composed scene; the fabric uses the FIRST toggle to
//                      stop blanking the HDMI output (no power-up garbage)
//   0x50 PAL_INDEX  WO [7:0] index used by the next PAL_DATA write
//   0x54 PAL_DATA   WO [23:0] 0x00RRGGBB -> pal[PAL_INDEX], then PAL_INDEX++
//   0x40 SPR_BANK   WO [0] object-table bank: 0 -> rectangles 0..3,
//                      1 -> rectangles 4..7. Reset value is 0.
//   0x80+0x20n+4f   WO generic object table, rectangle n (0..NS-1, NS=5), field f:
//                      f=0 x0[9:0]  f=1 y0[8:0]  f=2 x1[9:0] = x0+w
//                      f=3 y1[9:0] = y0+h    f=4 {23'b0, enable, colour[3:0]}
//                      (f=2/f=3 are the EXCLUSIVE right/bottom edges; storing
//                       edges instead of w/h keeps an adder out of the
//                       per-pixel hit test - see sprite_overlay.v)
//                      (higher n is painted on top of lower n)
//                      The window 0x80..0xFF only reaches rectangles 0..3
//                      (n = paddr[6:5]); write SPR_BANK (0x40) first to select
//                      rectangles 4..7 (with NS=5 only index 4 exists there).
//                      Writes to n >= NS are ignored.
//                      Every field is a WORD (4-byte) slot: the Cortex-M3
//                      HardFaults on an unaligned access to the APB Device
//                      region, so the C side MUST be able to write whole words.
//
// Framebuffer model: 320x240 x 8bpp INDEXED, stored LINEARLY (row-major, no
// padding), so one byte = one pixel and byte index = y*320 + x. A 128-byte
// block therefore covers 128 consecutive frame pixels and MAY SPAN A ROW
// BOUNDARY: 600 blocks per frame. Each 32-bit FB_DATA word holds four pixels,
// left-most in bits 31:24. The fabric's read engine upscales 2x horizontally
// and, by reading every source row twice, 2x vertically, so the HDMI output is
// still 640x480 while the firmware only ever deals with 320x240 pixels.
//
// Triple buffering: three complete frames live in HyperRAM (bases 0, 38400 and
// 76800 half-word units). The fabric scans out DISP, the M3 renders into FREE,
// and a posted buffer waits in READY. 0x30/0x34/0x3C expose that state.
//
// Framebuffer write protocol (LEVEL handshake):
//   C writes FB_BLK once, then writes FB_DATA exactly 32 times. Each FB_DATA
//   write toggles fb_req; the fabric two-flop synchronizes data+req into the
//   hp_clkout domain, stores the word and toggles fb_ack. C polls FB_STATUS
//   bit0 until it matches the toggled request value before writing the next
//   word. After the 32nd word the fabric commits one 128-byte HyperRAM burst
//   (blk * 64 half-word units).
//
// NOTE: prdata is a COMBINATIONAL mux and pready is tied high, so the master
// samples stable read data on the APB setup phase.
//
//============================================================================

module apb_fb_reg (
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

    // Triple-buffer control (hp_clkout domain crosses below). The 2-bit
    // indices travel GRAY CODED so at most one bit can be in flight across
    // the clock boundary; the far side syncs two flops and decodes.
    output reg  [1:0]  buf_post_gray,  // gray(block) just rendered, 0x30 write
    output reg         buf_post_tog,   // toggles once per 0x30 write
    input  wire [1:0]  disp_gray,      // gray(block being scanned out)
    input  wire [1:0]  free_gray,      // gray(block the M3 renders into next)

    // First-frame gate for the HDMI blank (clk_p domain crosses in top.v)
    output reg         fb_ready,       // toggles on a write to 0x38

    // Colour palette write port (clk_p domain table lives in palette_ram.v)
    output reg  [7:0]  pal_waddr,
    output reg  [23:0] pal_wdata,
    output reg         pal_we,         // one-cycle pulse, valid with the above

    // Generic object (rectangle) table write port (sprite_overlay.v)
    output reg  [2:0]  spr_sel,
    output reg  [2:0]  spr_field,
    output reg  [15:0] spr_wdata,
    output reg         spr_we,         // one-cycle pulse, valid with the above

    // Collision tone drive. C writes 1/0 to make the buzzer square wave; the
    // bit is KEPT between writes (no auto-clear), so the firmware's SysTick
    // ISR just flips it at the tone frequency.
    output reg         beep_trig       // 0x5C write bit0 -> buzzer level
);

    //----------------------------------------------------------------------
    // APB protocol (always ready, no decode errors)
    //----------------------------------------------------------------------
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    // Palette auto-increment cursor. It is kept SEPARATE from the address that
    // goes to palette_ram because pal_we is registered: the table samples
    // (we, addr, data) one cycle after the APB access. Incrementing the address
    // in the same cycle as the data write therefore pushed every entry one slot
    // later (index 0 stayed black, entry 15 was lost).
    reg [7:0] pal_widx;

    //----------------------------------------------------------------------
    // Object-table BANK. The rectangle window 0x80..0xFF is only 128 bytes and
    // holds exactly FOUR rectangles (4 x 8 fields x 4 bytes = 128), addressed by
    // paddr[6:5]; the 8-bit APB address space is completely full there. So the
    // upper half of an 8-rectangle table is reached through this bank bit:
    //     spr_sel = {spr_bank, paddr[6:5]}      (0..7)
    // Write 1 to 0x40 to address rectangles 4..7, 0 to address 0..3.
    // Reset value is 0, so a program that never writes 0x40 sees EXACTLY the old
    // four-rectangle map - the extension is fully backward compatible.
    //----------------------------------------------------------------------
    reg spr_bank;

    //----------------------------------------------------------------------
    // Key register: keyboard_74hc165 already reports keys_raw[0]=KEY1 ...
    // keys_raw[7]=KEY8 (it samples D7 first and shifts it into bit 7), so the
    // byte is passed through UNCHANGED - key_reg[n] = KEY(n+1).
    // (An earlier version also bit-reversed here, which mirrored the whole
    //  keyboard: key_reg[0] became KEY8, so Pong/Tetris listened to the last
    //  keys of the chain and pressing the first keys did nothing at all.)
    // Key pressed = 0 (active low).
    //----------------------------------------------------------------------
    wire [7:0] key_reg = keys_raw;

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
    reg [1:0] dbg_s0, dbg_s1;
    reg [1:0] frg_s0, frg_s1;
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ack_s0 <= 1'b0; ack_s1 <= 1'b0;
            req_s0 <= 1'b0; req_s1 <= 1'b0;
            init_s0 <= 1'b0; init_s1 <= 1'b0;
            fc_s0 <= 8'd0;  fc_s1 <= 8'd0;
            dbg_s0 <= 2'd0; dbg_s1 <= 2'd0;
            frg_s0 <= 2'd0; frg_s1 <= 2'd0;
        end else begin
            ack_s0 <= fb_ack; ack_s1 <= ack_s0;
            req_s0 <= fb_req; req_s1 <= req_s0;
            init_s0 <= hp_init; init_s1 <= init_s0;
            fc_s0 <= frame_cnt; fc_s1 <= fc_s0;
            dbg_s0 <= disp_gray; dbg_s1 <= dbg_s0;
            frg_s0 <= free_gray; frg_s1 <= frg_s0;
        end
    end

    // Gray decode of the two synced buffer indices (see the port comment).
    wire [1:0] db_i = {dbg_s1[1], dbg_s1[1] ^ dbg_s1[0]};
    wire [1:0] fr_i = {frg_s1[1], frg_s1[1] ^ frg_s1[0]};

    //----------------------------------------------------------------------
    // Combinational read mux (no registered read data race)
    //----------------------------------------------------------------------
    always @(*) begin
        case (paddr)
            8'h04: prdata = {24'b0, key_reg};
            8'h08: prdata = {31'b0, init_s1};
            8'h0C: prdata = {24'b0, fc_s1};
            8'h2C: prdata = {30'b0, req_s1, ack_s1};
            8'h34: prdata = {30'b0, db_i};
            8'h3C: prdata = {30'b0, fr_i};
            8'h54: prdata = {24'b0, pal_widx};    // read back the palette cursor
            default: prdata = 32'b0;
        endcase
    end

    //----------------------------------------------------------------------
    // Writes. pal_we / spr_we are REGISTERED one-cycle strobes: the payload
    // registers are loaded in the APB write cycle and the strobe is asserted
    // in the following cycle, so address and data are always stable (and
    // glitch-free) when the far side samples them.
    //----------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            fb_blk    <= 13'd0;
            fb_data   <= 32'd0;
            fb_req    <= 1'b0;
            buf_post_gray <= 2'd0;
            buf_post_tog  <= 1'b0;
            fb_ready  <= 1'b0;
            pal_waddr <= 8'd0;
            pal_widx  <= 8'd0;
            pal_wdata <= 24'd0;
            pal_we    <= 1'b0;
            spr_bank  <= 1'b0;
            spr_sel   <= 3'd0;
            spr_field <= 3'd0;
            spr_wdata <= 16'd0;
            spr_we    <= 1'b0;
            beep_trig <= 1'b0;
        end else begin
            pal_we <= 1'b0;
            spr_we <= 1'b0;
            if (psel && penable && pwrite) begin
                case (paddr)
                    8'h24: fb_blk  <= pwdata[12:0];
                    8'h28: begin
                              fb_data <= pwdata;
                              fb_req  <= ~fb_req;   /* toggle: one word written */
                           end
                    8'h30: begin
                              /* triple-buffer post: latch WHICH buffer was just
                                 rendered (gray coded, so the 2-bit index can
                                 cross into the hp_clkout domain without a
                                 multi-bit race) and toggle the request */
                              buf_post_gray <= pwdata[1:0] ^ (pwdata[1:0] >> 1);
                              buf_post_tog  <= ~buf_post_tog;
                           end
                    8'h38: fb_ready <= ~fb_ready;   /* toggle: first frame is up */
                    8'h40: spr_bank <= pwdata[0];   /* rectangle table bank 0/1 */
                    8'h50: begin
                              pal_waddr <= pwdata[7:0];
                              pal_widx  <= pwdata[7:0];   /* set the cursor   */
                           end
                    8'h54: begin
                              /* the table samples these next cycle: keep the
                                 address on the CURRENT index and advance the
                                 cursor only for the NEXT entry */
                              pal_waddr <= pal_widx;
                              pal_wdata <= pwdata[23:0];
                              pal_we    <= 1'b1;
                              pal_widx  <= pal_widx + 8'd1;
                           end
                    8'h5C: beep_trig <= pwdata[0];   /* level: 1 = beep on, 0 = off */
                    default: begin
                        if (paddr[7] == 1'b1) begin      /* 0x80..0xFF */
                            spr_sel   <= {spr_bank, paddr[6:5]}; /* rect 0..7 */
                            spr_field <= paddr[4:2];     /* field 0..4      */
                            spr_wdata <= pwdata[15:0];
                            spr_we    <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end

endmodule