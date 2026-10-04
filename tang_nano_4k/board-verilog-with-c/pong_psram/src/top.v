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
    inout  [7:0] hpram_dq,
    inout        hpram_rwds,
    output       hpram_ck,
    output       hpram_cs_n,
    output       hpram_reset_n,

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

localparam LINE_WORDS    = 480;     // 640 px * 3 B / 4 B
localparam LINE_LAST     = 479;
localparam GROUPS_LINE   = 160;     // 640 px / 4
localparam BURST_WORDS   = 32;      // 128-byte burst = 32 words
localparam BURSTS_FRAME  = 7200;    // 230400 frame words / 32
localparam [21:0] ADDR_STEP = 22'd64; // 128 bytes in 2-byte addr units

// DIAGNOSTIC: when 1, the pixel FSM streams an internally generated test
// pattern (8 BGR vertical bars + 32px black grid + white border) and never
// touches UART/HyperRAM/FIFO. Set back to 0 for normal image display.
localparam TEST_PATTERN = 1'b1;

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
        st_s0 <= 1'b0;  st_s1 <= 1'b0;
        pack_cnt <= 5'd0; ridx <= 5'd0;
        wr_addr <= 22'd0; w_state <= W_IDLE; w_to <= 7'd0;
        display_mode <= 1'b0; ack_toggle <= 1'b0;
    end else begin
        // 2-flop sync of APB2 bridge outputs
        wd_s0 <= apb_word; wd_s1 <= wd_s0;
        wr_s0 <= apb_req;  wr_s1 <= wr_s0;  wr_prev <= wr_s1;
        st_s0 <= apb_start; st_s1 <= st_s0;

        // latch start (display mode) once CTRL is written
        if (st_s1) display_mode <= 1'b1;

        // The case always runs so a burst already in W_ISSUE/W_STREAM can
        // finish after display_mode is set; only W_IDLE acceptance is gated.
        case (w_state)
                W_IDLE: begin
                    if (!display_mode && (wr_s1 ^ wr_prev)) begin
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
// Frame start is a toggle from the pixel side (also retoggles per frame).
//============================================================================
reg [21:0] rd_addr;
reg [12:0] rburst;       // 0..7199
reg        rd_run;
reg        rd_v_seen, rd_d_seen, fr_seen;   // read-path diagnostics (sticky)
reg        fr_s0, fr_s1, fr_prev;

wire fifo_full;
wire fifo_can_burst;
wire fifo_empty;
wire fifo_has_word;
wire [7:0] fifo_rd_fill;
wire [31:0] fifo_dout;
reg        fifo_re;      // read enable in clk_p domain

assign hp_rd_req = rd_run && !hp_busy && fifo_can_burst;

