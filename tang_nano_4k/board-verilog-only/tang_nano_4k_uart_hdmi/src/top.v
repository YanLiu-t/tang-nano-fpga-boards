//============================================================================
// TOP - UART -> HyperRAM -> HDMI 640x480 RGB888 (Tang Nano 4K, GW1NSR-4C)
//============================================================================
//
// 数据通路 (纯 fabric 逻辑, 不使用 M3, 无需任何 C 固件):
//   PC --UART 921600--> uart_upload.v (纯 Verilog 16x 过采样接收) 每 4 字节
//   打包一个 32-bit 词 -> req/ack 电平握手 -> fabric 每收 32 词 = 128 字节
//   发起一次 HyperRAM burst128 顺序写满整帧 (230400 词 = 7200 次突发)
//   -> 收满后引擎拉高 start (等价 CTRL=START) -> 读引擎以 burst128 连续把
//   整帧读入双时钟 FIFO (64x32, 1 块 SDPB) -> 25.2MHz 像素侧 3 词->4 像素
//   (BGR 重排) -> SVO HDMI 栈输出 640x480@60, 每帧重复读同一幅静态图。
//
// 时钟方案:
//   clk (27MHz 晶振) ─┬─> UART 上传引擎
//                    └─> HyperRAM IP 'clk' 参考时钟输入
//   clk -> PLLVR ─┬─> clk_p5 (126MHz, TMDS 串行) -> CLKDIV(/5) -> clk_p (25.2MHz)
//                 └─> clk_d63 (63MHz, HyperRAM memory_clk)
//                        └─IP 内部 /2 -> hp_clkout (31.5MHz, CLK Ratio 1:2)
//   HyperRAM 用户侧/写打包/读引擎/FIFO 写侧: hp_clkout (31.5MHz, IP 输出)
//   像素流/FIFO 读侧: clk_p (25.2MHz)
//
// BSRAM 预算 (共 10 块, 仅用 2):
//   HyperRAM IP 内部 x1 + 视频 FIFO SDPB x1 = 2 (M3 已移除, 不占 TCM)。
//   32 词写打包用 reg 阵列 (RAM16/FF), 不占 BSRAM。
//
// 字节顺序:
//   UART 收到的 RGB888 字节流 = 每像素 {R,G,B} 顺序, 第一个字节 = 第 0 像素 R。
//   uart_upload 按 MSB 优先打包 4 字节 -> word[31:24]=最先收到的字节。
//   word0={p0.R,p0.G,p0.B,p1.R}, word1={p1.G,p1.B,p2.R,p2.G},
//   word2={p2.B,p3.R,p3.G,p3.B}。3 词 = 12 字节 = 4 像素。
//   SVO 栈输入 BGR (svo_rgba = {a,b,g,r}), 输出做字节倒序。
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
    // UART (pure-Verilog upload engine, PC image upload)
    //----------------------------------------------------------------------
    input  uart0_rxd,       // Pin 40 (external 3.3V USB-TTL TXD)
    output uart0_txd,       // Pin 39 (external 3.3V USB-TTL RXD)

    //----------------------------------------------------------------------
    // HyperRAM physical pins (embedded die - no external .cst, see note)
    //----------------------------------------------------------------------
    // Embedded HyperRAM on the GW1NSR-4C die-in-package.
    // The port NAMES must match the IP pseudo-ports EXACTLY and be [0:0]
    // vectors. The fitter identifies the embedded HyperRAM by these names
    // and binds them to the dedicated die pins (shown as "p1-xx" in the
    // pin report). With renamed or scalar ports the fitter silently
    // auto-places them on ordinary user I/O, the embedded die is never
    // driven and init_calib stays 0 forever.
    inout  [7:0] IO_hpram_dq,
    inout  [0:0] IO_hpram_rwds,
    output [0:0] O_hpram_ck,
    output [0:0] O_hpram_ck_n,
    output [0:0] O_hpram_cs_n,
    output [0:0] O_hpram_reset_n,

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
// "640x480V" = STANDARD VGA (800x525 total) which is exactly 60.000 Hz at the
// 25.2 MHz pixel clock. The plain "640x480" entry is 800x500 -> 63.0 Hz, a
// non-standard refresh that many monitors refuse to lock ("no signal", steady
// red LED) even though the TMDS stream itself is perfectly valid.
parameter SVO_MODE             = "640x480V";
parameter SVO_FRAMERATE        = 60;
parameter SVO_BITS_PER_PIXEL   = 24;
parameter SVO_BITS_PER_RED     = 8;
parameter SVO_BITS_PER_GREEN   = 8;
parameter SVO_BITS_PER_BLUE    = 8;
parameter SVO_BITS_PER_ALPHA   = 0;

localparam LINE_WORDS    = 480;     // 640 px * 3 B / 4 B
localparam LINE_LAST     = 479;
localparam GROUPS_LINE   = 160;     // 640 px / 4
localparam BURST_WORDS   = 32;      // 128-byte burst = 32 words
localparam BURSTS_FRAME  = 7200;    // 230400 frame words / 32
localparam [21:0] ADDR_STEP = 22'd64; // 128 bytes in 2-byte addr units

