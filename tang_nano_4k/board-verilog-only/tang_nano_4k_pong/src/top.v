//============================================================================
// TOP MODULE - Color Pong for Tang Nano 4K (GW1NSR-4C)
//============================================================================
//
// 架构 (两个已验证工程的合并):
//   Cortex-M3 (Gowin_EMPU, 27MHz) 跑 C 游戏逻辑, 经 APB2 桥把 RGB888 像素
//   按 128 字节 (32 词) 块写入板载 HyperRAM (PSRAM) 帧缓冲 (640x480x24b
//   = 230400 词 = 7200 块)。fabric 读引擎以 burst128 连续把整帧读入双时钟
//   FIFO (128x32, 1 块 SDPB) -> 25.2MHz 像素侧 3 词 -> 4 像素 (BGR 重排)
//   -> SVO HDMI 栈输出 640x480@60 全彩画面。
//
        // 仲裁 (hp_clkout 31.5MHz 域):
//   读引擎自由运行, 只要视频 FIFO 有 32 词空位 (fifo_can_burst) 就发起
//   读突发 (显示优先, 永不饿)。写打包 FSM 收满 32 词后在读不要求总线时
//   插入一个写突发 (64 周期 ~2us; FIFO 128 词深, 显示最多被推迟 2us,
//   稳态余量 >60 词, 不会饿死)。M3 写带宽 ~1M 词/s << 空闲带宽 ~12M 词/s。
//
// 时钟方案:
//   clk (27MHz 晶振) ─┬─> EMPU sys_clk (master_pclk: APB + 键盘域)
//                     └─> HyperRAM IP 'clk' 参考时钟
//   clk -> PLLVR ─┬─> clk_p5 (126MHz, TMDS 串行) -> CLKDIV(/5) -> clk_p (25.2MHz)
//                 └─> clk_d63 (63MHz, HyperRAM memory_clk)
//                        └─IP 内部 /2 -> hp_clkout (31.5MHz)
//
// BSRAM 预算 (共 10 块): EMPU M3 SRAM x8 + HyperRAM IP 内部 x1 + 视频
//   FIFO SDPB x1 = 10。写打包 pack_mem 用 reg 阵列, 不占 BSRAM。
//
// 字节顺序 (与 psram_hdmi 工程一致):
//   PSRAM 字节流 = 每像素 {R,G,B} 顺序, 第一个字节 = 第 0 像素 R。
//   word0={p0.R,p0.G,p0.B,p1.R}, 3 词 = 12 字节 = 4 像素。
//   SVO 栈输入 BGR (svo_rgba = {a,b,g,r}), 像素流做字节倒序。
//
//============================================================================
`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module top(
    //----------------------------------------------------------------------
    // Clock & Reset
    //----------------------------------------------------------------------
    input clk,              // 27 MHz crystal
    input resetn,           // Reset button S1 (active low)

    //----------------------------------------------------------------------
    // Keyboard (74HC165 shift register)
    //----------------------------------------------------------------------
    output keyboard_pl,     // Parallel Load  (Pin 41)
    output keyboard_cp,     // Clock          (Pin 42)
    input  keyboard_q7,     // Serial Data    (Pin 43)

    //----------------------------------------------------------------------
    // UART (EMPU debug, optional)
    //----------------------------------------------------------------------
    input  uart0_rxd,       // Pin 39
    output uart0_txd,       // Pin 40

    //----------------------------------------------------------------------
    // HyperRAM physical pins (embedded die - auto-placed to internal bond pads)
    //----------------------------------------------------------------------
    inout  [7:0] hpram_dq,
    inout  [0:0] hpram_rwds,
    output [0:0] hpram_ck,
    output [0:0] hpram_ck_n,
    output [0:0] hpram_cs_n,
    output [0:0] hpram_reset_n,

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
// Standard 640x480@60 timing: 800 x 525 (45 blanking lines, 59.94 Hz).
// The "640x480" preset in svo_defines.vh is 800 x 500 (only 20 blanking
// lines) -> 63 Hz, a non-standard mode that makes monitors re-sync (flicker)
// and leaves very little margin for the read engine to restart at the frame
// boundary. "640x480V" keeps the same 160-symbol horizontal blanking but
// restores the standard 45-line vertical blanking.
parameter SVO_MODE             = "640x480V";
parameter SVO_FRAMERATE        = 60;
parameter SVO_BITS_PER_PIXEL   = 24;
parameter SVO_BITS_PER_RED     = 8;
parameter SVO_BITS_PER_GREEN   = 8;
parameter SVO_BITS_PER_BLUE    = 8;
parameter SVO_BITS_PER_ALPHA   = 0;

localparam LINE_LAST     = 479;
localparam GROUPS_LINE   = 160;     // 640 px / 4
localparam BURSTS_FRAME  = 7200;    // 230400 frame words / 32
localparam [21:0] ADDR_STEP  = 22'd64;     // 128 bytes in 2-byte addr units
localparam [21:0] FRAME_UNITS = 22'd460800; // one 640x480x24b frame in 2-byte units
                                            // (buffer A base = 0, buffer B = FRAME_UNITS)

// DIAGNOSTIC: when 1, the pixel FSM streams an internally generated STATIC
// GEOMETRIC PATTERN (8 colour bars + reference edge markers, see test_rgb)
// and never touches HyperRAM / the video FIFO. One flash then splits the
// fault space in two:
//   * pattern rock-steady   -> TMDS/raster/clock path is clean; the flicker
//                              comes from the memory / pixel-data path
//                              (incl. double-buffer content differences)
//   * pattern SHIFTS sideways/vertically -> the pixel FSM's frame boundary
//                              drifts relative to the encoder raster
//                              (frame desynchronisation)
//   * pattern rolls/flickers as a whole  -> the TMDS/encoder/clock path itself
// Set to 0 for the normal game display.
localparam TEST_PATTERN = 1'b0;

// NORM-PATH PROBE: when 1, the normal pixel FSM runs exactly as in the game
// (P_IDLE -> P_PRIME -> P_RUN, reading the FIFO), but the HDMI encoder is fed
// by an INDEPENDENT always-valid stream whose colour reports the normal FSM's
// state and whether the pixel side ever read a NON-ZERO FIFO word:
//   BLUE    init not done
//   RED     stuck in P_IDLE   (fifo_rd_fill >= 64 never satisfied)
//   ORANGE  stuck in P_PRIME  (no FIFO word available)
//   GREEN   P_RUN and FIFO read data was NON-ZERO (normal path fully works)
//   MAGENTA P_RUN but FIFO read data was always ZERO (FIFO read side broken)
// Set to 0 for normal game display.
localparam NORM_PROBE = 1'b0;

// NORM-PATH CONST-DATA: when 1, the normal FSM drives the encoder with its
// REAL fb_tvalid/fb_tuser (gaps and all) but a CONSTANT magenta data word, so
// a magenta screen proves the FSM's tvalid/tuser/pacing produce a valid frame
// (=> the bug is in the data path), while a black screen proves the FSM's
// output framing itself is broken. Set to 0 for normal game display.
localparam NORM_CONST = 1'b0;

// DIAG: when 1, the pixel streamer overrides the framebuffer with a status
// colour until the write path is proven healthy (M3 wrote words + a burst
// completed). Set to 0 for normal game display.
localparam DIAG_WRITE = 1'b0;

// FABRIC WRITE SELF-TEST: when 1, a fabric FSM (bypassing the M3/APB/pack_mem
// path) writes a solid 0xFFFFFFFF (white) frame directly through hyper_ram_ctrl,
// then releases the read engine to display it. WHITE screen => fabric write +
// read path work (bug is in the M3/APB/pack path). BLACK screen => the fabric
// write to the HyperRAM die is broken. Set to 0 for normal game display.
localparam FABRIC_WRITE_TEST = 1'b0;

//============================================================================
// CLOCKS / RESETS
//============================================================================
wire pll_lock;
wire clk_p5;            // 126 MHz  (PLL CLKOUT, TMDS serial)
wire clk_d63;           // 63 MHz   (PLL CLKOUTD, HyperRAM memory_clk)
wire clk_p;             // 25.2 MHz pixel clock
wire sys_resetn;        // clk_p domain reset
wire apb_resetn;        // master_pclk domain reset
wire global_resetn;     // resetn & pll_lock (HyperRAM FSMs, hp_clkout domain)

wire memory_clk = clk_d63;

assign global_resetn = resetn & pll_lock;

//============================================================================
// PLL - 126 MHz + 63 MHz (clkoutd = CLKOUT/2)
//============================================================================
Gowin_PLLVR pll_inst (
    .clkout (clk_p5),
    .lock   (pll_lock),
    .clkoutd(clk_d63),
    .clkin  (clk)
);

//============================================================================
// CLOCK DIVIDER - 126 MHz / 5 = 25.2 MHz (pixel clock)
//============================================================================
Gowin_CLKDIV clkdiv_inst (
    .clkout(clk_p),
    .hclkin(clk_p5),
    .resetn(pll_lock)
);

//============================================================================
// RESET SYNC (pixel clock domain)
//============================================================================
Reset_Sync reset_sync_px (
    .resetn(sys_resetn),
    .ext_reset(resetn & pll_lock),
    .clk(clk_p)
);

//============================================================================
// EMPU (Cortex-M3) - game logic + PSRAM rendering in C
//============================================================================
wire master_pclk;
wire master_prst;
wire master_penable;
wire [7:0]  master_paddr;
wire master_pwrite;
wire [31:0] master_pwdata;
wire [3:0]  master_pstrb;
wire [2:0]  master_pprot;
wire master_psel1;
wire [31:0] master_prdata1;
wire master_pready1;
wire master_pslverr1;
wire [15:0] gpio_io;

Gowin_EMPU_Top u_empu (
    .sys_clk(clk),
    .gpio(gpio_io),
    .uart0_rxd(uart0_rxd),
    .uart0_txd(uart0_txd),
    .master_pclk(master_pclk),
    .master_prst(master_prst),
    .master_penable(master_penable),
    .master_paddr(master_paddr),
    .master_pwrite(master_pwrite),
    .master_pwdata(master_pwdata),
    .master_pstrb(master_pstrb),
    .master_pprot(master_pprot),
    .master_psel1(master_psel1),
    .master_prdata1(master_prdata1),
    .master_pready1(master_pready1),
    .master_pslverr1(master_pslverr1),
    .reset_n(resetn)
);

//============================================================================
// RESET SYNC (APB master_pclk domain, own fabric reset)
//============================================================================
Reset_Sync reset_sync_apb (
    .resetn(apb_resetn),
    .ext_reset(resetn & pll_lock),
    .clk(master_pclk)
);

//============================================================================
// KEYBOARD (74HC165) - Read 8 keys (master_pclk domain)
//============================================================================
wire [7:0] keys;
wire keys_valid;

keyboard_74hc165 u_keyboard (
    .clk    (master_pclk),
    .resetn (apb_resetn),
    .pl     (keyboard_pl),
    .cp     (keyboard_cp),
    .q7     (keyboard_q7),
    .keys   (keys),
    .valid  (keys_valid)
);

//============================================================================
// HyperRAM controller signals
//============================================================================
wire [21:0] hp_addr;
wire [31:0] hp_wr_data;
wire        hp_wr_req;
wire        hp_wr_done;
wire        hp_rd_req;
wire        hp_rd_stall;     // hp_clkout: one-cycle pulse per stalled read burst
wire        hp_rd_valid;
wire [31:0] hp_rd_data;
wire        hp_rd_done;
wire        hp_busy;
wire        hp_init;
wire        hp_clkout;

//============================================================================
// APB2 REGISTER BRIDGE (master_pclk domain)
//   FB write window: C writes FB_BLK (128B block index) once, then streams
//   32 FB_DATA words (level handshake). Fabric packs them into one burst.
//============================================================================
wire [12:0] fb_blk;
wire [31:0] fb_data;
wire        fb_req;
wire        fb_ack;
wire [7:0]  frame_cnt;      // clk_p domain -> synced inside the bridge
wire        buf_swap;       // master_pclk -> hp_clkout toggle (double buffer)
reg         disp_buf;       // hp_clkout: framebuffer currently scanned out
wire        apb_ready_tog;  // master_pclk -> clk_p toggle: unblank the HDMI output

wire [9:0] sp_p1_y_apb, sp_p2_y_apb, sp_bx_apb, sp_by_apb;   // M3 -> fabric sprite positions

apb_pong_reg u_apb_reg (
    .pclk      (master_pclk),
    .presetn   (apb_resetn),
    .psel      (master_psel1),
    .penable   (master_penable),
    .paddr     (master_paddr),
    .pwrite    (master_pwrite),
    .pwdata    (master_pwdata),
    .prdata    (master_prdata1),
    .pready    (master_pready1),
    .pslverr   (master_pslverr1),
    .keys_raw  (keys),
    .hp_init   (hp_init),
    .frame_cnt (frame_cnt),
    .fb_blk    (fb_blk),
    .fb_data   (fb_data),
    .fb_req    (fb_req),
    .fb_ack    (fb_ack),
    .buf_swap  (buf_swap),
    .disp_buf  (disp_buf),
    .fb_ready  (apb_ready_tog),
    .sp_p1_y   (sp_p1_y_apb),
    .sp_p2_y   (sp_p2_y_apb),
    .sp_bx     (sp_bx_apb),
    .sp_by     (sp_by_apb)
);

//============================================================================
// Write-path FSM (APB words -> HyperRAM burst128), hp_clkout domain
//   - 2-flop sync of bridge outputs (master_pclk -> hp_clkout)
//   - incoming words fill pack_mem[0..31] (flip-flop array, no BSRAM)
//   - 32nd word latches the burst address into wr_addr_lat and asserts full
//   - burst engine streams words 0..31, then the buffer is free again
//   - a word arriving while the buffer is busy is held on the APB bus until
//     the ack can be given (never dropped), keeping M3 and fabric in sync
//
// Stream timing contract with hyper_ram_ctrl:
//   W_ISSUE cycle  : hp_wr_req=1 and hp_wr_data=pack_mem[0]
//   W_STREAM cyc k : hp_wr_data=pack_mem[k+1], k=0..30
//============================================================================
reg [31:0] pack_mem [0:31];   // 32-word pack buffer (flip-flop array, no BSRAM)
reg [31:0] wd_s0, wd_s1;
reg        wr_s0, wr_s1, wr_prev;
reg [12:0] blk_s0, blk_s1;
reg [4:0]  cnt;           // words stored in the buffer since the last burst
reg [4:0]  ridx;          // streaming word index (1..31)
reg        full;          // buffer complete, awaiting / under burst
// Burst address LATCHED WITH THE BLOCK (block index + buffer base at pack
// time). It must not be recomputed from disp_buf when the burst is finally
// issued: the scheduler below can delay a write by a whole read burst, and
// disp_buf flips at the read engine's revolution wrap. Recomputing would
// redirect a block packed for the previous buffer into the buffer being
// scanned -> a 43 px horizontal tear. 22 bits = 64 half-word units * 7200.
reg [21:0] wr_addr_lat;   // latched burst address (2-byte units)
reg        cap_act;       // a word is being captured
reg [1:0]  cap_dly;       // settle delay before sampling the 32-bit word
reg [1:0]  w_state;
reg [6:0]  w_to;          // burst-stall watchdog (W_STREAM cycles)
reg        ack_toggle;

localparam W_IDLE   = 2'd0;
localparam W_ISSUE  = 2'd1;
localparam W_STREAM = 2'd2;

// Video-FIFO status. Declared HERE (not next to the instance) because the
// scheduler below reads the write-side fill level and Gowin's parser does not
// hoist module-level declarations.
wire        fifo_full;      // video FIFO status (async_fifo instance below)
wire        fifo_can_burst;
wire        fifo_empty;
wire        fifo_has_word;
wire [9:0]  fifo_rd_fill;
wire [31:0] fifo_dout;
wire [9:0]  wr_fill;        // write-domain fill level (synced read ptr)

//============================================================================
// BUS-TURNAROUND / WRITE-WINDOW SCHEDULER (hp_clkout domain)
//============================================================================
// The HyperRAM die is ONE bus: a write burst is a full DQ turnaround in the
// same stream the display reads from. Both turnaround directions were
// unguarded, and that is what painted the flickering horizontal bars:
//
//  (a) WRITE -> READ: rd_guard (the 48-cycle hold-off) is a REGISTER that is
//      loaded on the hp_wr_done cycle. On that very cycle it still held its
//      old value 0, while hp_busy had already dropped to 0 (cleared at the
//      same edge that sets ex_wr_done) and fifo_can_burst was 1 again - the
//      pixel side had drained ~38 of the 512 words during the 64-cycle write,
//      taking the level back under 448. So hp_rd_req was asserted in the SAME
//      cycle the write finished and the controller accepted a read command
//      with ZERO write-recovery gap. The burst that came back was polluted and
//      painted a ~43 px band (one 128B block) on whatever line was being
//      scanned at that moment. It only appeared while the M3 was writing
//      (i.e. while the ball/paddles moved) and vanished with STATIC_TEST.
//      FIX: rd_guard now also blocks the hp_wr_done cycle itself.
//
//  (b) READ -> WRITE: the write used to be issued on the first cycle the bus
//      was free, i.e. ~1 hp cycle (32 ns) after the previous read burst
//      completed - far below the memory's read-to-write recovery.
//      FIX: rd_quiet counts cycles since the last read burst released the
//      bus, and a write may only start after RD_QUIET_CYCLES.
//
// wr_hold closes the read window while a packed block waits, so (b) is
// reachable at all: in steady state the read engine is throttled by
// fifo_can_burst and would otherwise re-grab the bus every ~13 idle cycles.
// wr_hold is only armed with >= WR_ARM_FILL words of elasticity (>=12.7 us at
// the 25.2 MHz pixel rate), so holding the reads off - at most a read burst
// tail + quiet + write + guard ~ 190..590 cycles (6..19 us) - can never
// starve the display.
//============================================================================
localparam [7:0]  RD_QUIET_CYCLES = 8'd24;    // read->write turnaround (~0.8 us)
localparam [7:0]  WR_GUARD_CYCLES = 8'd96;    // write->read recovery  (~3 us)
localparam [9:0]  WR_ARM_FILL     = 10'd400;  // arm only with >=400 words elastic
localparam [9:0]  WR_COOLDOWN     = 10'd256;  // min cycles between write windows
localparam [11:0] WR_WAIT_MAX     = 12'd4095; // force a window if starved

reg  [7:0]  rd_quiet;   // hp cycles since the last read burst completed
reg  [9:0]  wr_cool;    // post-write cooldown
reg  [11:0] wr_wait;    // how long the packed block has waited for the bus
reg         wr_hold;    // write pending: read engine is off the bus

// ---- VBLANK-SEPARATED WRITE WINDOW -------------------------------------
// The known-good Gowin HyperRAM->HDMI reference NEVER overlaps a write burst
// with the display read stream: it uploads one frame (write phase), then sets
// display_mode and reads forever with the write path completely idle. Pong has
// to write continuously, and every attempt to merely GUARD the read/write
// turnaround (rd_guard 48/96 cycles, wr_hold/wr_cool scheduling) still painted
// horizontal stripes. On this IP an interleaved 128-byte write corrupts the
// read burst that is filling the video FIFO, so the two are now separated in
// TIME: a write burst may only start inside the VERTICAL BLANKING interval,
// where the pixel FSM consumes nothing and the read engine is idle anyway.
//
// The vblank is detected without any raster signal: during vblank the FIFO
// stops draining, so fifo_can_burst stays false, the read engine stops being
// re-armed, and rd_idle (cycles since the last read burst completed) runs
// away. In active video rd_idle can never exceed ~280 (hblank is only ~200
// cycles long), so 1024 cycles (~32 us) is an unambiguous "we are in vblank".
// The window then closes on the FIRST sign of consumption - wr_fill dropping
// back below the level a no-drain FIFO sits at - i.e. exactly when active
// video restarts. A write can therefore never land while the display reads.
reg  [15:0] rd_idle;    // cycles since the last read burst completed
reg         vb_win;     // vblank write window open: reads are held off
reg         vb_latch;   // one window per vblank, re-armed by a read burst
localparam [15:0] VB_IDLE = 16'd1024;   // ~32 us of read idle => vblank
localparam [9:0]  VB_FILL = 10'd400;    // no-drain (vblank) FIFO level marker
wire vb_seen = (rd_idle >= VB_IDLE) && (wr_fill >= VB_FILL);

// The ONE condition that opens a write window. It gates BOTH the W_ISSUE ->
// W_STREAM transition and hp_wr_req itself, so the request is exactly one
// cycle long and the controller latches address and word 0 together.
wire wr_burst_ok = hp_init && wr_hold && !hp_busy &&
                   (rd_quiet >= RD_QUIET_CYCLES);

// Enough elasticity for a window - or the block has waited far too long
// (~130 us) and taking the bus is the lesser evil (keeps the M3 moving even
// if the read path were ever unable to fill the FIFO).
// A write window may only open inside vblank (see the detector above). The old
// "force a window after WR_WAIT_MAX" escape is deliberately gone: it fired
// during active video whenever the M3 was a little slow - precisely the
// interleaving this design removes.
// ---- STARTUP WRITE BYPASS ------------------------------------------------
// The M3 can normally push only ONE block per vertical blanking interval: the
// pack buffer stays full until its burst is allowed out, and wr_armable opens
// only inside vblank (see the vblank detector above), so the M3 polls its
// write ack for the whole active-video period - ~91% of every frame is wasted
// waiting. At power-up that made composing the two framebuffers take ~20 s of
// black screen. While the HDMI output is still blanked no pixel the M3 damages
// can reach the monitor, so the write path is allowed to leave the vblank
// window: wr_hold pulls the read engine off the bus, rd_quiet builds up and the
// burst goes out after RD_QUIET_CYCLES, exactly as it does inside vblank. The
// bypass is dropped for good on the FIRST FB_READY toggle - always written
// while the output is still blanked - so steady-state operation keeps the
// strict vblank-only read/write separation that removed the horizontal stripes.
reg  rdy_h0, rdy_h1, rdy_hprev, startup_done;
always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        rdy_h0 <= 1'b0; rdy_h1 <= 1'b0; rdy_hprev <= 1'b0; startup_done <= 1'b0;
    end else begin
        rdy_h0 <= apb_ready_tog; rdy_h1 <= rdy_h0; rdy_hprev <= rdy_h1;
        if (rdy_h1 ^ rdy_hprev) startup_done <= 1'b1;
    end
end
// The ONE condition that opens a write window: inside vblank, or - while the
// output is still blanked - anywhere, so the power-up fill is not throttled.
wire wr_armable = vb_win || !startup_done;

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        rd_quiet <= 8'd0;
        wr_cool  <= 10'd0;
        wr_wait  <= 12'd0;
        wr_hold  <= 1'b0;
    end else begin
        // Time since the read engine last released the bus.
        if (hp_rd_done)              rd_quiet <= 8'd0;
        else if (rd_quiet != 8'hFF)  rd_quiet <= rd_quiet + 8'd1;

        // Post-write cooldown: bound the write duty cycle so the read engine
        // always gets its share of the bus back.
        if (hp_wr_done)              wr_cool <= WR_COOLDOWN;
        else if (wr_cool != 10'd0)   wr_cool <= wr_cool - 10'd1;

        // Waiting time of a packed block (deadlock insurance for wr_armable).
        if (!full || hp_wr_done)          wr_wait <= 12'd0;
        else if (wr_wait != WR_WAIT_MAX)  wr_wait <= wr_wait + 12'd1;

        // Open a write window (read engine yields the bus), and close it when
        // the burst finished or the W_STREAM watchdog abandoned it.
        if (hp_wr_done || (w_state == W_STREAM && w_to == 7'd127))
            wr_hold <= 1'b0;
        else if (hp_init && full && (wr_cool == 10'd0) && wr_armable)
            wr_hold <= 1'b1;

        // ---- vblank detector + write window (see the block above) -------
        if (hp_rd_done) begin
            rd_idle  <= 16'd0;
            vb_latch <= 1'b0;   // a read burst re-arms the next window
        end else if (rd_idle != 16'hFFFF) begin
            rd_idle  <= rd_idle + 16'd1;
        end

        if (vb_win) begin
            // close the moment the pixel side starts eating the FIFO again
            if (wr_fill < VB_FILL) begin
                vb_win   <= 1'b0;
                vb_latch <= 1'b1;
            end
        end else if (vb_seen && !vb_latch) begin
            vb_win <= 1'b1;
        end
    end
end

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        wd_s0 <= 32'b0; wd_s1 <= 32'b0;
        wr_s0 <= 1'b0;  wr_s1 <= 1'b0;  wr_prev <= 1'b0;
        blk_s0 <= 13'b0; blk_s1 <= 13'b0;
        cnt <= 5'd0; ridx <= 5'd0;
        full <= 1'b0; wr_addr_lat <= 22'b0;
        cap_act <= 1'b0; cap_dly <= 2'd0;
        w_state <= W_IDLE; w_to <= 7'd0;
        ack_toggle <= 1'b0;
    end else begin
        // 2-flop sync of APB bridge outputs
        wd_s0  <= fb_data; wd_s1 <= wd_s0;
        wr_s0  <= fb_req;  wr_s1 <= wr_s0;  wr_prev <= wr_s1;
        blk_s0 <= fb_blk;  blk_s1 <= blk_s0;

        //--------------------------------------------------------------
        // Burst engine: when the buffer holds a full 128-byte block, stream
        // it out as one burst128.
        //--------------------------------------------------------------
        case (w_state)
            W_IDLE: begin
                if (full) w_state <= W_ISSUE;
            end

            // request cycle: controller samples word 0 on this edge. The
            // scheduler's wr_burst_ok guarantees that the controller is IDLE,
            // the read engine is off the bus and the memory has been quiet
            // since the previous read burst (see the scheduler above).
            W_ISSUE: begin
                if (wr_burst_ok) begin
                    ridx    <= 5'd1;              // next cycle presents word 1
                    w_to    <= 7'd0;
                    w_state <= W_STREAM;
                end
            end

            W_STREAM: begin
                if (hp_wr_done || (w_to == 7'd127)) begin
                    // burst finished (or was abandoned): buffer free again
                    full   <= 1'b0;
                    w_to   <= 7'd0;
                    w_state <= W_IDLE;
                end else begin
                    w_to <= w_to + 7'd1;
                    if (ridx != 5'd31)
                        ridx <= ridx + 5'b1;
                end
            end

            default: w_state <= W_IDLE;
        endcase

        //--------------------------------------------------------------
        // Packing - one word stored and acked per FB_DATA write.
        //
        // (a) CDC: wd_s1 and wr_s1 are two-flop synchronised with the SAME
        //     latency, so sampling wd_s1 on the detected edge could capture a
        //     bus that is still settling. The M3 holds fb_data until it sees
        //     the ack, so we sample wd_s1 CAP_DLY cycles after the edge.
        // (b) NEVER DROP A WORD. While the burst engine is streaming the
        //     buffer, the incoming word simply waits (cap_act stays set, ack
        //     is delayed). The M3 keeps driving the same data until it is
        //     acked, so the word is still on wd_s1 when the buffer frees.
        //     Dropping it here would desynchronise the ack toggle and shift
        //     every following word by one -> stripes / twitching objects.
        //--------------------------------------------------------------
        if (wr_s1 ^ wr_prev) begin
            cap_act <= 1'b1;
            cap_dly <= 2'd3;
        end else if (cap_act) begin
            if (cap_dly != 2'd0) begin
                cap_dly <= cap_dly - 2'd1;
            end else if (!full) begin
                pack_mem[cnt] <= wd_s1;       // bus settled by now
                ack_toggle <= ~ack_toggle;
                cap_act    <= 1'b0;
                if (cnt == 5'd31) begin
                    // Address latched WITH the block: block index * 64 units
                    // plus the base of the buffer the M3 is rendering into
                    // (the complement of the one being scanned). Using the
                    // disp_buf of THIS cycle is essential - the burst may be
                    // issued after a later revolution wrap.
                    wr_addr_lat <= {3'b0, blk_s1, 6'b0} +
                                   (disp_buf ? 22'd0 : FRAME_UNITS);
                    full  <= 1'b1;
                    cnt   <= 5'd0;
                end else begin
                    cnt <= cnt + 5'd1;
                end
            end
        end
    end
end

assign fb_ack = ack_toggle;

// Write-activity flags (hp_clkout domain): sticky, for on-screen diagnostics.
reg any_word;   // set on the first FB_DATA word packed
reg any_burst;  // set on the first HyperRAM write burst completing
always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        any_word  <= 1'b0;
        any_burst <= 1'b0;
    end else begin
        if (wr_s1 ^ wr_prev) any_word  <= 1'b1;
        if (hp_wr_done)      any_burst <= 1'b1;
    end
end

//----------------------------------------------------------------------
// FABRIC WRITE SELF-TEST (hp_clkout): after calibration, fill the whole
// frame with 0xFFFFFFFF directly through hyper_ram_ctrl, then stop. The
// read engine is held off until fab_done so the fill is not interleaved.
// WHITE screen => fabric write + read path work. BLACK => write broken.
//----------------------------------------------------------------------
reg [12:0] fab_blk;     // 0..7199
reg [1:0]  fab_state;
reg        fab_done;
localparam FAB_IDLE = 2'd0;
localparam FAB_REQ  = 2'd1;
localparam FAB_WAIT = 2'd2;

wire        fab_req  = (fab_state == FAB_REQ) && !hp_busy && !hp_rd_req;
wire [21:0] fab_addr = {fab_blk, 6'b0};

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        fab_blk   <= 13'd0;
        fab_state <= FAB_IDLE;
        fab_done  <= 1'b0;
    end else begin
        case (fab_state)
            FAB_IDLE: begin
                if (hp_init && !fab_done) begin
                    fab_blk   <= 13'd0;
                    fab_state <= FAB_REQ;
                end
            end
            FAB_REQ: begin
                if (!hp_busy && !hp_rd_req)
                    fab_state <= FAB_WAIT;
            end
            FAB_WAIT: begin
                if (hp_wr_done) begin
                    if (fab_blk == BURSTS_FRAME - 13'd1) begin
                        fab_done  <= 1'b1;
                        fab_state <= FAB_IDLE;
                    end else begin
                        fab_blk   <= fab_blk + 13'd1;
                        fab_state <= FAB_REQ;
                    end
                end
            end
            default: fab_state <= FAB_IDLE;
        endcase
    end
end

// Sticky flag: did ANY read burst return a NON-ZERO word? This separates
// "read bursts complete but the data is all zero" (write/read not landing)
// from "real data comes back" (memory path healthy).
reg rd_nz;
always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) rd_nz <= 1'b0;
    else if (hp_rd_valid && (hp_rd_data != 32'b0)) rd_nz <= 1'b1;
end

// word 0 is presented by the W_ISSUE mux; afterwards pack_mem[ridx] streams.
// hp_wr_req pulses exactly when the scheduler opens a write window - the same
// condition that advances W_ISSUE -> W_STREAM, so the request is one cycle
// long and the controller latches address + word 0 together.
wire [31:0] hp_wr_data_pack = (w_state == W_ISSUE) ? pack_mem[5'd0] : pack_mem[ridx];
wire        hp_wr_req_pack  = (w_state == W_ISSUE) && wr_burst_ok;

assign hp_wr_data = FABRIC_WRITE_TEST ? 32'hFFFFFFFF : hp_wr_data_pack;
assign hp_wr_req  = FABRIC_WRITE_TEST ? fab_req        : hp_wr_req_pack;

//============================================================================
// Read engine (hp_clkout): FREE-RUNNING stream of the whole frame in 7200
// burst128 tasks into the async FIFO. A new burst starts only when the FIFO
// has 32 free words (fifo_can_burst); at the frame end the address wraps and
// (if requested) the displayed double-buffer is switched.
//============================================================================
reg [21:0] rd_addr;
reg [12:0] rburst;       // 0..7199
reg        sw_s0, sw_s1, sw_prev;   // buf_swap sync (master_pclk -> hp_clkout)
reg        sw_pending;              // flip request latched until a frame boundary
reg [6:0]  rd_guard;                // read hold-off after a write burst

reg        fifo_re;      // read enable in clk_p domain
reg        fifo_re_r;    // fifo_re delayed 1 cycle (dout valid window)
reg        fifo_nz;      // sticky: pixel side read a NON-ZERO FIFO word

// During the fabric write self-test, hold reads off until the fill completes.
wire rd_en = (!FABRIC_WRITE_TEST) || fab_done;

// The read engine FREE-RUNS: it streams the frame over and over and is
// throttled ONLY by fifo_can_burst (32 free words). There is deliberately NO
// per-frame stop/restart and NO frame-boundary synchroniser (this is the
// known-good HyperRAM->HDMI reference's structure). A stop/restart gap drains
// the FIFO every frame, and the resulting variable-length drain gap is what
// made the picture flicker. Free-running keeps the FIFO near full (~96 words
// = ~5 us) so the pixel side never starves on HyperRAM latency/refresh gaps.
wire rd_active = hp_init && rd_en;
// POST-WRITE GUARD: a HyperRAM write burst is a bus turnaround on the same
// DQ pins the display read stream uses. Issuing the next read command on the
// very next cycle after hp_wr_done made the IP come back with no data at all
// (RD_TIMEOUT -> 32 ZERO words -> a BLACK chunk on screen + ~432 cycles of
// lost production). That is exactly why the picture flickered harder whenever
// the M3 wrote a lot - i.e. when the ball was near a paddle. Hold the read
// engine off ~48 hp cycles (~1.5us) after every completed write burst so the
// memory's write recovery finishes before the next read command.
// Bus turnaround is guarded in BOTH directions now:
//   * !wr_hold      - a packed block has closed the read window, so the write
//                     can go out after RD_QUIET_CYCLES of a genuinely silent
//                     bus instead of 1 cycle after the previous read burst.
//   * !hp_wr_done   - blocks the cycle the write finishes. hp_busy is already
//                     0 there and fifo_can_burst is 1 again (the pixel side
//                     drained ~38 words during the 64-cycle write), so without
//                     this term a read command was accepted in the SAME cycle
//                     as the write completion - with rd_guard still at 0 (it is
//                     loaded at that edge). That unguarded read was the source
//                     of the flickering horizontal bars.
// The 96-cycle rd_guard then covers the remaining write-recovery window.
assign hp_rd_req = rd_active && !hp_busy && fifo_can_burst &&
                   (rd_guard == 7'd0) && !hp_wr_done && !wr_hold && !vb_win;

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        rd_addr <= 22'd0; rburst <= 13'd0;
        sw_s0 <= 1'b0; sw_s1 <= 1'b0; sw_prev <= 1'b0;
        sw_pending <= 1'b0; disp_buf <= 1'b0;
        rd_guard <= 7'd0;
    end else begin
        sw_s0 <= buf_swap;      sw_s1 <= sw_s0; sw_prev <= sw_s1;

        // Latch a flip request; it takes effect at the next revolution wrap so
        // a whole displayed frame always comes from ONE complete buffer.
        if (sw_s1 ^ sw_prev)
            sw_pending <= 1'b1;

        // Post-write read hold-off (see hp_rd_req above).
        if (hp_wr_done)             rd_guard <= WR_GUARD_CYCLES;
        else if (rd_guard != 7'd0)  rd_guard <= rd_guard - 7'd1;

        if (rd_active && hp_rd_done) begin
            if (rburst == BURSTS_FRAME - 13'd1) begin
                // Frame wrap: DOUBLE BUFFER. A flip request (sw_pending) takes
                // effect HERE, at the engine's own revolution boundary, so the
                // address change is continuous in the stream (7199 -> base of
                // the next buffer) and no data ever jumps mid-frame. disp_buf
                // selects which buffer is scanned and the write base below is
                // its complement, so the M3 renders the buffer that is NOT being
                // scanned (that is exactly what the firmware's alternating
                // old_*[r] dirty state expects).
                //
                // The wrap phase is locked to the display frame: the engine is
                // throttled by fifo_can_burst and the pixel side is paced by the
                // raster, so the FIFO-level pattern repeats every frame. The
                // phase used to drift - and the picture rolled - only because a
                // data-dependent state (P_PRIME) moved the consumption pattern;
                // with that removed the seam sits at a fixed, invisible spot.
                rburst     <= 13'd0;
                disp_buf   <= sw_pending ? ~disp_buf : disp_buf;
                rd_addr    <= (sw_pending ? ~disp_buf : disp_buf) ? FRAME_UNITS : 22'd0;
                // A flip request that arrives on THIS very cycle must NOT be
                // destroyed by the clear. Both assignments are non-blocking
                // writes to sw_pending in this same always block, so the later
                // one used to win and the request was silently dropped: the M3
                // then rendered into the buffer being scanned (tearing) and
                // wait_disp() spun for its whole timeout (~2 s freeze). An
                // arriving edge is a NEW request, so keep it latched for the
                // next wrap; only a request that was already pending is
                // consumed here.
                sw_pending <= (sw_s1 ^ sw_prev) ? 1'b1 : 1'b0;
            end else begin
                rburst  <= rburst + 13'b1;
                rd_addr <= rd_addr + ADDR_STEP;
            end
        end
    end
end

// Read-stall counter (hp_clkout): saturating, free-running count of RD_TIMEOUT
// events. The clk_p side samples it once per display frame and shows the DELTA
// on screen, so "did the read path actually stall this frame?" needs no UART.
reg [7:0] stall_cnt;
always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) stall_cnt <= 8'd0;
    else if (hp_rd_stall && stall_cnt != 8'hFF) stall_cnt <= stall_cnt + 8'd1;
end

// HyperRAM address mux: follows whichever request is actually presented to
// the controller this cycle (the controller latches ex_addr on the req edge).
// hp_wr_req and hp_rd_req are mutually exclusive by construction.
//
// DOUBLE BUFFER: disp_buf selects the buffer being scanned out, and the M3
// writes its COMPLEMENT, so a render never touches the visible frame and the
// firmware's alternating old_*[r] dirty state always refers to the buffer it
// is actually writing. disp_buf only ever changes at the read engine's own
// revolution wrap (see above), i.e. after the M3 has finished a whole render
// and asserted buf_swap.
wire [21:0] eff_wr_addr = FABRIC_WRITE_TEST ? fab_addr : wr_addr_lat;
assign hp_addr = hp_wr_req ? eff_wr_addr : rd_addr;

//============================================================================
// ASYNC VIDEO FIFO: write = hp_clkout read bursts, read = clk_p pixels
//============================================================================
async_fifo u_video_fifo (
    .wr_clk       (hp_clkout),
    .wr_rst_n     (global_resetn),
    .wr_en        (hp_rd_valid),
    .wr_data      (hp_rd_data),
    .full         (fifo_full),
    .wr_can_burst (fifo_can_burst),
    .wr_fill      (wr_fill),

    .rd_clk       (clk_p),
    .rd_rst_n     (sys_resetn),
    .rd_en        (fifo_re),
    .rd_data      (fifo_dout),
    .empty        (fifo_empty),
    .rd_has_word  (fifo_has_word),
    .rd_fill      (fifo_rd_fill)
);

//============================================================================
// Encoder interface (declared here because the pixel streamer below reads
// enc_tuser[2] (VSYNC) to start its frame on the raster's blanking interval).
//============================================================================
wire fb_tready;
wire enc_tvalid, enc_tready;
wire [SVO_BITS_PER_PIXEL-1:0] enc_tdata;
wire [3:0] enc_tuser;

//============================================================================
// Pixel streamer (clk_p): FIFO words -> 4-pixel groups -> SVO encoder
//   - auto-starts once HyperRAM init is done (brief PSRAM noise until the
//     M3 finishes drawing the background, then the game appears)
//   - the read engine free-runs; the FSM re-locks to the raster VSYNC each frame
//   - frame_cnt increments per frame (game tick reference for the M3)
//============================================================================
reg        init_s0, init_s1, started;
reg        primed;       // one-shot: first frame started at FIFO word 0
reg        go_frame;     // set once inside vblank; preloads group 0 before P_RUN
reg [7:0]  frame_cnt_r;

reg [1:0]  pstate;       // P_IDLE / P_RUN
reg [95:0] grp;          // current group (3 words = 4 pixels)
reg [95:0] ngrp;         // next group being loaded
reg [7:0]  gx;           // 0..159 groups per line
reg [8:0]  gy;           // 0..479 lines
reg [2:0]  ph;           // output phase 0..3, 4 = wait at group boundary
reg [1:0]  ld;           // words already loaded into ngrp (0..3)
reg        cap_pending;  // a FIFO read was issued, dout valid next cycle

// Read-path health: lowest video-FIFO fill seen during the current frame, and
// the value latched at the last frame boundary. Shown as a small colour code
// in the bottom-left corner so the read path can be diagnosed WITHOUT a UART.
reg [9:0]  fmin;         // running minimum (this frame)
reg [9:0]  fmin_disp;    // minimum of the previous frame (displayed)

// Read-stall health: how many read bursts hit the IP timeout during the last
// displayed frame (each one injects 32 zero words = a black chunk).
reg [7:0]  st_s0, st_s1;   // stall_cnt 2-flop sync into clk_p
reg [7:0]  stall_prev;     // stall_cnt sampled at the previous frame boundary
reg [7:0]  stall_disp;     // stalls during the last displayed frame

reg        fb_tvalid;
reg        fb_tuser;
reg [23:0] fb_tdata;

localparam P_IDLE  = 2'd0;
localparam P_RUN   = 2'd2;

assign frame_cnt = frame_cnt_r;

//--------------------------------------------------------------------------
// TEST PATTERN (diagnostic, independent of memory path)
//--------------------------------------------------------------------------
wire [9:0] test_x   = {gx, ph[1:0]};          // 0..639
wire [2:0] test_bar = test_x[9:7];            // 8 bars of 80 px
reg [23:0] test_rgb;
always @(*) begin
    // STATIC GEOMETRIC pattern. It is derived ONLY from the pixel counter
    // (gx/gy/ph) and touches no memory, no FIFO and no double-buffer state.
    // A purely flat colour would hide any shift; the bars plus the hard edge
    // markers below make ANY horizontal or vertical motion immediately
    // visible, which is exactly what is needed to tell "frame desync" apart
    // from "TMDS/clock/pixel-path instability".
    case (test_bar)
        3'd0: test_rgb = 24'hFFFFFF;          // white
        3'd1: test_rgb = 24'hFFFF00;          // yellow
        3'd2: test_rgb = 24'h00FFFF;          // cyan
        3'd3: test_rgb = 24'h00FF00;          // green
        3'd4: test_rgb = 24'hFF00FF;          // magenta
        3'd5: test_rgb = 24'hFF0000;          // red
        3'd6: test_rgb = 24'h0000FF;          // blue
        default: test_rgb = 24'h808080;       // grey
    endcase
    // Hard horizontal reference lines (reveal vertical motion).
    if (gy == 9'd0)   test_rgb = 24'hFFFFFF;  // top    : white
    if (gy == 9'd240) test_rgb = 24'hFF00FF;  // middle : magenta
    if (gy == 9'd479) test_rgb = 24'h00FF00;  // bottom : green
    // Hard vertical reference edge (reveals horizontal motion).
    if (test_x < 10'd4) test_rgb = 24'hFF0000; // left 4 columns : red
end

// ---- HARDWARE SPRITE OVERLAY (ball + paddles) ---------------------------
// The M3 no longer stores the ball or the paddles in the framebuffer. It only
// publishes their positions in the APB domain; those four values are sampled
// into clk_p once per frame (on fb_tuser - their source registers are settled
// for the whole ~16.7 ms frame, so a single sample is safe, and no value can
// change half-way down a field and shear an object), then compared
// against the raster as every pixel is shifted out. The objects therefore
// move at the true 60 Hz pixel rate with ZERO HyperRAM write traffic: the
// write channel (one vblank window per frame) is off the game's critical path
// entirely, which is what makes the ball and the paddles smooth AND lets
// their speed be raised freely.
reg  [9:0] sp_p1_y, sp_p2_y, sp_bx, sp_by;

always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        sp_p1_y <= 10'd190; sp_p2_y <= 10'd190;
        sp_bx   <= 10'd320; sp_by   <= 10'd240;
    end else if (fb_tuser) begin
        sp_p1_y <= sp_p1_y_apb;
        sp_p2_y <= sp_p2_y_apb;
        sp_bx   <= sp_bx_apb;
        sp_by   <= sp_by_apb;
    end
end

// Colours are {B,G,R}: fb_tdata is {B,G,R} (see the pixel mux in P_RUN), so
// these are the firmware palette values with their outer bytes swapped.
localparam [23:0] SPR_BALL = 24'h8CF0FF;   // 0xFFF08C warm bright ball
localparam [23:0] SPR_P1   = 24'hFFC800;   // 0x00C8FF cyan paddle
localparam [23:0] SPR_P1HI = 24'hFFF096;   // 0x96F0FF cyan highlight
localparam [23:0] SPR_P2   = 24'h1E5AFF;   // 0xFF5A1E orange-red paddle
localparam [23:0] SPR_P2HI = 24'h96C8FF;   // 0xFFC896 orange highlight

// Priority ball > P1 > P2, matching the old firmware obj_pixel().
function [23:0] spr_px;
    input [9:0]  x;
    input [9:0]  y;
    input [23:0] base;
    reg   [23:0] c;
    begin
        c = base;
        if (y >= sp_p1_y && y < sp_p1_y + 10'd100 &&
            x >= 10'd10 && x < 10'd20)
            c = (x >= 10'd18) ? SPR_P1HI : SPR_P1;
        else if (y >= sp_p2_y && y < sp_p2_y + 10'd100 &&
                 x >= 10'd620 && x < 10'd630)
            c = (x < 10'd622) ? SPR_P2HI : SPR_P2;
        if ((x + 10'd6 >= sp_bx) && (x <= sp_bx + 10'd6) &&
            (y + 10'd6 >= sp_by) && (y <= sp_by + 10'd6))
            c = SPR_BALL;
        spr_px = c;
    end
endfunction

//--------------------------------------------------------------------------
// Encoder VSYNC (out_axis_tuser[2]) = the raster's vertical-sync pulse.
//
// The pixel FSM MUST begin its frame inside the vertical blanking interval.
// P_IDLE holds fb_tvalid LOW (see below), so by the time the FSM starts the
// encoder's 6-deep input FIFO is EMPTY; the FSM's first 6 pixels simply fill
// it during vblank and do not move, so at the first ACTIVE raster pixel the
// encoder consumes FSM pixel 0 - the frame boundary lands on (0,0) exactly.
//
// If the FSM instead starts at an arbitrary raster phase (the old behaviour:
// start as soon as the video FIFO was prefilled), the whole picture is
// displaced by (phase + 6) pixels. The sub-line part shears every line, so a
// horizontal feature - the green grass edge at GROUND_Y - steps between the
// left and right halves; the whole-line part wraps the TOP of the picture
// around to the BOTTOM, so the ball and the left paddle "穿屏" (their top is
// cut and reappears at the bottom-left). The displacement changes with the
// power-up race, which is why the defect moved between builds.
//
// One-shot is enough: the FSM emits exactly 160*480 groups = 307200 px per
// frame, exactly the raster's active length, so once the start is aligned the
// boundary stays locked forever (any frame-end gap would re-introduce the
// arbitrary offset).
reg enc_vs_d;
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) enc_vs_d <= 1'b0;
    else             enc_vs_d <= enc_tuser[2];
end
wire enc_vs_rise = enc_tuser[2] & ~enc_vs_d;

always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        init_s0 <= 1'b0; init_s1 <= 1'b0; started <= 1'b0;
        primed <= 1'b0;
        go_frame <= 1'b0;
        frame_cnt_r <= 8'd0;
        pstate <= P_IDLE;
        grp <= 96'b0; ngrp <= 96'b0;
        gx <= 8'd0; gy <= 9'd0; ph <= 3'd0;
        ld <= 2'd0; cap_pending <= 1'b0;
        fb_tvalid <= 1'b0; fb_tuser <= 1'b0; fb_tdata <= 24'b0;
        fmin <= 10'd512; fmin_disp <= 10'd512;
        st_s0 <= 8'd0; st_s1 <= 8'd0;
        stall_prev <= 8'd0; stall_disp <= 8'd0;
        fifo_re <= 1'b0;
        fifo_re_r <= 1'b0; fifo_nz <= 1'b0;
    end else begin
        init_s0 <= hp_init; init_s1 <= init_s0;

        // stall_cnt -> clk_p (2 flops); the delta is taken at frame boundaries.
        st_s0 <= stall_cnt; st_s1 <= st_s0;

        // HyperRAM calibrated: begin the frame loop
        if ((init_s1 || TEST_PATTERN) && !started) begin
            started <= 1'b1;
        end

        // default: FIFO read strobe is a 1-cycle pulse
        fifo_re <= 1'b0;

        // Track whether the pixel side ever received a NON-ZERO FIFO word.
        fifo_re_r <= fifo_re;
        if (fifo_re_r && (fifo_dout != 32'b0)) fifo_nz <= 1'b1;

        case (pstate)
            //--------------------------------------------------------------
            P_IDLE: begin
                // Leave fb_tvalid LOW here on purpose. Feeding black during
                // P_IDLE used to keep the encoder's 6-deep input FIFO FULL, so
                // when the frame started the FSM's pixels queued BEHIND six
                // stale black words and pixel 0 was displayed 6 px into the
                // line - a permanent 6-px shear. Letting the FIFO drain while
                // the FSM idles means the 6 look-ahead pixels it emits at the
                // start of the frame are its own pixel 0..5, so pixel 0 lands
                // on (0,0). (The encoder's raster and output stage are fully
                // free-running - see svo_enc.v - so an input tvalid gap only
                // blanks pixels; it can never stall the raster or the TMDS.)
                fb_tvalid <= 1'b0;
                fb_tdata  <= 24'h000000;
                fb_tuser  <= 1'b0;
                // Start the frame in P_RUN, self-paced by fb_tready (the
                // encoder's input FIFO back-pressures it). It emits exactly
                // 160*480 groups = 307200 px per frame so its frame boundary
                // stays locked to the raster by construction, and consumes
                // exactly 3 FIFO words per group so it stays locked to the
                // READ STREAM as well.
                //
                // THE ONE-SHOT PREFILL GATE (this is what fixes the picture):
                // the pixel grid must consume read word 0 as pixel 0. If the
                // FSM starts while the FIFO is still empty, the first groups
                // cannot load their 3 words, get painted black and consume
                // NOTHING - so group N ends up showing read words 3(N-k)..
                // i.e. the WHOLE picture is shifted by 4*k px. The read
                // engine's first data arrives ~100 cycles after hp_init, so
                // k was ~25 groups (~100 px): P2 (x=620) wrapped round to
                // x~80, right next to P1 (x=10) -> "both paddles on the left",
                // the ball visually passing through its paddle, and the last
                // ~100 px of every line wrapping into the next line -> 花屏.
                // k depended on the power-up race, which is why every build
                // showed a DIFFERENT shift.
                //
                // Waiting for the FIFO to hold >= 64 words before the very
                // first frame makes the oldest buffered word read word 0, so
                // the grid and the stream start aligned; production ==
                // consumption (230400 words/frame) then keeps them aligned
                // forever. The gate is ONE-SHOT (primed): from the second
                // frame on P_IDLE falls straight through in a single cycle, so
                // the frame length never depends on the FIFO level (that
                // mistake - a per-frame data-dependent start - is what used to
                // make the picture roll while the M3 was writing).
                // (a) video FIFO prefilled (one-shot), and (b) the encoder is
                //     inside its vertical blanking period (enc_vs_rise), so the
                //     frame boundary is deterministic instead of depending on
                //     the power-up race. See the enc_vs_d block above.
                if (!go_frame && started && (primed || fifo_rd_fill >= 10'd64) && enc_vs_rise) begin
                    primed   <= 1'b1;
                    go_frame <= 1'b1;
                end

                // PRELOAD GROUP 0 - the fix for "green grass bar not aligned
                // left-to-right". Run the SAME 3-word loader here, before
                // entering P_RUN, so grp already holds read words 0..2 when the
                // first pixel is emitted.
                //
                // Why it matters: P_IDLE used to enter P_RUN with grp = 96'h0,
                // i.e. group 0 (grid pixels 0..3) was a BLACK group. The 3 words
                // it loaded while emitting it were only latched into grp at the
                // ph==3 boundary, so they were displayed as group 1 - one group
                // (4 px) late. Net effect: EVERY framebuffer pixel appeared 4 px
                // to the RIGHT of its true position, grid(x,y) = buffer(x-4,y).
                // The hardware sprites (ball/paddles) are generated from gx
                // directly and are NOT shifted, so the background - including
                // the GROUND_Y grass edge - sat 4 px off against the sprites,
                // and each line's leftmost 4 px showed the PREVIOUS line's
                // rightmost 4 px: a 4-px notch where the grass bar meets the
                // left edge. Preloading makes grid pixel 0 = buffer pixel 0.
                //
                // The alignment then persists for every later frame: at the
                // frame boundary grp <= ngrp is NOT reset to black, and the read
                // stream is continuous across the engine's wrap (word 230399 is
                // followed by the new frame's word 0), so the carry-over group
                // is exactly the new frame's group 0.
                if (go_frame) begin
                    if (ld != 2'd3) begin
                        if (cap_pending) begin
                            case (ld)
                                2'd0: ngrp[95:64] <= fifo_dout;
                                2'd1: ngrp[63:32] <= fifo_dout;
                                2'd2: ngrp[31:0]  <= fifo_dout;
                            endcase
                            ld <= ld + 2'b1;
                            if (ld != 2'd2 && fifo_has_word) begin
                                fifo_re     <= 1'b1;
                                cap_pending <= 1'b1;
                            end else begin
                                cap_pending <= 1'b0;
                            end
                        end else if (fifo_has_word) begin
                            fifo_re     <= 1'b1;
                            cap_pending <= 1'b1;
                        end
                    end else begin
                        // group 0 fully loaded -> hand it to grp and run
                        grp         <= ngrp;
                        ld          <= 2'd0;
                        cap_pending <= 1'b0;
                        gx          <= 8'd0;
                        gy          <= 9'd0;
                        ph          <= 3'd0;
                        go_frame    <= 1'b0;
                        pstate      <= P_RUN;
                    end
                end
            end

            //--------------------------------------------------------------
            // Output the 4 pixels of grp (ph 0..3) while loading the next
            // group ngrp in parallel.
            //--------------------------------------------------------------
            P_RUN: begin
                // Read-path health monitor: remember the lowest video-FIFO
                // fill seen during this frame (shown in the corner below).
                if (fifo_rd_fill < fmin) fmin <= fifo_rd_fill;

                if (TEST_PATTERN) begin
                    fb_tvalid <= 1'b1;
                    fb_tuser  <= (gx == 8'd0 && gy == 9'd0 && ph == 3'd0);
                    fb_tdata  <= test_rgb;
                    if (fb_tready) begin
                        if (ph != 3'd3) begin
                            ph <= ph + 3'b1;
                        end else begin
                            ph <= 3'd0;
                            if (gx != GROUPS_LINE - 1) begin
                                gx <= gx + 8'b1;
                            end else begin
                                gx <= 8'd0;
                                if (gy != LINE_LAST)
                                    gy <= gy + 9'b1;
                                else
                                    gy <= 9'd0;   // loop, stay in P_RUN
                            end
                        end
                    end
                end else begin
                //-------- next-group loader (runs every cycle) -------------
                if (ld != 2'd3) begin
                    if (cap_pending) begin
                        case (ld)
                            2'd0: ngrp[95:64] <= fifo_dout;
                            2'd1: ngrp[63:32] <= fifo_dout;
                            2'd2: ngrp[31:0] <= fifo_dout;
                        endcase
                        ld <= ld + 2'b1;
                        if (ld != 2'd2 && fifo_has_word) begin
                            fifo_re      <= 1'b1;
                            cap_pending  <= 1'b1;
                        end else begin
                            cap_pending  <= 1'b0;
                        end
                    end else if (fifo_has_word) begin
                        fifo_re     <= 1'b1;
                        cap_pending <= 1'b1;
                    end
                end

                //-------- pixel output (grp already complete) --------------
                // 3 words = 12 bytes = 4 RGB pixels. The word stream is
                // {R,G,B,R|G,B,R,G,B|...} MSB-first, so each pixel needs its
                // two outer bytes swapped to form the {B,G,R} the SVO stack
                // expects.
                if (ph < 3'd4) begin
                    fb_tvalid <= 1'b1;
                    // memory pixel for this phase, with the hardware sprite overlay on top
                    fb_tdata <= spr_px({gx, ph[1:0]}, {1'b0, gy},
                                       (ph[1:0] == 2'd0) ?
                                         {grp[79:72], grp[87:80], grp[95:88]} :
                                       (ph[1:0] == 2'd1) ?
                                         {grp[55:48], grp[63:56], grp[71:64]} :
                                       (ph[1:0] == 2'd2) ?
                                         {grp[31:24], grp[39:32], grp[47:40]} :
                                         {grp[7:0],   grp[15:8],  grp[23:16]});
                    fb_tuser <= (gx == 8'd0 && gy == 9'd0 && ph == 3'd0);
                    // The two 16x8 diagnostic patches (bottom-left FIFO-water,
                    // bottom-right read-timeout) have been REMOVED: the user
                    // asked for a clean playfield. fmin_disp / stall_disp are
                    // now unused and get optimised away.
                end

                if (fb_tready) begin
                    if (ph < 3'd3) begin
                        ph <= ph + 3'b1;
                    end else begin
                        // ph == 3, last pixel of the group.
                        //
                        // THE FRAME CADENCE MUST NEVER DEPEND ON FIFO
                        // AVAILABILITY: the FSM ALWAYS advances exactly one
                        // group and sweeps gx/gy, whether or not the next group
                        // arrived. The old code held ph==3 and repeated the last
                        // pixel while starved - that made the number of pixels
                        // emitted per frame vary, so the FSM's frame boundary
                        // slipped by a different amount every frame and the
                        // whole picture rolled. This is the exact failure mode
                        // the known-good HyperRAM->HDMI reference avoids by
                        // painting one (black) group on underrun instead of
                        // stalling. gx/gy must keep sweeping so a frame-start
                        // marker (fb_tuser) is produced every 307200 px no
                        // matter what the memory path is doing.
                        if (ld == 2'd3) begin
                            grp <= ngrp;        // complete group from the FIFO
                            ld          <= 2'd0;
                            cap_pending <= 1'b0;
                        end else if (ld == 2'd2 && cap_pending) begin
                            // ONE-CYCLE-LATE LOOK-AHEAD. The third word is ON
                            // fifo_dout THIS cycle (it was popped at ph==2), so
                            // the group can still be completed. This happens
                            // (a) on the first group after a frame boundary, and
                            // (b) whenever the FIFO's synchronised empty flag
                            //     falsely delayed the look-ahead read by a cycle.
                            grp <= {ngrp[95:64], ngrp[63:32], fifo_dout};
                            ld          <= 2'd0;
                            cap_pending <= 1'b0;
                        end else begin
                            // STARVED: emit one black group, but KEEP whatever
                            // words were already fetched - ld, ngrp and
                            // cap_pending are deliberately left untouched so the
                            // partial group completes during the NEXT group.
                            //
                            // Discarding them (the old `ld <= 0` here) advanced
                            // the word stream against the pixel grid by 4 or 8
                            // bytes, i.e. by a NON-multiple of 3, which rotated
                            // the R/G/B byte phase for the REST of the frame:
                            // the solid-colour marker came out as vertical
                            // red/green/blue stripes, and on the game scene the
                            // same rotation shows up as colour speckle /
                            // "electric" shimmer. Carrying the words over costs
                            // at most one 4-px hiccup and can never rotate the
                            // colour phase.
                            grp <= 96'h0;       // starved -> one black group
                        end
                        ph          <= 3'd0;
                        fb_tvalid   <= 1'b1;
                        // Restart the loader immediately: the read port is free
                        // again this cycle and the pixel side eats exactly one
                        // word per pixel clock, so a bubble here would make the
                        // loader slower than the encoder. At the very end of the
                        // frame NO look-ahead read is started: the display would
                        // eat that word but the engine would never produce it,
                        // and that single lost word per frame is exactly what
                        // rolled the picture (4 bytes = 1.33 px per frame).
                        if (gx != GROUPS_LINE - 1) begin
                            gx <= gx + 8'b1;
                            // Restart the loader early only when no captured-but-
                            // not-yet-taken word is waiting on fifo_dout;
                            // popping in that state would overwrite it and lose
                            // 4 bytes (colour-phase rotation). When the group was
                            // carried over, the loader restarts itself from its
                            // own idle branch instead.
                            if (fifo_has_word && !(cap_pending && ld < 2'd2)) begin
                                fifo_re     <= 1'b1;
                                cap_pending <= 1'b1;
                            end
                        end else begin
                            gx <= 8'd0;
                            if (gy != LINE_LAST) begin
                                gy <= gy + 9'b1;
                                if (fifo_has_word && !(cap_pending && ld < 2'd2)) begin
                                    fifo_re     <= 1'b1;
                                    cap_pending <= 1'b1;
                                end
                            end else begin
                                // END OF FRAME: exactly 160*480 groups done.
                                //
                                // STAY IN P_RUN (exactly like the test-pattern
                                // branch above). Tripping through P_IDLE used to
                                // emit ONE extra pixel per frame: P_IDLE drives
                                // fb_tvalid=1 with black, so the FSM produced
                                // 307201 px/frame while the encoder consumes
                                // exactly 307200 active pixels. The encoder's
                                // 8-deep AXIS input FIFO therefore gained one
                                // pixel EVERY frame until it back-pressured, at
                                // which point the FSM stalled for a cycle. That
                                // periodic stall moved the pixel grid against the
                                // raster by +/-1 px - the whole picture shimmered
                                // and every object's vertical edge jittered.
                                // Staying in P_RUN emits no extra pixel, so
                                // production == consumption == 307200 exactly and
                                // the grid stays locked to the raster.
                                //
                                // ld / cap_pending / ngrp are deliberately NOT
                                // reset here. Resetting them discarded a word that
                                // had already been popped off the FIFO but not yet
                                // folded into ngrp (the ld==2 && cap_pending case) -
                                // the very same 4-byte step the starvation branch
                                // above used to take. 4 bytes is NOT a multiple of
                                // 3, so it rotated the R/G/B byte phase for the whole
                                // next frame; on screen that is exactly "colour bars
                                // that appear and disappear a few times a second and
                                // flicker". Carrying the partial group into the first
                                // group of the next frame costs at most one black
                                // 4-px group in the bottom-right corner (invisible)
                                // and can never rotate the colour phase.
                                gy          <= 9'd0;
                                frame_cnt_r <= frame_cnt_r + 8'b1;
                                fb_tvalid   <= 1'b1;
                                // Latch this frame's lowest FIFO fill for the
                                // corner indicator, then start a new frame.
                                fmin_disp   <= fmin;
                                fmin        <= 10'd512;
                                // stalls during the frame just finished
                                stall_disp <= st_s1 - stall_prev;
                                stall_prev <= st_s1;
                            end
                        end
                    end
                end
                end // !TEST_PATTERN
            end

            default: pstate <= P_IDLE;
        endcase
    end
end

//============================================================================
// TMDS encode (SVO stack, input = BGR)
//============================================================================
// (fb_tready / enc_* are declared above the pixel streamer, which consumes
//  enc_tuser[2] as its frame-start trigger.)

// CDC: write-activity flags -> clk_p, then an on-screen write-path status.
reg aw_s0, aw_s1, ab_s0, ab_s1;
reg fd_s0, fd_s1;           // fab_done  -> clk_p
reg rnz_s0, rnz_s1;         // rd_nz     -> clk_p
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        aw_s0 <= 1'b0; aw_s1 <= 1'b0;
        ab_s0 <= 1'b0; ab_s1 <= 1'b0;
        fd_s0 <= 1'b0; fd_s1 <= 1'b0;
        rnz_s0 <= 1'b0; rnz_s1 <= 1'b0;
    end else begin
        aw_s0 <= any_word;  aw_s1 <= aw_s0;
        ab_s0 <= any_burst; ab_s1 <= ab_s0;
        fd_s0 <= fab_done;  fd_s1 <= fd_s0;
        rnz_s0 <= rd_nz;    rnz_s1 <= rnz_s0;
    end
end

reg [23:0] diag_rgb;
always @(*) begin
    if (!init_s1)       diag_rgb = 24'h0000FF; // RED     calibration not done
    else if (!aw_s1)    diag_rgb = 24'h00FFFF; // YELLOW  M3 never wrote a word
    else if (!ab_s1)    diag_rgb = 24'hFF00FF; // MAGENTA words but no burst yet
    else                diag_rgb = 24'h000000;
end

wire wr_diag_ok = init_s1 && aw_s1 && ab_s1;
wire [23:0] px_rgb = (DIAG_WRITE && !wr_diag_ok) ? diag_rgb : fb_tdata;

//----------------------------------------------------------------------
// NORM-PATH PROBE stream (clk_p): independent always-valid 640x480 stream
// whose colour reports the normal pixel FSM state. Fed to the encoder only
// when NORM_PROBE=1 (the normal FSM still runs and drives fb_tready pacing).
//----------------------------------------------------------------------
// Sticky observations of the REAL pixel FSM, sampled in the clk_p domain.
//   min_fill : lowest FIFO fill seen while the FSM is running (starvation?)
//   hole_cnt : number of cycles in P_RUN where fb_tvalid was LOW (tvalid holes)
reg [9:0]  min_fill;
reg [15:0] hole_cnt;
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        min_fill <= 10'd1023;
        hole_cnt <= 16'd0;
    end else if (pstate == P_RUN) begin
        if (fifo_rd_fill < min_fill)          min_fill <= fifo_rd_fill;
        if (!fb_tvalid && hole_cnt != 16'hFFFF) hole_cnt <= hole_cnt + 16'd1;
    end
end

reg [9:0] probe_x;
reg [8:0] probe_y;
reg [23:0] probe_rgb;
reg        probe_tuser;
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        probe_x     <= 10'd0;
        probe_y     <= 9'd0;
        probe_rgb   <= 24'h0000FF;
        probe_tuser <= 1'b0;
    end else if (fb_tready) begin
        probe_tuser <= (probe_x == 10'd0 && probe_y == 9'd0);
        if (probe_x < 10'd320)
            // LEFT half: MINIMUM FIFO fill while the FSM runs (starvation?)
            probe_rgb <= (!init_s1)             ? 24'h0000FF : // BLUE    calib
                         (pstate == P_IDLE)     ? 24'hFF0000 : // RED     not running
                         (min_fill >= 8'd64)    ? 24'h00FF00 : // GREEN   never low
                         (min_fill >= 8'd33)    ? 24'hFFFF00 : // YELLOW  33..63
                         (min_fill >= 8'd17)    ? 24'hFF8000 : // ORANGE  17..32
                         (min_fill >= 8'd1)     ? 24'hFF00FF : // MAGENTA 1..16
                                                  24'hFF0000;   // RED     emptied
        else
            // RIGHT half: number of tvalid-hole cycles in P_RUN
            probe_rgb <= (hole_cnt == 16'd0)      ? 24'h00FF00 : // GREEN   none
                         (hole_cnt <= 16'd8)      ? 24'hFFFF00 : // YELLOW  rare
                         (hole_cnt <= 16'd255)    ? 24'hFF8000 : // ORANGE  occasional
                         (hole_cnt <= 16'd4095)   ? 24'hFF00FF : // MAGENTA frequent
                                                    24'hFF0000;   // RED     constant
        if (probe_x == 10'd639) begin
            probe_x <= 10'd0;
            probe_y <= (probe_y == 9'd479) ? 9'd0 : probe_y + 9'd1;
        end else begin
            probe_x <= probe_x + 10'd1;
        end
    end
end

wire        enc_in_tvalid = NORM_PROBE ? 1'b1 : fb_tvalid;
// ---- Blank the HDMI output until the M3 reports the first whole frame -----
// At power-up the read engine scans whatever the HyperRAM happens to contain,
// and the M3 needs ~1 s to fill one buffer through the vblank-limited write
// window, so the monitor used to show about a second of scrolling garbage
// before the scene. apb_ready_tog is a toggle from the APB domain; its first
// edge permanently unblanks the output. Only the DATA is forced black - the
// tvalid/tuser path is untouched, so the SVO encoder's startup gate and the
// raster are unaffected (dropping tvalid here locks the encoder permanently).
reg rdy_s0, rdy_s1, rdy_prev, blank_pix;
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        rdy_s0 <= 1'b0; rdy_s1 <= 1'b0; rdy_prev <= 1'b0; blank_pix <= 1'b1;
    end else begin
        rdy_s0 <= apb_ready_tog; rdy_s1 <= rdy_s0; rdy_prev <= rdy_s1;
        if (rdy_s1 ^ rdy_prev)
            blank_pix <= 1'b0;
    end
end
wire        enc_in_tuser  = NORM_PROBE ? probe_tuser : fb_tuser;
wire [23:0] enc_in_tdata  = NORM_PROBE ? probe_rgb
                          : NORM_CONST  ? 24'hFF00FF
                          : (DIAG_WRITE && !wr_diag_ok) ? diag_rgb
                          : (blank_pix ? 24'h000000 : fb_tdata);

svo_enc #( `SVO_PASS_PARAMS ) enc_inst (
    .clk(clk_p),
    .resetn(sys_resetn),
    .in_axis_tvalid(enc_in_tvalid),
    .in_axis_tready(fb_tready),
    .in_axis_tdata(enc_in_tdata),
    .in_axis_tuser(enc_in_tuser),
    .out_axis_tvalid(enc_tvalid),
    .out_axis_tready(enc_tready),
    .out_axis_tdata(enc_tdata),
    .out_axis_tuser(enc_tuser)
);
assign enc_tready = 1'b1;