always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        rd_addr <= 22'd0; rburst <= 13'd0; rd_run <= 1'b0;
        fr_s0 <= 1'b0; fr_s1 <= 1'b0; fr_prev <= 1'b0;
        rd_v_seen <= 1'b0; rd_d_seen <= 1'b0; fr_seen <= 1'b0;
    end else begin
        fr_s0 <= frame_req_tog; fr_s1 <= fr_s0; fr_prev <= fr_s1;

        if (fr_s1 ^ fr_prev) begin
            // (re)start a frame
            rd_addr <= 22'd0;
            rburst  <= 13'd0;
            rd_run  <= 1'b1;
            fr_seen <= 1'b1;
        end else if (rd_run && hp_rd_done) begin
            if (rburst == BURSTS_FRAME - 13'd1) begin
                rd_run <= 1'b0;
            end else begin
                rburst  <= rburst + 13'b1;
                rd_addr <= rd_addr + ADDR_STEP;
            end
        end

        // read-path diagnostics
        if (hp_rd_done)  rd_d_seen <= 1'b1;
        if (hp_rd_valid) rd_v_seen <= 1'b1;
    end
end

//----------------------------------------------------------------------
// Display-path diagnostics
//   px_alive      (clk_p): latches 1 once sys_resetn has released and
//                  clk_p is ticking - proves the pixel domain is alive.
//   px_start_seen (clk_p): latches 1 once the START level reached the
//                  pixel FSM (start_s1).
//   Both are sticky on purpose, then 2-flop synced into hp_clkout.
//----------------------------------------------------------------------
reg px_alive, px_start_seen;
always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        px_alive      <= 1'b0;
        px_start_seen <= 1'b0;
    end else begin
        px_alive      <= 1'b1;
        if (start_s1) px_start_seen <= 1'b1;
    end
end

reg px_alive_cc, px_start_cc;
always @(posedge hp_clkout or negedge global_resetn) begin
    if (!global_resetn) begin
        px_alive_cc <= 1'b0; px_start_cc <= 1'b0;
    end else begin
        px_alive_cc <= px_alive;
        px_start_cc <= px_start_seen;
    end
end

// Read-path status for the diagnostic packet (hp_clkout domain)
// bit7 fr_seen | 6 rd_d_seen | 5 rd_v_seen | 4 rd_run
// bit3 fifo_can_burst | 2 fifo_full | 1 px_start_seen | 0 px_alive
assign hp_rd_status = {fr_seen, rd_d_seen, rd_v_seen,
                       rd_run, fifo_can_burst, fifo_full,
                       px_start_cc, px_alive_cc};

// HyperRAM address mux: writes before START, reads afterwards
assign hp_addr = display_mode ? rd_addr : wr_addr;

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
//   - start: APB START synced into clk_p, toggles frame_req_tog once;
//     the toggle is retoggled at every frame end so the static image loops
//   - P_PRIME loads group 0 (3 words, 1-cycle SDPB latency respected)
//   - P_RUN outputs 4 pixels per group while loading the next group in
//     parallel (ph0..ph2 issue reads, ph3 captures word 2 and swaps).
//   - all advances are gated by fb_tready and by data availability.
//============================================================================
reg        start_s0, start_s1, started;
reg        frame_req_tog;

reg [1:0]  pstate;       // P_IDLE / P_PRIME / P_RUN
reg [1:0]  pc;           // prime counter
reg [95:0] grp;          // current group (3 words = 4 pixels)
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
localparam P_PRIME = 2'd1;
localparam P_RUN   = 2'd2;

//--------------------------------------------------------------------------
// TEST PATTERN (diagnostic, independent of memory path)
//   8 vertical BGR bars, each 80 px wide, crossed by a 32-px black grid and
//   a 4-px white border. Any duplicated/dropped pixel shows up as uneven bar
//   widths / broken grid; any lane swap shows up as wrong bar colours.
//--------------------------------------------------------------------------
wire [8:0] test_x   = {gx, ph[1:0]};          // 0..639
wire [2:0] test_bar = test_x[8:6];            // 8 bars
reg [23:0] test_rgb;
always @(*) begin
    case (test_bar)
        3'd0: test_rgb = 24'hFFFFFF;          // white  {B,G,R}
        3'd1: test_rgb = 24'h00FFFF;          // yellow
        3'd2: test_rgb = 24'hFFFF00;          // cyan
        3'd3: test_rgb = 24'h00FF00;          // green
        3'd4: test_rgb = 24'hFF00FF;          // magenta
        3'd5: test_rgb = 24'h0000FF;          // red
        3'd6: test_rgb = 24'hFF0000;          // blue
        default: test_rgb = 24'h000000;       // black
    endcase
    if (test_x[4:0] == 5'd0 || gy[4:0] == 5'd0)
        test_rgb = 24'h000000;                // fine grid
    if (test_x < 9'd4 || test_x > 9'd635 || gy < 9'd4 || gy > 9'd475)
        test_rgb = 24'hFFFFFF;                // outer border
end

always @(posedge clk_p or negedge sys_resetn) begin
    if (!sys_resetn) begin
        start_s0 <= 1'b0; start_s1 <= 1'b0; started <= 1'b0;
        frame_req_tog <= 1'b0;
        pstate <= P_IDLE; pc <= 2'd0;
        grp <= 96'b0; ngrp <= 96'b0;
        gx <= 8'd0; gy <= 9'd0; ph <= 3'd0;
        ld <= 2'd0; cap_pending <= 1'b0;
        fb_tvalid <= 1'b0; fb_tuser <= 1'b0; fb_tdata <= 24'b0;
        fifo_re <= 1'b0;
    end else begin
        start_s0 <= apb_start; start_s1 <= start_s0;

        // first START: begin frame loop (read engine starts on this toggle)
        if ((start_s1 || TEST_PATTERN) && !started) begin
            started       <= 1'b1;
            if (!TEST_PATTERN)
                frame_req_tog <= ~frame_req_tog;
        end

        // default: FIFO read strobe is a 1-cycle pulse
        fifo_re <= 1'b0;

        case (pstate)
            //--------------------------------------------------------------
            P_IDLE: begin
                fb_tvalid <= 1'b0;
                // TEST_PATTERN starts immediately; normal path waits for the
                // read engine to prefetch 64 words (~3.4 us of video) so an
                // inter-burst latency gap cannot starve the active line.
                if (started && (TEST_PATTERN || fifo_rd_fill >= 8'd64)) begin
                    gx <= 8'd0; gy <= 9'd0; pc <= 2'd0;
                    ph <= 3'd0; ld <= 2'd0; cap_pending <= 1'b0;
                    fb_tvalid <= TEST_PATTERN;
                    pstate <= TEST_PATTERN ? P_RUN : P_PRIME;
                end
            end

            //--------------------------------------------------------------
            // Prime group 0. FIFO read latency = 1: an address in cycle T
            // yields fifo_dout in T+1; wait for data availability before
            // each advance so the stream never mis-validates.
            //--------------------------------------------------------------
            P_PRIME: begin
                fb_tvalid <= 1'b0;
                case (pc)
                    2'd0: begin
                        if (fifo_has_word) begin
                            fifo_re <= 1'b1;   // word 0 -> dout next cycle
                            pc <= 2'd1;
                        end
                    end
                    2'd1: begin
                        grp[95:64] <= fifo_dout;
                        if (fifo_has_word) begin
                            fifo_re <= 1'b1;
                            pc <= 2'd2;
                        end
                    end
                    2'd2: begin
                        grp[63:32] <= fifo_dout;
                        if (fifo_has_word) begin
                            fifo_re <= 1'b1;
                            pc <= 2'd3;
                        end
                    end
                    default: begin
                        grp[31:0]  <= fifo_dout;
                        ph         <= 3'd0;
                        ld         <= 2'd0;
                        cap_pending <= 1'b0;
                        fb_tvalid  <= 1'b1;
                        pstate     <= P_RUN;
                    end
                endcase
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
                if (TEST_PATTERN) begin
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
                                else
                                    gy <= 9'd0;   // loop, stay in P_RUN
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
                if (ph < 3'd4) begin
                    fb_tvalid <= 1'b1;
                    case (ph[1:0])
                        2'd0: fb_tdata <= {grp[79:72], grp[87:80], grp[95:88]};
                        2'd1: fb_tdata <= {grp[55:48], grp[63:56], grp[71:64]};
                        2'd2: fb_tdata <= {grp[31:24], grp[39:32], grp[47:40]};
                        default: fb_tdata <= {grp[7:0],  grp[15:8],  grp[23:16]};
                    endcase
                    fb_tuser <= (gx == 8'd0 && gy == 9'd0 && ph == 3'd0);
                end

                if (fb_tready) begin
                    if (ph < 3'd3) begin
                        ph <= ph + 3'b1;
                    end else if (ph == 3'd3) begin
                        // last pixel of the group: swap only if ngrp ready
                        if (ld == 2'd3) begin
                            grp <= ngrp;
                            ld  <= 2'd0;
                            ph  <= 3'd0;
                            // advance group / line / frame counters
                            if (gx != GROUPS_LINE - 1) begin
                                gx <= gx + 8'b1;
                            end else begin
                                gx <= 8'd0;
                                if (gy != LINE_LAST) begin
                                    gy <= gy + 9'b1;
                                end else begin
                                    gy            <= 9'd0;
                                    frame_req_tog <= ~frame_req_tog;
                                    fb_tvalid     <= 1'b0;
                                    pstate        <= P_IDLE;
                                end
                            end
                        end else begin
                            ph <= 3'd4;       // wait, keep last pixel valid...
                            fb_tvalid <= 1'b0; // ...but not re-issued
                        end
                    end else begin
                        // ph == 4: idle gap until the next group is loaded
                        if (ld == 2'd3) begin
                            grp       <= ngrp;
                            ld        <= 2'd0;
                            ph        <= 3'd0;
                            fb_tvalid <= 1'b1;
                            if (gx != GROUPS_LINE - 1) begin
                                gx <= gx + 8'b1;
                            end else begin
                                gx <= 8'd0;
                                if (gy != LINE_LAST) begin
                                    gy <= gy + 9'b1;
                                end else begin
                                    gy            <= 9'd0;
                                    frame_req_tog <= ~frame_req_tog;
                                    fb_tvalid     <= 1'b0;
                                    pstate        <= P_IDLE;
                                end
                            end
                        end else begin
                            fb_tvalid <= 1'b0;
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
wire fb_tready;
wire enc_tvalid, enc_tready;
wire [SVO_BITS_PER_PIXEL-1:0] enc_tdata;
wire [3:0] enc_tuser;

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
wire [0:0] hp_ck, hp_cs_n, hp_reset_n;

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
    .O_hpram_ck     (hp_ck),
    .IO_hpram_rwds  (hpram_rwds),
    .IO_hpram_dq    (hpram_dq),
    .O_hpram_cs_n   (hp_cs_n),
    .O_hpram_reset_n(hp_reset_n)
);

assign hpram_ck      = hp_ck[0];
assign hpram_cs_n    = hp_cs_n[0];
assign hpram_reset_n = hp_reset_n[0];

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