// DIAGNOSTIC: when 1, the pixel FSM streams ONLY the internally generated
// test pattern (8 BGR vertical bars + 32px black grid + white border) and
// never touches UART/HyperRAM/FIFO. Normal operation is 0, in which case
// the same pattern is still shown automatically until the memory path has
// delivered a frame (see img_live/test_pat below). That makes the video
// pipeline self-observable: bars appear the instant the pixel clock runs, so
//   - bars forever          -> TMDS/pixel clock fine, HyperRAM read dead
//   - bars, then the image  -> whole chain healthy
//   - nothing at all        -> TMDS/PLL path is the fault
localparam TEST_PATTERN = 1'b0;

//============================================================================
// CLOCKS / RESETS
//============================================================================
wire pll_lock;
wire clk_p5;            // 126 MHz  (PLL CLKOUT, TMDS serial)
wire clk_d63;           // 63 MHz   (PLL CLKOUTD, HyperRAM memory_clk)
                        // 31.5 MHz HyperRAM user clock = hp_clkout (IP: memory_clk/2)
wire clk_p;             // 25.2 MHz pixel clock
wire sys_resetn;        // clk_p domain reset
wire global_resetn;     // resetn & pll_lock (HyperRAM FSM)

//----------------------------------------------------------------------
// HyperRAM clocks:
//   memory_clk = 63 MHz  (PLL CLKOUTD, W956D8MKY 安全区)
//   controller = 31.5 MHz (CLKDIV /2 of clk_d63, CLK Ratio 1:2)
//----------------------------------------------------------------------
wire memory_clk = clk_d63;

assign global_resetn = resetn & pll_lock;

//============================================================================
// PLL - 126 MHz
//============================================================================
Gowin_PLLVR pll_inst (
    .clkout (clk_p5),
    .lock   (pll_lock),
    .clkoutd(clk_d63),
    .clkin  (clk)
);

//============================================================================
// 31.5 MHz HyperRAM user clock is generated INSIDE the IP (it divides
// memory_clk by 2 and outputs it as hp_clkout). The IP's 'clk' reference
// input is the 27MHz board crystal (see u_hyper below), and ALL HyperRAM
// user logic runs on hp_clkout - no external divider.
//============================================================================

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
// PURE-VERILOG UART UPLOAD ENGINE (replaces Gowin_EMPU M3 + C firmware)
//   27MHz fabric domain; drives the same word/req/start/ack handshake that
//   the APB2 bridge used to expose. top.v's existing 2-flop synchronizers
//   into hp_clkout remain unchanged.
//============================================================================
wire        eng_resetn;

Reset_Sync reset_sync_eng (
    .resetn(eng_resetn),
    .ext_reset(resetn & pll_lock),
    .clk(clk)
);

//============================================================================
// REGISTER HANDSHAKE - UART image word stream (pure Verilog)
//============================================================================
wire [31:0] apb_word;
wire        apb_req;      // toggles per word (clk 27MHz domain)
wire        apb_start;    // level high after full frame (clk 27MHz domain)
wire        apb_ack;      // toggles per consumed word (clk_out domain)

// HyperRAM status consumed by the upload engine's diagnostic packet.
// MUST be declared BEFORE u_upload: Gowin's parser does NOT hoist
// module-level declarations - later declarations leave the instance
// port tied to an undriven implicit net (EX3638 / EX1998).
wire        hp_init;
wire        hp_busy;
wire        hp_wact;
wire [7:0]  hp_rd_status;

uart_upload #(
    .CLK_HZ     (27000000),
    .BAUD       (921600),
    .FRAME_WORDS(230400)
) u_upload (
    .clk      (clk),
    .rstn     (eng_resetn),
    .rxd      (uart0_rxd),
    .txd      (uart0_txd),
    .out_data (apb_word),
    .out_req  (apb_req),
    .out_start(apb_start),
    .out_ack  (apb_ack),
    .hp_init  (hp_init),
    .hp_busy  (hp_busy),
    .hp_wact  (hp_wact),
    .hp_rd_status (hp_rd_status)
);

//============================================================================
// HyperRAM controller signals
//============================================================================
wire [21:0] hp_addr;
wire [31:0] hp_wr_data;
wire        hp_wr_req;
wire        hp_wr_done;
wire        hp_rd_req;
wire        hp_rd_valid;
wire [31:0] hp_rd_data;
wire        hp_rd_done;
wire        hp_clkout;

//============================================================================
// Write-path FSM (UART words -> HyperRAM burst128), hp_clkout domain
//   - 2-flop sync of APB2 bridge outputs (master_pclk -> hp_clkout)
//   - incoming words fill pack_mem[0..31] (flip-flop/RAM16, no BSRAM)
//   - 32 words = 128 bytes -> one streaming burst write, addr += 64
//   - ack toggles per accepted word (backpressure while a burst is running)
//
// Stream timing contract with hyper_ram_ctrl:
//   W_ISSUE cycle  : hp_wr_req=1 and hp_wr_data=pack_mem[0] (controller
//                    samples word 0 on this edge, issues IP command next)
//   W_STREAM cyc k : hp_wr_data=pack_mem[k+1], k=0..30
//============================================================================
reg [31:0] pack_mem [0:31];
reg [31:0] wd_s0, wd_s1;
reg        wr_s0, wr_s1, wr_prev;
reg        wr_acc;        // acceptance pulse, DELAYED one hp_clkout cycle
reg        st_s0, st_s1;
reg [4:0]  pack_cnt;      // next incoming slot
reg [4:0]  ridx;          // current read-present slot
reg [21:0] wr_addr;
reg [1:0]  w_state;
reg [6:0]  w_to;        // burst-stall watchdog (W_STREAM cycles), 127*31.7ns
reg        display_mode;  // 1 after START: stop accepting, display forever
reg        ack_toggle;

