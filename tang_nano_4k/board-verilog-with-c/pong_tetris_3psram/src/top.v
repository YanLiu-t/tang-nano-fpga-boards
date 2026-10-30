//============================================================================
// TOP MODULE - Color Pong for Tang Nano 4K (GW1NSR-4C)
//============================================================================
//
// 架构: fabric 是"游戏无关"的显示后端, 只负责 分辨率 + 配色 + 通用矩形物体。
//   Cortex-M3 (Gowin_EMPU, 27MHz) 跑全部游戏逻辑 (规则 / 坐标 / AI / 按键含义),
//   经 APB2 桥做三件事:
//     * 把 8bpp 索引像素按 128 字节 (32 词) 块写入板载 HyperRAM (PSRAM) 帧缓冲
//       (320x240x8bpp = 76800 字节 = 19200 词 = 600 块, 线性排列);
//     * 写 16 项 RGB333 调色板 (索引 -> RGB), 配色完全由这张硬件表决定;
//     * 写 4 条通用矩形物体 (x/y/w/h/颜色索引/使能), fabric 逐像素叠加。
//   fabric 读引擎以 burst128 连续把整帧读入双时钟 FIFO (512x32, 1 块 SDPB),
//   每一对源行 (640 字节 = 正好 5 个突发) 连读两遍 = 垂直 2x;
//   像素侧再把每个字节显示两次 = 水平 2x, 640x480 输出而显存只有 320x240。
//   -> SVO HDMI 栈输出 640x480@60 全彩画面。
//
//   三缓存 (front/middle/back): HyperRAM 里放三整帧, C 渲染 BUF_FREE,
//   fabric 扫描 BUF_DISP, C 填完一帧写 BUF_POST 交还。C 永远不需要等翻转。
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
// 字节顺序:
//   PSRAM 字节流 = 每像素 1 个调色板索引, 第一个字节 = 第 0 像素。
//   1 词 = 4 字节 = 4 像素: p0=W[31:24] p1=W[23:16] p2=W[15:8] p3=W[7:0]。
//   调色板输出 {B,G,R} (SVO 栈输入布局), C 写寄存器时用 0x00RRGGBB。
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
    // UART (EMPU debug, TX only - RX pin 39 is now the buzzer)
    //----------------------------------------------------------------------
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
    output [2:0] tmds_d_p,

    //----------------------------------------------------------------------
    // Buzzer (collision "pong" tone - driven by the REG_BEEP level bit)
    //----------------------------------------------------------------------
    output buzzer
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
localparam BURSTS_FRAME  = 1200;    // 38400 frame words / 32
// The FRAMEBUFFER is 320x240x8bpp (76800 bytes = 38400 2-byte units). The
// read engine fetches it row pair by row pair (2 source rows = 640 bytes =
// exactly FIVE 128-byte bursts) and repeats every pair TWICE, which is what
// produces the 2x vertical upscale for free. The pixel FSM then only has to
// double each source pixel horizontally. Buffer bases: 0, BUF_UNITS, 2*BUF_UNITS.
localparam [21:0] BUF_UNITS   = 22'd38400;   // one 320x240x8bpp frame in 2-byte units
localparam [21:0] BUF_UNITS_2 = 22'd76800;   // buffer 2 base