wire [2:0] tmds_d;
wire [2:0] tmds_d0, tmds_d1, tmds_d2, tmds_d3, tmds_d4;
wire [2:0] tmds_d5, tmds_d6, tmds_d7, tmds_d8, tmds_d9;

// Channel 0: Blue + control
svo_tmds tmds_0 (
    .clk(clk_p), .resetn(sys_resetn),
    .de(!enc_tuser[3]), .ctrl(enc_tuser[2:1]), .din(enc_tdata[23:16]),
    .dout({tmds_d9[0], tmds_d8[0], tmds_d7[0], tmds_d6[0], tmds_d5[0],
           tmds_d4[0], tmds_d3[0], tmds_d2[0], tmds_d1[0], tmds_d0[0]})
);
// Channel 1: Green
svo_tmds tmds_1 (
    .clk(clk_p), .resetn(sys_resetn),
    .de(!enc_tuser[3]), .ctrl(2'b0), .din(enc_tdata[15:8]),
    .dout({tmds_d9[1], tmds_d8[1], tmds_d7[1], tmds_d6[1], tmds_d5[1],
           tmds_d4[1], tmds_d3[1], tmds_d2[1], tmds_d1[1], tmds_d0[1]})
);
// Channel 2: Red
svo_tmds tmds_2 (
    .clk(clk_p), .resetn(sys_resetn),
    .de(!enc_tuser[3]), .ctrl(2'b0), .din(enc_tdata[7:0]),
    .dout({tmds_d9[2], tmds_d8[2], tmds_d7[2], tmds_d6[2], tmds_d5[2],
           tmds_d4[2], tmds_d3[2], tmds_d2[2], tmds_d1[2], tmds_d0[2]})
);

//============================================================================
// SERIALIZER 10:1 + DIFFERENTIAL OUTPUT BUFFERS
//============================================================================
OSER10 tmds_serdes [2:0] (
    .Q(tmds_d),
    .D0(tmds_d0), .D1(tmds_d1), .D2(tmds_d2), .D3(tmds_d3), .D4(tmds_d4),
    .D5(tmds_d5), .D6(tmds_d6), .D7(tmds_d7), .D8(tmds_d8), .D9(tmds_d9),
    .PCLK(clk_p),
    .FCLK(clk_p5),
    .RESET(~sys_resetn)
);

ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_p, tmds_d}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

//============================================================================
// HyperRAM IP (embedded) - physical pins
//============================================================================
hyper_ram_ctrl u_hyper (
    .sys_clock      (clk),          // IP reference clock = 27MHz board crystal
    .sys_reset_n    (global_resetn),// hold IP reset until PLL locks (avoid init before stable clocks)
    .memory_clk     (memory_clk),
    .pll_lock       (pll_lock),
    .global_reset_n (global_resetn),
    .ex_addr        (hp_addr),
    .ex_wr_req      (hp_wr_req),
    .ex_wr_data     (hp_wr_data),
    .ex_wr_done     (hp_wr_done),
    .ex_rd_req      (hp_rd_req),
    .ex_rd_valid    (hp_rd_valid),
    .ex_rd_data     (hp_rd_data),
    .ex_rd_done     (hp_rd_done),
    .ex_rd_stall    (hp_rd_stall),
    .busy           (hp_busy),
    .init_calib     (hp_init),
    .clk_out        (hp_clkout),
    .O_hpram_ck     (hpram_ck),
    .O_hpram_ck_n   (hpram_ck_n),
    .IO_hpram_rwds  (hpram_rwds),
    .IO_hpram_dq    (hpram_dq),
    .O_hpram_cs_n   (hpram_cs_n),
    .O_hpram_reset_n(hpram_reset_n)
);

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