localparam W_IDLE   = 2'd0;
localparam W_ISSUE  = 2'd1;
localparam W_STREAM = 2'd2;

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        wd_s0 <= 32'b0; wd_s1 <= 32'b0;
        wr_s0 <= 1'b0;  wr_s1 <= 1'b0;  wr_prev <= 1'b0;
        wr_acc <= 1'b0;
        st_s0 <= 1'b0;  st_s1 <= 1'b0;
        pack_cnt <= 5'd0; ridx <= 5'd0;
        wr_addr <= 22'd0; w_state <= W_IDLE; w_to <= 7'd0;
        display_mode <= 1'b0; ack_toggle <= 1'b0;
    end else begin
        // 2-flop sync of APB2 bridge outputs
        wd_s0 <= apb_word; wd_s1 <= wd_s0;
        wr_s0 <= apb_req;  wr_s1 <= wr_s0;  wr_prev <= wr_s1;
        // Acceptance pulse is the edge detect DELAYED one more cycle: at the
        // (wr_s1 ^ wr_prev) instant wd_s1 still holds the FIRST sample of the
        // 32-bit payload, which may be metastable/old. Registering the pulse
        // gives the payload an extra full hp_clkout cycle to settle before
        // pack_mem samples it -> no more duplicated (previous) words.
        wr_acc <= (wr_s1 ^ wr_prev);
        st_s0 <= apb_start; st_s1 <= st_s0;

        // latch start (display mode) once CTRL is written
        if (st_s1) display_mode <= 1'b1;

        // The case always runs so a burst already in W_ISSUE/W_STREAM can
        // finish after display_mode is set; only W_IDLE acceptance is gated.
        case (w_state)
                W_IDLE: begin
                    // hp_init gate: a burst issued before the IP has finished
                    // calibration never completes, so W_STREAM's w_to==127
                    // watchdog silently abandons it - the 32 words are lost
                    // while wr_addr still advances, leaving a 32-word hole in
                    // the stored picture. Only accept once init_calib is up.
                    if (!display_mode && hp_init && wr_acc) begin
                        pack_mem[pack_cnt] <= wd_s1;
                        ack_toggle <= ~ack_toggle;
                        if (pack_cnt == 5'd31) begin
                            pack_cnt <= 5'd0;
                            w_state  <= W_ISSUE;   // read slot 0 already muxed
                        end else begin
                            pack_cnt <= pack_cnt + 5'b1;
                        end
                    end
                end

                // one-cycle request: controller samples word 0 this edge
                W_ISSUE: begin
                    ridx    <= 5'd1;              // next cycle presents word 1
                    w_to    <= 7'd0;
                    w_state <= W_STREAM;
                end

                W_STREAM: begin
                    if (hp_wr_done) begin
                        wr_addr <= wr_addr + ADDR_STEP;
                        w_state <= W_IDLE;
                    end else if (w_to == 7'd127) begin
                        // burst never completed (e.g. HyperRAM IP init not
                        // done): abandon the task so the frame can finish
                        w_to    <= 7'd0;
                        wr_addr <= wr_addr + ADDR_STEP;
                        w_state <= W_IDLE;
                    end else begin
                        w_to <= w_to + 7'd1;
                        if (ridx != 5'd31)
                            ridx <= ridx + 5'b1;
                    end
                end

                default: w_state <= W_IDLE;
        endcase
    end
end

assign apb_ack = ack_toggle;

// write FSM active (status packet, diagnostics)
assign hp_wact = (w_state != W_IDLE);

// word 0 is presented by the W_ISSUE mux; afterwards pack_mem[ridx] streams
assign hp_wr_data = (w_state == W_ISSUE) ? pack_mem[5'd0] : pack_mem[ridx];
assign hp_wr_req  = (w_state == W_ISSUE);

//============================================================================
// Read engine (hp_clkout): stream the whole frame in 7200 burst128 tasks
// into the async FIFO. A new burst starts only when the FIFO holds <= 32
// words (wr_can_burst), which leaves 32 words of elasticity across the IP
// read-latency gap between bursts.
//============================================================================
reg [21:0] rd_addr;
reg [12:0] rburst;       // 0..7199

//--------------------------------------------------------------------------
// Frame-boundary word conservation.
//
// The read engine's revolution and the displayed frame are two free-running
// loops over the same 230400 words. If the display ever consumes one word
// that the engine does not also produce, the picture rolls by 4 bytes =
// 1.33 px per frame and - because 4 is not a multiple of the 3 bytes per
// pixel - the colour cast rotates a little every frame.
//
// That is exactly what the old frame-boundary look-ahead read did: P_RUN
// started one extra FIFO read in the last group of the frame and P_IDLE then
// cleared cap_pending, silently throwing that word away. P_RUN now starts NO
// read at the frame end (see the gx/gy split at the bottom of P_RUN), so the
// counts match exactly - 7200 bursts = 230400 words per revolution = the words
// the display eats per frame - and the FIFO offset is periodic per frame.
//
// Parking the engine and draining the FIFO here was tried twice (v14, v17) and
// came up black on hardware both times: the pixel FSM ended up sitting in the
// alignment state emitting black without ever producing a frame marker, the
// encoder's out_fifo drained and the output stage froze. Do not reintroduce it.
//--------------------------------------------------------------------------

wire fifo_full;
wire fifo_can_burst;
wire fifo_empty;
wire fifo_has_word;
wire [7:0] fifo_rd_fill;
wire [31:0] fifo_dout;
reg        fifo_re;      // read enable in clk_p domain

// The read engine FREE-RUNS once display mode is on: it streams the stored
// frame over and over (the address wraps at the end of the frame) and is
// throttled only by fifo_can_burst. There is deliberately NO per-frame
// trigger and NO "traversal finished" stop state. A frame-locked engine
// that stopped after one traversal left the FIFO dry the instant the pixel
// side switched from the test bars to the real picture, which is why the
// bars stayed on screen forever.
//
// Waiting for w_state == W_IDLE keeps hp_addr on wr_addr until the very
// last write burst of the upload has finished.
wire rd_active = display_mode && hp_init && (w_state == W_IDLE);

//----------------------------------------------------------------------
// READ-ENGINE ADDRESS COUNTER
//
// The engine free-runs once display mode is on: bursts start at rd_addr and
// walk the whole frame, wrapping back to word 0 at the end. It is throttled
// only by fifo_can_burst. The pixel side consumes exactly one frame worth of
// words per displayed frame, so in steady state the FIFO offset (the words
// already buffered) is periodic with the frame and the picture does not slide.
//----------------------------------------------------------------------
assign hp_rd_req = rd_active && !hp_busy && fifo_can_burst;

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        rd_addr <= 22'd0; rburst <= 13'd0;
    end else if (rd_active && hp_rd_done) begin
        if (rburst == BURSTS_FRAME - 13'd1) begin
            rburst  <= 13'd0;      // wrap: the picture keeps looping
            rd_addr <= 22'd0;
        end else begin
            rburst  <= rburst + 13'b1;
            rd_addr <= rd_addr + ADDR_STEP;
        end
    end
end

//----------------------------------------------------------------------
// Display-path diagnostics
//   px_alive      (clk_p): latches 1 once sys_resetn has released and
//                  clk_p is ticking - proves the pixel domain is alive.
//   px_frame_tog  (clk_p): flips at the end of every rendered frame, so a
//                  change between two consecutive status packets proves the
//                  pixel FSM keeps cycling frames (the stream is not stuck).
//                  It is only meaningful because the status-packet period is
//                  1.05 s = exactly 63 frames at 60.000 fps (an ODD number),
//                  so the bit is guaranteed to differ between packets. A
//                  plain 1.000 s period would alias (60 frames, even).
//   Both are 2-flop synced into hp_clkout.
//
// NOTE: fb_tready / enc_* MUST be declared here, BEFORE the pixel FSM that
// reads them. Gowin's parser does not hoist module-level declarations: a net
// first used above its declaration becomes an implicit undriven 1-bit wire
// (EX3638) while the explicit declaration creates a SECOND, disconnected net.
// fb_tready was read at the P_RUN advance gates long before its declaration
// near the encoder instance, which would leave the FSM pushing a pixel every
// cycle into svo_enc regardless of backpressure (pixel_fifo overruns -> the
// mixer drops everything -> out_fifo drains -> output stage freezes -> "no
// signal" while the pixel FSM happily keeps counting frames).
//----------------------------------------------------------------------
reg img_live;          // pixel-side source select (used by the diagnostics
                       // below, so it must be declared before them)
reg px_alive;
reg px_frame_tog;      // driven in the measurement block after the pixel FSM
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        px_alive <= 1'b0;
    end else begin
        px_alive <= 1'b1;
    end
end

wire fb_tready;
wire enc_tvalid, enc_tready;
wire [23:0] enc_tdata;
wire [3:0] enc_tuser;

// The measurements that actually feed the status packet are built further
// down, right after the pixel FSM (they need pstate/gx/gy/ph/ld in scope).

// HyperRAM address mux: writes before START, reads afterwards. While the
// write FSM is still draining its last burst hp_addr stays on wr_addr.
assign hp_addr = rd_active ? rd_addr : wr_addr;

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

    .rd_clk       (clk_p),
    .rd_rst_n     (sys_resetn),
    .rd_en        (fifo_re),
    .rd_data      (fifo_dout),
    .empty        (fifo_empty),
    .rd_has_word  (fifo_has_word),
    .rd_fill      (fifo_rd_fill)
);

//============================================================================
// Pixel streamer (clk_p): FIFO words -> 4-pixel groups -> SVO encoder
//   - start: APB START synced into clk_p (display_mode drives the read
//     engine, so no frame trigger is needed here)
//   - P_IDLE picks the source for the next frame and holds a black pixel
//   - P_RUN outputs 4 pixels per group while loading the next group in
//     parallel (ph0..ph2 issue reads, ph3 captures word 2 and swaps).
//   - all advances are gated by fb_tready and by data availability.
//============================================================================
reg        start_s0, start_s1;

// img_live is re-decided at EVERY frame start from the FIFO level (see
// P_IDLE). It is not sticky, so a transient starvation can only cost one
// frame of colour bars - the next frame retries by itself.
// test_pat = 1 -> colour bars, 0 -> real picture. img_live is re-decided once
// per frame in P_IDLE and is NOT sticky, so a transient dry FIFO can only cost
// one frame of bars and the next frame retries the real picture by itself.
wire       test_pat = TEST_PATTERN | ~img_live;

reg [1:0]  pstate;       // P_IDLE / P_RUN
reg [95:0] grp;          // current group (3 words = 3*4B = 4 RGB pixels)
reg [95:0] ngrp;         // next group being loaded

reg [7:0]  gx;           // 0..159 groups per line
reg [8:0]  gy;           // 0..479 lines
reg [2:0]  ph;           // output phase 0..3, 4 = wait at group boundary
reg [1:0]  ld;           // words already loaded into ngrp (0..3)
reg        cap_pending;  // a FIFO read was issued, dout valid next cycle

reg        fb_tvalid;
reg        fb_tuser;
reg [23:0] fb_tdata;

localparam P_IDLE  = 2'd0;
localparam P_RUN   = 2'd1;

//--------------------------------------------------------------------------
// TEST PATTERN (diagnostic, independent of memory path)
//   EXACTLY the content of flat_4col_640x480.rgb: four flat colour bands,
//   160 px wide each, in the same order. The generator never touches UART,
//   HyperRAM or the FIFO, so comparing power-on (this generator) against the
//   uploaded picture (full memory path) is an apples-to-apples test: same
//   colours, same video timing, same encoder, same TMDS.
//     screen keeps the band texture  -> fault is outside the memory/loader path
//     band texture disappears        -> fault is in the memory/loader path
//--------------------------------------------------------------------------
wire [9:0] test_x = {gx, ph[1:0]};            // 0..639 (10 bits!)
reg [23:0] test_rgb;
always @(*) begin
    if      (test_x < 10'd160) test_rgb = 24'hC85A00;  // blue    R0   G90  B200
    else if (test_x < 10'd320) test_rgb = 24'h005AC8;  // orange  R200 G90  B0
    else if (test_x < 10'd480) test_rgb = 24'h5AC800;  // green   R0   G200 B90
    else                       test_rgb = 24'h5A00C8;  // magenta R200 G0   B90
end

//--------------------------------------------------------------------------
// Pixel the memory path delivered for the current screen position: 3 words
// = 12 bytes = 4 RGB pixels. fb_tdata is {B,G,R}; each pixel needs its two
// outer bytes swapped (see the P_RUN pixel output).
//--------------------------------------------------------------------------
wire [23:0] real_px =
      (ph[1:0] == 2'd0) ? {grp[79:72], grp[87:80], grp[95:88]}
    : (ph[1:0] == 2'd1) ? {grp[55:48], grp[63:56], grp[71:64]}
    : (ph[1:0] == 2'd2) ? {grp[31:24], grp[39:32], grp[47:40]}
    :                     {grp[7:0],   grp[15:8],  grp[23:16]};

always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        start_s0 <= 1'b0; start_s1 <= 1'b0;
        img_live <= 1'b0;
        pstate <= P_IDLE;
        grp <= 96'b0; ngrp <= 96'b0;
        gx <= 8'd0; gy <= 9'd0; ph <= 3'd0;
        ld <= 2'd0; cap_pending <= 1'b0;
        fb_tvalid <= 1'b0; fb_tuser <= 1'b0; fb_tdata <= 24'b0;
        fifo_re <= 1'b0;
    end else begin
        start_s0 <= apb_start; start_s1 <= start_s0;

        // default: FIFO read strobe is a 1-cycle pulse
        fifo_re <= 1'b0;

        case (pstate)
            //--------------------------------------------------------------
            P_IDLE: begin
                // Keep the AXIS stream alive with a black pixel - never a
                // gap. svo_enc freezes its whole output (hsync/vsync
                // included) the moment the input stream stops, and a frozen
                // stream is exactly what the monitor shows as "no signal".
                fb_tvalid <= 1'b1;
                fb_tdata  <= 24'h000000;  // black
                fb_tuser  <= 1'b0;
                if (!display_mode) begin
                    // Nothing uploaded yet: play the colour bars. The read
                    // engine is inactive (rd_active = 0).
                    img_live <= 1'b0;
                    gx <= 8'd0; gy <= 9'd0; ph <= 3'd0;
                    ld <= 2'd0; cap_pending <= 1'b0;
                    pstate <= P_RUN;
                end else begin
                    // Upload finished: use the real picture for EVERY following
                    // frame. img_live is decided here and only here (from
                    // display_mode); it must NOT flip back to the bars when the
                    // FIFO level dips, because alternating bars/real frames is
                    // what made the picture flash and appear to slide.
                    //
                    // This state goes STRAIGHT to P_RUN: P_RUN's own loader fills
                    // the first group. Routing the entry through a priming state
                    // that waits for FIFO data (P_PRIME in v7/v14/v15, P_ALIGN in
                    // v17) came up black every single time - the FSM sat there
                    // emitting black with fb_tuser low, the encoder never saw a
                    // frame marker, its out_fifo drained and the output froze.
                    gx <= 8'd0; gy <= 9'd0; ph <= 3'd0;
                    ld <= 2'd0;
                    if (!img_live) begin
                        //------------------------------------------------------
                        // FIRST real frame: one-group PRE-ROLL.
                        //
                        // The group pipeline always swaps grp at the END of a
                        // group, so the words popped at a frame start cannot be
                        // seen until group 1. Every frame therefore came out
                        // shifted right by exactly one group = 4 px: the
                        // leftmost 4 px of every line showed the PREVIOUS
                        // line's last 4 px (the thin magenta strip on the flat
                        // 4-band test) and every band edge sat 4 px off. A
                        // uniform grey picture is invariant to that shift,
                        // which is exactly what the hardware showed (no strip,
                        // no dots) - proving the fault is positional, not data.
                        //
                        // Fix: make the frame's FIRST group actually be image
                        // group 0 by popping one group HERE and installing it
                        // in grp before P_RUN. This is bounded (3 words), it
                        // does NOT stop the read engine and does NOT drain the
                        // FIFO - v14/v17 went black doing either of those.
                        // Afterwards the steady state is already consistent:
                        // during each group the loader loads the NEXT group, so
                        // the frame-end swap leaves image group 0 in grp for the
                        // following frame and no extra word is popped again.
                        // The 3 words spent here are a one-time cost (this frame
                        // has no predecessor to pre-load it), so the FIFO offset
                        // never drifts and the picture does not roll.
                        //
                        // ld/cap_pending/ngrp run the SAME micro-sequence as the
                        // P_RUN loader, so the datapath muxing is shared.
                        //------------------------------------------------------
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
                            // pre-roll complete: install it as group 0, arm the
                            // look-ahead for group 1 and start the frame
                            grp         <= ngrp;
                            ld          <= 2'd0;
                            img_live    <= 1'b1;
                            if (fifo_has_word) begin
                                fifo_re     <= 1'b1;
                                cap_pending <= 1'b1;
                            end else begin
                                cap_pending <= 1'b0;
                            end
                            pstate      <= P_RUN;
                        end
                    end else begin
                        // Later frames: grp already holds image group 0, left
                        // there by the frame-end swap of the previous frame.
                        // Only the first group's look-ahead needs arming.
                        if (!cap_pending && fifo_has_word) begin
                            fifo_re     <= 1'b1;
                            cap_pending <= 1'b1;
                        end else begin
                            cap_pending <= 1'b0;
                        end
                        pstate <= P_RUN;
                    end
                end
            end

            //--------------------------------------------------------------
            // Output the 4 pixels of grp (ph 0..3) while loading the next
            // group ngrp with an independent 3-word micro-sequence. The two
            // never interfere: pixel output needs no FIFO access, the loader
            // owns the read port. If loading lags (bandwidth should make
            // this impossible, but stay correct), ph reaches 4 and tvalid
            // drops until ngrp is complete - an AXIS gap, never a duplicated
            // pixel.
            //--------------------------------------------------------------
            P_RUN: begin
                if (test_pat) begin
                    //------------------------------------------------------
                    // Diagnostic path: one pixel per cycle, no FIFO/RAM.
                    //------------------------------------------------------
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
                                else begin
                                    gy <= 9'd0;
                                    // back to P_IDLE so the next frame picks
                                    // up the real picture if it is available
                                    pstate <= P_IDLE;
                                end
                            end
                        end
                    end
                end else begin
                //-------- next-group loader (runs every cycle) -------------
                if (ld != 2'd3) begin
                    if (cap_pending) begin
                        // word from the previous cycle's read is on dout
                        case (ld)
                            2'd0: ngrp[95:64] <= fifo_dout;
                            2'd1: ngrp[63:32] <= fifo_dout;
                            2'd2: ngrp[31:0] <= fifo_dout;
                        endcase
                        ld <= ld + 2'b1;
                        // chain the next read immediately (read port is free
                        // again this cycle) while more words are needed
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
                // 3 words = 12 bytes = 4 RGB pixels. fb_tdata is {B,G,R}, the
                // incoming word stream is {R,G,B,R|G,B,R,G,B|...} MSB-first, so
                // each pixel needs its two outer bytes swapped.
                if (ph < 3'd4) begin
                    fb_tvalid <= 1'b1;
                    fb_tdata <= real_px;
                    fb_tuser  <= (gx == 8'd0 && gy == 9'd0 && ph == 3'd0);
                end

                if (fb_tready) begin
                    if (ph < 3'd3) begin
                        ph <= ph + 3'b1;
                    end else begin
                        // ph == 3, last pixel of the group. The frame cadence
                        // (gx/gy sweep + frame-start marker) advances
                        // UNCONDITIONALLY: if it depended on FIFO availability a
                        // dry FIFO would freeze the FSM, gx/gy would stop
                        // sweeping, no fb_tuser would ever be produced again and
                        // svo_enc's mixer would drop pixels forever -> the
                        // output stage stalls -> the monitor reports
                        // "no signal" (red LED) even though the TMDS clock lane
                        // is still alive.
                        ph        <= 3'd0;
                        fb_tvalid <= 1'b1;
                        if (ld == 2'd3) begin
                            // complete group from the FIFO
                            grp <= ngrp;
                            ld          <= 2'd0;
                            cap_pending <= 1'b0;
                            // restart the loader immediately: the read port is
                            // free again this cycle and the pixel side eats
                            // exactly 1 word per pixel clock, so any bubble here
                            // makes the loader slower than the encoder. At the
                            // very end of the frame NO look-ahead read is
                            // started: the display would eat that word but the
                            // engine would never produce it, and that single
                            // lost word per frame is exactly what rolled the
                            // picture (4 bytes = 1.33 px) and rotated the
                            // colour cast.
                            if (gx != GROUPS_LINE - 1) begin
                                gx <= gx + 8'b1;
                                if (fifo_has_word) begin
                                    fifo_re     <= 1'b1;
                                    cap_pending <= 1'b1;
                                end
                            end else begin
                                gx <= 8'd0;
                                if (gy != LINE_LAST) begin
                                    gy <= gy + 9'b1;
                                    if (fifo_has_word) begin
                                        fifo_re     <= 1'b1;
                                        cap_pending <= 1'b1;
                                    end
                                end else begin
                                    // End of frame: next frame picks the source
                                    // in P_IDLE and enters P_RUN directly.
                                    gy     <= 9'd0;
                                    pstate <= P_IDLE;
                                end
                            end
                        end else begin
                            // TRANSIENT UNDERRUN - CONCEAL, NEVER FLASH.
                            // Fewer than 3 words were available when this group
                            // had to be emitted. Do NOT paint a marker colour
                            // (this used to put a 4-pixel WHITE block on screen
                            // = the scattered coloured dots) and do NOT clear
                            // ld / cap_pending: the loader simply carries on and
                            // finishes the group it is already assembling, so no
                            // word is ever discarded and the word stream stays
                            // aligned. The only cost is a 4-pixel repeat of the
                            // previous group, which is invisible in flat areas.
                            if (gx != GROUPS_LINE - 1) begin
                                gx <= gx + 8'b1;
                            end else begin
                                gx <= 8'd0;
                                if (gy != LINE_LAST) begin
                                    gy <= gy + 9'b1;
                                end else begin
                                    gy     <= 9'd0;
                                    pstate <= P_IDLE;
                                end
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
// DISPLAY / STORAGE MEASUREMENTS FOR THE STATUS PACKET
//   Built here (not up with the other diagnostics) because they read the
//   pixel FSM's own state, which is only declared above this point.
//
//   px_frame_tog  (clk_p): flips on every COMPLETED frame. The status packet
//                 period is 1.05 s = exactly 63 frames at 60.000 fps (ODD),
//                 so two consecutive packets are guaranteed to show different
//                 bits while the pixel FSM keeps rendering. A stuck bit means
//                 the FSM stopped cycling frames (e.g. the real-image loader
//                 is wedged at ph==4). This replaced a 19-bit activity
//                 counter, which cost 20 FFs and triggered PR0003.
//   real_px_nz    (clk_p, sticky): a NON-ZERO pixel was handed to the
//                 encoder, i.e. the HyperRAM read-back really carries image
//                 data. If this stays 0 the whole picture is already black
//                 before the encoder, and the display chain is not at fault.
//   enc_vs_tog    (clk_p): toggles on every vsync edge SEEN AT THE ENCODER
//                 OUTPUT PORT. This is the one bit that proves the TMDS
//                 serializer stream is alive. If it differs between
//                 consecutive packets the output stage keeps emitting whole
//                 frames; if it is frozen the output stage stalled (out_fifo
//                 drained) and the monitor loses sync -> "black / no signal"
//                 even though every other indicator reads green.
//   starved       (clk_p, sticky): the real branch once ran the ph==4 fill
//                 state, i.e. the pixel engine ran out of FIFO words. That is
//                 the mechanism that drains out_fifo and freezes the encoder.
//   wr_nz_seen    (hp_clkout, sticky): a NON-ZERO word reached the HyperRAM
//                 IP write port. Together with real_px_nz it separates
//                 "the host sent zeros" (wr_nz_seen = 0) from "the store /
//                 load path loses the data" (wr_nz_seen = 1, real_px_nz = 0).
//============================================================================
wire px_frame_end = (pstate == P_RUN) && fb_tready && (ph == 3'd3) &&
                    (gx == GROUPS_LINE - 1) && (gy == LINE_LAST) &&
                    (test_pat | (ld == 2'd3));

reg        real_px_nz;
reg        starved;
reg        px_frame_tog;
reg        enc_vs_r, enc_vs_tog;
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        real_px_nz   <= 1'b0;
        starved      <= 1'b0;
        px_frame_tog <= 1'b0;
        enc_vs_r     <= 1'b0;
        enc_vs_tog   <= 1'b0;
    end else begin
        // One flip per COMPLETED frame (either source). See the note above:
        // the 1.05 s packet period makes this bit differ between consecutive
        // packets as long as the pixel FSM really keeps rendering frames.
        if (px_frame_end) px_frame_tog <= ~px_frame_tog;

        // The real branch ran the ph==4 fill state => out of FIFO words.
        if (!test_pat && (pstate == P_RUN) && (ph == 3'd4) && (ld != 2'd3))
            starved <= 1'b1;

        // A NON-ZERO pixel reached the encoder in the real branch (sticky).
        // If this stays 0 the picture is already black BEFORE the encoder,
        // i.e. the fault is in the store/load path - the video chain itself
        // is proven healthy by the colour bars.
        if (!test_pat && (pstate == P_RUN) && (ph < 3'd4) &&
            (fb_tdata != 24'd0))
            real_px_nz <= 1'b1;

        // vsync edges at the encoder OUTPUT (tuser[2] = is_vsync).
        enc_vs_r <= enc_tvalid & enc_tuser[2];
        if ((enc_tvalid & enc_tuser[2]) & ~enc_vs_r)
            enc_vs_tog <= ~enc_vs_tog;
    end
end

reg wr_nz_seen;
always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn)
        wr_nz_seen <= 1'b0;
    else if ((w_state != W_IDLE) && (hp_wr_data != 32'd0))
        wr_nz_seen <= 1'b1;
end

reg px_alive_cc, img_live_cc;
reg px_frame_tog_cc, real_px_nz_cc, enc_vs_tog_cc, starved_cc;
always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        px_alive_cc     <= 1'b0;
        img_live_cc     <= 1'b0;
        px_frame_tog_cc <= 1'b0;
        real_px_nz_cc   <= 1'b0;
        enc_vs_tog_cc   <= 1'b0;
        starved_cc      <= 1'b0;
    end else begin
        px_alive_cc     <= px_alive;
        img_live_cc     <= img_live;
        px_frame_tog_cc <= px_frame_tog;
        real_px_nz_cc   <= real_px_nz;
        enc_vs_tog_cc   <= enc_vs_tog;
        starved_cc      <= starved;
    end
end

// Status byte carried in the diagnostic packet (hp_clkout domain)
//   bit7 img_live         pixel side selected the real picture
//   bit6 px_frame_tog     differs between consecutive packets (63 frames/1.05s)
//   bit5 real_px_nz       a NON-ZERO pixel reached the encoder
//   bit4 enc_vs_tog       TMDS output stage still emitting whole frames
//   bit3 wr_nz_seen       a NON-ZERO word reached the HyperRAM write port
//   bit2 starved          the real branch once ran out of FIFO words
//   bit1 rd_active        read engine currently enabled (display_mode+W_IDLE)
//   bit0 px_alive         clk_p domain released from reset
assign hp_rd_status = {img_live_cc, px_frame_tog_cc, real_px_nz_cc,
                       enc_vs_tog_cc, wr_nz_seen, starved_cc,
                       rd_active, px_alive_cc};

//============================================================================
// TMDS encode (SVO stack, input = BGR)
//============================================================================
// (fb_tready / enc_* are declared above, next to the diagnostics that use
//  them - see the NOTE there.)
svo_enc #( `SVO_PASS_PARAMS ) enc_inst (
    .clk(clk_p),
    .resetn(sys_resetn),
    .in_axis_tvalid(fb_tvalid),
    .in_axis_tready(fb_tready),
    .in_axis_tdata(fb_tdata),
    .in_axis_tuser(fb_tuser),
    .out_axis_tvalid(enc_tvalid),
    .out_axis_tready(enc_tready),
    .out_axis_tdata(enc_tdata),
    .out_axis_tuser(enc_tuser)
);
assign enc_tready = 1'b1;

wire [2:0] tmds_d;
wire [2:0] tmds_d0, tmds_d1, tmds_d2, tmds_d3, tmds_d4;
wire [2:0] tmds_d5, tmds_d6, tmds_d7, tmds_d8, tmds_d9;

svo_tmds tmds_0 (
    .clk(clk_p), .resetn(sys_resetn),
    .de(!enc_tuser[3]), .ctrl(enc_tuser[2:1]), .din(enc_tdata[23:16]),
    .dout({tmds_d9[0], tmds_d8[0], tmds_d7[0], tmds_d6[0], tmds_d5[0],
           tmds_d4[0], tmds_d3[0], tmds_d2[0], tmds_d1[0], tmds_d0[0]})
);
svo_tmds tmds_1 (
    .clk(clk_p), .resetn(sys_resetn),
    .de(!enc_tuser[3]), .ctrl(2'b0), .din(enc_tdata[15:8]),
    .dout({tmds_d9[1], tmds_d8[1], tmds_d7[1], tmds_d6[1], tmds_d5[1],
           tmds_d4[1], tmds_d3[1], tmds_d2[1], tmds_d1[1], tmds_d0[1]})
);
svo_tmds tmds_2 (
    .clk(clk_p), .resetn(sys_resetn),
    .de(!enc_tuser[3]), .ctrl(2'b0), .din(enc_tdata[7:0]),
    .dout({tmds_d9[2], tmds_d8[2], tmds_d7[2], tmds_d6[2], tmds_d5[2],
           tmds_d4[2], tmds_d3[2], tmds_d2[2], tmds_d1[2], tmds_d0[2]})
);

OSER10 tmds_serdes [2:0] (
    .Q(tmds_d),
    .D0(tmds_d0), .D1(tmds_d1), .D2(tmds_d2), .D3(tmds_d3), .D4(tmds_d4),
    .D5(tmds_d5), .D6(tmds_d6), .D7(tmds_d7), .D8(tmds_d8), .D9(tmds_d9),
    .PCLK(clk_p), .FCLK(clk_p5), .RESET(~sys_resetn)
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
    .sys_reset_n    (resetn),
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
    .busy           (hp_busy),
    .init_calib     (hp_init),
    .clk_out        (hp_clkout),
    .O_hpram_ck     (O_hpram_ck),
    .O_hpram_ck_n   (O_hpram_ck_n),
    .IO_hpram_rwds  (IO_hpram_rwds),
    .IO_hpram_dq    (IO_hpram_dq),
    .O_hpram_cs_n   (O_hpram_cs_n),
    .O_hpram_reset_n(O_hpram_reset_n)
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