// NOTE: the bring-up diagnostics that used to live here (static test pattern,
// encoder probe stream, const-data probe, write-status overlay, fabric write
// self-test) are gone. They were all disabled (constant 0) yet still cost
// ~600 registers and their comparators - and GW1NSR-4C is FF/CLS-bound after
// adding the palette and the object table. Removing dead diagnostic hardware
// changes nothing functionally: every one of those paths was unreachable.

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
    .uart0_rxd(1'b1),          // RX unused (pin 39 is the buzzer) - idle high
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
wire [1:0]  buf_post_gray;  // master_pclk -> hp_clkout: gray(posted buffer)
wire        buf_post_tog;   // master_pclk -> hp_clkout: one toggle per post
reg  [1:0]  disp_i;         // hp_clkout: buffer being scanned out
reg  [1:0]  ready_i;        // hp_clkout: posted buffer waiting to be shown
reg         ready_v;        // hp_clkout: ready_i holds a complete frame
reg  [1:0]  free_i;         // hp_clkout: buffer the M3 must render into next
wire [1:0]  disp_gray = disp_i ^ (disp_i >> 1);   // gray coded for the CDC
wire [1:0]  free_gray = free_i ^ (free_i >> 1);
wire [21:0] disp_base = (disp_i == 2'd0) ? 22'd0 :
                        (disp_i == 2'd1) ? BUF_UNITS : BUF_UNITS_2;
wire [21:0] free_base = (free_i == 2'd0) ? 22'd0 :
                        (free_i == 2'd1) ? BUF_UNITS : BUF_UNITS_2;
wire        apb_ready_tog;  // master_pclk -> clk_p toggle: unblank the HDMI output

wire [7:0]  pal_waddr;      // M3 -> palette_ram write port
wire [23:0] pal_wdata;
wire        pal_we;

wire [2:0]  spr_sel;        // M3 -> sprite_overlay write port
wire [2:0]  spr_field;
wire [15:0] spr_wdata;
wire        spr_we;

wire        beep_trig;      // M3 -> buzzer pin (level bit, SysTick toggles it)

apb_fb_reg u_apb_reg (
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
    .buf_post_gray (buf_post_gray),
    .buf_post_tog  (buf_post_tog),
    .disp_gray     (disp_gray),
    .free_gray     (free_gray),
    .fb_ready  (apb_ready_tog),
    .pal_waddr (pal_waddr),
    .pal_wdata (pal_wdata),
    .pal_we    (pal_we),
    .spr_sel   (spr_sel),
    .spr_field (spr_field),
    .spr_wdata (spr_wdata),
    .spr_we    (spr_we),
    .beep_trig (beep_trig)
);

//============================================================================
// BUZZER - driven straight from the beep level bit. The firmware's SysTick ISR
// toggles REG_BEEP (0x5C) at the tone frequency; no fabric tone hardware, so
// GW1NSR-4C's already-full register budget is untouched.
//============================================================================
assign buzzer = beep_trig;

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
// time). It must not be recomputed when the burst is finally issued: the
// scheduler below can delay a write by a whole read burst, and free_i could
// change meanwhile. Recomputing would redirect a block packed for one buffer
// into another -> a horizontal tear. 22 bits = 64 half-word units * 600.
// w_addr_lat uses free_i: the M3 renders the buffer the fabric calls FREE, and
// that index is only ever changed by a POST, i.e. after the M3 has finished a
// whole render - never while a block is being packed.
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

reg  [7:0]  rd_quiet;   // hp cycles since the last read burst completed
reg  [9:0]  wr_cool;    // post-write cooldown
reg  [1:0]  full_vb_cnt; // consecutive vblanks a still-packed block missed
reg         vb_seen_d;   // registered vb_seen (for edge detection below)
reg         wr_hold;     // write pending: read engine is off the bus

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

// Enough elasticity for a window - or the block has missed two consecutive
// vblanks and forcing a write is the lesser evil (keeps the M3 moving if the
// window machinery ever wedges).  A write window normally opens inside the
// very first vblank after the pack buffer fills, so full_vb_cnt never reaches
// 2 in steady state.  If vb_win fails to open for two vblanks running, the
// escape opens wr_armable via (full_vb_cnt >= 2); because it is asserted on
// the rising edge of vb_seen (i.e. inside a detected vblank), even the forced
// write lands in vblank and paints no active-video stripe.  It costs 3 FFs
// (2-bit counter + 1 edge-FF) instead of a wide 2-frame cycle counter.
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
wire wr_armable = vb_win || !startup_done || (full_vb_cnt >= 2'd2);

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        rd_quiet <= 8'd0;
        wr_cool  <= 10'd0;
        full_vb_cnt <= 2'd0;
        vb_seen_d   <= 1'b0;
        wr_hold  <= 1'b0;
    end else begin
        // Time since the read engine last released the bus.
        if (hp_rd_done)              rd_quiet <= 8'd0;
        else if (rd_quiet != 8'hFF)  rd_quiet <= rd_quiet + 8'd1;

        // Post-write cooldown: bound the write duty cycle so the read engine
        // always gets its share of the bus back.
        if (hp_wr_done)              wr_cool <= WR_COOLDOWN;
        else if (wr_cool != 10'd0)   wr_cool <= wr_cool - 10'd1;

        // Deadlock insurance for wr_armable: count vblank detections in which
        // a packed, still-undrained block failed to get its burst out.  In
        // normal operation the block drains on the first such vblank, so the
        // count never reaches 2.  Only a wedged window machinery lets it climb
        // to 2, where wr_armable is forced open (see the wire above).
        vb_seen_d <= vb_seen;
        if (!full || hp_wr_done)
            full_vb_cnt <= 2'd0;
        else if (vb_seen && !vb_seen_d && full_vb_cnt != 2'd3)
            full_vb_cnt <= full_vb_cnt + 2'd1;

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
                    // (free_i, which a POST only changes after this very ack).
                    wr_addr_lat <= {3'b0, blk_s1, 6'b0} + free_base;
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

// word 0 is presented by the W_ISSUE mux; afterwards pack_mem[ridx] streams.
// hp_wr_req pulses exactly when the scheduler opens a write window - the same
// condition that advances W_ISSUE -> W_STREAM, so the request is one cycle
// long and the controller latches address + word 0 together.
wire [31:0] hp_wr_data_pack = (w_state == W_ISSUE) ? pack_mem[5'd0] : pack_mem[ridx];
wire        hp_wr_req_pack  = (w_state == W_ISSUE) && wr_burst_ok;

assign hp_wr_data = hp_wr_data_pack;
assign hp_wr_req  = hp_wr_req_pack;

//============================================================================
// Read engine (hp_clkout): FREE-RUNNING stream of the whole 320x240 frame in
// 1200 burst128 tasks into the async FIFO. A new burst starts only when the
// FIFO has 32 free words (fifo_can_burst).
//
// GEOMETRY: two source rows = 640 bytes = exactly FIVE 128-byte bursts, so the
// pair is burst-aligned with no padding at all. The pair is streamed TWICE
// (rd_copy), which is the whole 2x vertical upscale: the pixel FSM sees every
// source row twice and never needs a line buffer or an odd/even line test.
//   burst n : sub = n mod 5 (128B within the pair), copy = (n/5) mod 2,
//             unit = n/10 (pair index), address = unit*320 + sub*64.
// rd_base carries unit*320 and is advanced by an accumulator (no divider).
// 1200 bursts x 128 B = 153600 B = one 320x240 frame read twice.
//============================================================================
reg [21:0] rd_base;      // unit * 320: half-word offset of the current row pair
reg [2:0]  rd_sub;       // 0..4 : 128-byte burst inside the 640-byte row pair
reg        rd_copy;      // 0/1  : first or second pass over the row pair
reg [12:0] rburst;       // 0..1199
reg [1:0]  pi_s0, pi_s1;            // buf_post_gray sync (master_pclk -> hp)
reg        pt_s0, pt_s1, pt_prev;   // buf_post_tog  sync + edge detect
reg [6:0]  rd_guard;                // read hold-off after a write burst

// A POST strobe: the M3 finished rendering one buffer and handed it over.
wire        post_pulse = pt_s1 ^ pt_prev;
wire [1:0]  post_w     = {pi_s1[1], pi_s1[1] ^ pi_s1[0]};   // gray decode

// Address of the burst the read engine presents RIGHT NOW: the row-pair base
// plus 128 bytes per completed sub-burst, offset by the scanned buffer's base.
wire [21:0] rd_addr = rd_base + {13'b0, rd_sub, 6'b0};

reg        fifo_re;      // read enable in clk_p domain

// The read engine FREE-RUNS: it streams the frame over and over and is
// throttled ONLY by fifo_can_burst (32 free words). There is deliberately NO
// per-frame stop/restart and NO frame-boundary synchroniser (this is the
// known-good HyperRAM->HDMI reference's structure). A stop/restart gap drains
// the FIFO every frame, and the resulting variable-length drain gap is what
// made the picture flicker. Free-running keeps the FIFO near full (~96 words
// = ~5 us) so the pixel side never starves on HyperRAM latency/refresh gaps.
wire rd_active = hp_init;
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
        rd_base <= 22'd0; rd_sub <= 3'd0; rd_copy <= 1'b0; rburst <= 13'd0;
        pi_s0 <= 2'd0; pi_s1 <= 2'd0;
        pt_s0 <= 1'b0; pt_s1 <= 1'b0; pt_prev <= 1'b0;
        disp_i <= 2'd0; ready_i <= 2'd0; ready_v <= 1'b0; free_i <= 2'd1;
        rd_guard <= 7'd0;
    end else begin
        // 2-flop sync of the POST request (gray-coded index + toggle).
        pi_s0 <= buf_post_gray; pi_s1 <= pi_s0;
        pt_s0 <= buf_post_tog;  pt_s1 <= pt_s0; pt_prev <= pt_s1;

        // Post-write read hold-off (see hp_rd_req above).
        if (hp_wr_done)             rd_guard <= WR_GUARD_CYCLES;
        else if (rd_guard != 7'd0)  rd_guard <= rd_guard - 7'd1;

        //------------------------------------------------------------------
        // THREE-BUFFER POST (M3 -> fabric): the M3 finished rendering the
        // buffer it was given by BUF_FREE and hands it back. Standard
        // front/middle/back:
        //   * nothing waiting (READY empty) -> the new frame becomes READY and
        //     the third buffer (neither scanned nor posted) becomes FREE;
        //   * READY still occupied (the M3 got ahead of the display) -> the
        //     waiting frame is superseded, so IT becomes FREE and the just
        //     finished frame takes its place.
        // The 3-buffer invariant - DISP, READY and the M3's render target are
        // always three DIFFERENT buffers - is what lets the M3 render without
        // ever waiting for a flip, which is why the firmware no longer needs
        // wait_disp().
        //
        // NOTE: a POST never touches free_i while a block is being packed: the
        // M3 only posts after the last FB_DATA ack, and wr_addr_lat is latched
        // at that very ack - and a revolution wrap deliberately leaves free_i
        // alone (only DISP is advanced there).
        //------------------------------------------------------------------
        if (post_pulse && post_w != 2'd3) begin
            if (ready_v) begin
                free_i  <= ready_i;
                ready_i <= post_w;
            end else begin
                ready_i <= post_w;
                ready_v <= 1'b1;
                free_i  <= 2'd3 - disp_i - post_w;   // the only other buffer
            end
        end

        //------------------------------------------------------------------
        // Revolution wrap (read engine's own frame boundary).
        //
        // The address change is continuous in the stream (last burst of the
        // old buffer is followed by the first burst of the new one) and the
        // wrap phase is locked to the display frame: the engine is throttled
        // by fifo_can_burst and the pixel side is paced by the raster, so the
        // FIFO-level pattern repeats every frame and the seam sits at a fixed,
        // invisible spot.
        //
        // A POST that lands on THIS very cycle must NOT be consumed: it is a
        // brand-new completed frame, so the wrap is skipped for it and DISP
        // advances at the next revolution instead (one frame late, invisible).
        //------------------------------------------------------------------
        if (rd_active && hp_rd_done && (rburst == BURSTS_FRAME - 13'd1)) begin
            rburst  <= 13'd0;
            rd_sub  <= 3'd0;
            rd_copy <= 1'b0;
            rd_base <= 22'd0;
            if (ready_v && !(post_pulse && post_w != 2'd3)) begin
                disp_i  <= ready_i;
                ready_v <= 1'b0;
            end
        end else if (rd_active && hp_rd_done) begin
            rburst <= rburst + 13'b1;
            if (rd_sub != 3'd4) begin
                rd_sub <= rd_sub + 3'd1;
            end else begin
                rd_sub <= 3'd0;
                if (rd_copy) begin
                    // the row pair has been streamed twice -> next pair
                    rd_copy <= 1'b0;
                    rd_base <= rd_base + 22'd320;
                end else begin
                    rd_copy <= 1'b1;   // second pass over the same row pair
                end
            end
        end
    end
end

// HyperRAM address mux: follows whichever request is actually presented to
// the controller this cycle (the controller latches ex_addr on the req edge).
// hp_wr_req and hp_rd_req are mutually exclusive by construction.
//
// TRIPLE BUFFER: disp_i selects the buffer being scanned out, and the M3
// renders into free_i (see the POST block above), so a render never touches a
// buffer that is visible or about to become visible. disp_i only ever changes
// at the read engine's own revolution wrap.
assign hp_addr = hp_wr_req ? wr_addr_lat : (rd_addr + disp_base);

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
reg [31:0] grp;          // current group (1 word = 4 palette indices)
reg [31:0] ngrp;         // next group being loaded
reg [7:0]  gx;           // 0..159 groups per line
reg [8:0]  gy;           // 0..479 lines
reg [2:0]  ph;           // output phase 0..3
reg        ld;           // a word is parked in ngrp
reg        cap_pending;  // a FIFO read was issued, dout valid next cycle

reg        fb_tvalid;
reg        fb_tuser;
reg [23:0] fb_tdata;

localparam P_IDLE  = 2'd0;
localparam P_RUN   = 2'd2;

assign frame_cnt = frame_cnt_r;

// ---- GENERIC OBJECT OVERLAY + COLOUR PALETTE ----------------------------
// The fabric no longer knows what a paddle or a ball is. It offers 4 free
// rectangles (sprite_overlay.v) and a 16-entry RGB333 colour palette
// (palette_ram.v); the C firmware decides how many objects exist, their size,
// position and colour index, and the whole colour scheme. Both tables are
// plain flip-flops in the APB (master_pclk) domain that the pixel path reads
// combinationally: a field written mid-frame can only mis-colour the pixel
// being emitted in that instant, so no shadow bank / frame latch is needed.

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

//--------------------------------------------------------------------------
// Generic object table + colour palette (see the note above)
//   px_x / px_y : the raster coordinate of the pixel currently on the output
//   fb_idx      : palette index from the 8bpp framebuffer word (grp)
//   spr_hit/idx : the object table's answer for this pixel (overrides fb_idx)
//   pal_rgb     : the ONLY place a colour exists - index -> {B,G,R}
//--------------------------------------------------------------------------
wire [9:0]  px_x   = {gx, ph[1:0]};
wire [9:0]  px_y   = {1'b0, gy};
// 2x HORIZONTAL UPSCALE: every framebuffer byte is shown as TWO output pixels
// (ph 0,1 and ph 2,3), and one FIFO word therefore covers TWO output groups.
// The byte inside the word is ((gx&1)<<1) | (ph>>1). The 2x VERTICAL upscale
// already happened in the read engine, which streams each source row twice.
wire [1:0]  bsel   = {gx[0], ph[1]};
wire [7:0]  fb_idx = (bsel == 2'd0) ? grp[31:24] :
                     (bsel == 2'd1) ? grp[23:16] :
                     (bsel == 2'd2) ? grp[15:8]  : grp[7:0];
// The object table works in LOW-RESOLUTION pixels: the M3 gives every
// coordinate and size in 320x240 units and the fabric doubles it here, so a
// rectangle can only move in 2-pixel steps on the 640x480 raster.
wire [9:0]  spr_x  = px_x >> 1;
wire [9:0]  spr_y  = px_y >> 1;
wire        spr_hit;
wire [7:0]  spr_idx;
wire [7:0]  pix_idx = spr_hit ? spr_idx : fb_idx;
wire [23:0] pal_rgb;

palette_ram u_palette (
    .pclk  (master_pclk),
    .we    (pal_we),
    .waddr (pal_waddr),
    .wdata (pal_wdata),
    .raddr (pix_idx[3:0]),
    .rgb   (pal_rgb)
);

sprite_overlay #(.NS(5)) u_sprites (
    .pclk     (master_pclk),
    .presetn  (apb_resetn),
    .we       (spr_we),
    .sel      (spr_sel),
    .field    (spr_field),
    .wdata    (spr_wdata),
    .x        (spr_x),
    .y        (spr_y),
    .idx      (spr_idx),
    .hit      (spr_hit)
);

always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        init_s0 <= 1'b0; init_s1 <= 1'b0; started <= 1'b0;
        primed <= 1'b0;
        go_frame <= 1'b0;
        frame_cnt_r <= 8'd0;
        pstate <= P_IDLE;
        grp <= 32'b0; ngrp <= 32'b0;
        gx <= 8'd0; gy <= 9'd0; ph <= 3'd0;
        ld <= 1'b0; cap_pending <= 1'b0;
        fb_tvalid <= 1'b0; fb_tuser <= 1'b0; fb_tdata <= 24'b0;
        fifo_re <= 1'b0;
    end else begin
        init_s0 <= hp_init; init_s1 <= init_s0;

        // HyperRAM calibrated: begin the frame loop
        if (init_s1 && !started) begin
            started <= 1'b1;
        end

        // default: FIFO read strobe is a 1-cycle pulse
        fifo_re <= 1'b0;

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
                    // Preload group 0 with the SAME one-word loader P_RUN uses,
                    // so grp already holds read word 0 when the first pixel is
                    // emitted. Without this the first group would be black and
                    // every framebuffer pixel would sit one group (4 px) to the
                    // right of the hardware objects.
                    if (cap_pending) begin
                        ngrp <= fifo_dout;
                        ld   <= 1'b1;
                        cap_pending <= 1'b0;
                    end else if (!ld) begin
                        if (fifo_has_word) begin
                            fifo_re     <= 1'b1;
                            cap_pending <= 1'b1;
                        end
                    end else begin
                        // group 0 loaded -> hand it to grp and run
                        grp         <= ngrp;
                        ld          <= 1'b0;
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
                //-------- next-word loader (runs every cycle) --------------
                // 8bpp + 2x horizontal upscale: ONE word = 4 source pixels =
                // TWO output groups. cap_pending means a FIFO read was issued
                // last cycle, so fifo_dout holds the word NOW; ld means a word
                // is parked in ngrp. The loader itself stays greedy - the half
                // RATE comes from only consuming at an odd gx (below), so ld
                // blocks the next fetch for exactly one extra group.
                if (cap_pending) begin
                    ngrp <= fifo_dout;
                    ld   <= 1'b1;
                    cap_pending <= 1'b0;
                end else if (!ld && fifo_has_word) begin
                    fifo_re     <= 1'b1;
                    cap_pending <= 1'b1;
                end

                //-------- pixel output (grp holds 4 palette indices) -------
                // The framebuffer byte is a PALETTE INDEX; the generic object
                // table overrides it when a rectangle covers this pixel, and
                // the palette turns the final index into {B,G,R}.
                if (ph < 3'd4) begin
                    fb_tvalid <= 1'b1;
                    fb_tdata  <= pal_rgb;
                    fb_tuser  <= (gx == 8'd0 && gy == 9'd0 && ph == 3'd0);
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
                        // STARVED: emit one black (index 0) group, but KEEP the
                        // parked word/state - ld, ngrp and cap_pending are
                        // deliberately left untouched so the group completes
                        // during the NEXT one. Discarding them used to advance
                        // the word stream against the pixel grid by a
                        // non-multiple of the group, which rotated the byte
                        // phase for the rest of the frame (colour speckle /
                        // "electric" shimmer). Carrying them over costs at most
                        // one 4-px hiccup and can never rotate the phase.
                        // ONE FIFO word spans TWO output groups now, so a new
                        // word is consumed only when the PAIR ends (gx odd). The
                        // even group re-uses grp as-is - which is also why a
                        // starvation there must not blank it: the even group's
                        // source word is the one already in grp, so replacing it
                        // with black would corrupt the odd group too.
                        if (gx[0]) begin
                            if (ld) begin
                                grp <= ngrp;            // next source word
                                ld  <= 1'b0;
                                cap_pending <= 1'b0;
                            end else if (cap_pending) begin
                                // the word is on fifo_dout THIS cycle
                                grp <= fifo_dout;
                                ld  <= 1'b0;
                                cap_pending <= 1'b0;
                            end else begin
                                grp <= 32'h0;           // starved -> black pair
                            end
                        end
                        ph        <= 3'd0;
                        fb_tvalid <= 1'b1;

                        if (gx != GROUPS_LINE - 1) begin
                            gx <= gx + 8'b1;
                        end else begin
                            gx <= 8'd0;
                            if (gy != LINE_LAST) begin
                                gy <= gy + 9'b1;
                            end else begin
                                // END OF FRAME: exactly 160*480 groups done.
                                // STAY IN P_RUN so no extra pixel is emitted and
                                // keep ld / cap_pending / ngrp, so production ==
                                // consumption == 38400 words per frame and the
                                // grid stays locked to the raster.
                                gy          <= 9'd0;
                                frame_cnt_r <= frame_cnt_r + 8'b1;
                                fb_tvalid   <= 1'b1;
                            end
                        end
                    end
                end
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
wire        enc_in_tvalid = fb_tvalid;
wire        enc_in_tuser  = fb_tuser;
wire [23:0] enc_in_tdata  = blank_pix ? 24'h000000 : fb_tdata;

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
