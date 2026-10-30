//============================================================================
// ASYNC_FIFO - 512 x 32-bit dual-clock FIFO for the HyperRAM video stream
//============================================================================
//
// Write side runs in the HyperRAM clk_out domain (31.5 MHz): read bursts
// dump 32 words here as rd_data_valid pulses arrive.
// Read side runs in the pixel clock domain (25.2 MHz): the pixel streamer
// consumes words (3 words -> 4 pixels).
//
// Storage is ONE explicit SDPB block (the same primitive/pinout proven in
// the old line_buffer, including the two independent port clocks). All
// empty/full logic is fabric: 10-bit pointers (9 address bits + 1 wrap bit)
// with Gray-code 2-flop crossing.
//
// Read port has 1-cycle latency (SDPB READ_MODE=0 bypass): assert rd_en in
// cycle T with rbin pointing at the wanted slot, rd_data holds that word in
// T+1. rd_en is ignored while empty.
//
// wr_can_burst is the writer-side gate for a 32-word HyperRAM burst: it is
// high while the fill level is <= 448 words (64 free slots of the 512). The
// pixel side waits for rd_fill >= 64 before starting a frame, so the FIFO
// stays near full (~450 words / ~24 us of elasticity) and the IP
// read-latency/refresh gap between bursts can never starve the active
// display area.
//
//============================================================================
`timescale 1ns / 1ps

module async_fifo (
    input  wire        wr_clk,        // write clock (hp_clkout, 31.5 MHz)
    input  wire        wr_rst_n,      // write-domain async reset (active low)
    input  wire        wr_en,         // write strobe (ignored when full)
    input  wire [31:0] wr_data,
    output wire        full,          // write-domain full
    output wire        wr_can_burst,  // write-domain: fill level <= 32 words
    output wire [9:0]  wr_fill,       // write-domain fill level (synced rptr)

    input  wire        rd_clk,        // read clock (clk_p, 25.2 MHz)
    input  wire        rd_rst_n,      // read-domain async reset (active low)
    input  wire        rd_en,         // read advance (ignored when empty)
    output wire [31:0] rd_data,       // 1-cycle-latency read data
    output wire        empty,         // read-domain empty
    output wire        rd_has_word,   // read-domain: at least 1 word available
    output wire [9:0]  rd_fill        // read-domain fill level (synced wptr)
);

    localparam AW = 9;  // 512 slots (the SDPB is 32b x 512: no extra block)
    localparam PW = AW + 1;  // pointer width incl. wrap bit

    //----------------------------------------------------------------------
    // Binary + Gray pointers
    //----------------------------------------------------------------------
    reg  [PW-1:0] wbin, wgray;
    reg  [PW-1:0] rbin, rgray;

    // synchronized pointers
    reg  [PW-1:0] wg_s0, wg_s1;   // wgray -> rd domain
    reg  [PW-1:0] rg_s0, rg_s1;   // rgray -> wr domain

    wire [PW-1:0] wbin_next  = wbin  + (wr_en && !full  ? 1'b1 : 1'b0);
    wire [PW-1:0] wgray_next = (wbin_next >> 1) ^ wbin_next;
    wire [PW-1:0] rbin_next  = rbin  + (rd_en && !empty ? 1'b1 : 1'b0);
    wire [PW-1:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    // write pointer
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin  <= 0;
            wgray <= 0;
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
        end
    end

    // read pointer
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rbin  <= 0;
            rgray <= 0;
        end else begin
            rbin  <= rbin_next;
            rgray <= rgray_next;
        end
    end

    // 2-flop synchronizers
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rg_s0 <= 0;
            rg_s1 <= 0;
        end else begin
            rg_s0 <= rgray;
            rg_s1 <= rg_s0;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wg_s0 <= 0;
            wg_s1 <= 0;
        end else begin
            wg_s0 <= wgray;
            wg_s1 <= wg_s0;
        end
    end

    // full: top 2 bits differ, rest equal (classic async FIFO)
    assign full = (wgray[PW-1]    != rg_s1[PW-1]) &&
                  (wgray[PW-2]    != rg_s1[PW-2]) &&
                  (wgray[PW-3:0] == rg_s1[PW-3:0]);

    // empty (reader view): pointers identical
    assign empty = (rgray == wg_s1);
    assign rd_has_word = !empty;

    // Reader-side fill level (synced write pointer, Gray -> binary).
    // Slightly stale (writer counted fewer pushes) -> under-estimate, safe
    // for the "prefill enough before display starts" gate.
    integer j;
    reg [PW-1:0] wbin_from_g;
    always @(*) begin
        wbin_from_g[PW-1] = wg_s1[PW-1];
        for (j = PW-2; j >= 0; j = j - 1)
            wbin_from_g[j] = wbin_from_g[j+1] ^ wg_s1[j];
    end

    assign rd_fill = wbin_from_g - rbin;

    //----------------------------------------------------------------------
    // Writer-side fill level via synced read pointer (Gray -> binary),
    // used to gate the next 32-word HyperRAM burst. The synced read pointer
    // is always slightly stale (reader counted fewer pops), so the computed
    // level is an over-estimate: the gate is conservative (bursts start a
    // little later, never overflow).
    //----------------------------------------------------------------------
    integer i;
    reg [PW-1:0] rbin_from_g;
    always @(*) begin
        rbin_from_g[PW-1] = rg_s1[PW-1];
        for (i = PW-2; i >= 0; i = i - 1)
            rbin_from_g[i] = rbin_from_g[i+1] ^ rg_s1[i];
    end

    wire [PW-1:0] fill_level = wbin - rbin_from_g;
    // Gate a 32-word burst while at least 64 slots are free (fill <= 448 of
    // 512). Keeps the FIFO near-full in steady state (~450 words = ~24 us of
    // pixel elasticity) so a HyperRAM read stall - the controller itself
    // allows up to RD_TIMEOUT=400 cycles (~12.7 us) before it pads a burst
    // with zeros - is absorbed instead of starving the active display area.
    // The old 128-word FIFO only held ~5 us, far below that timeout, so any
    // real read stall painted black groups -> flicker / stripes.
    assign wr_can_burst = (fill_level <= 10'd448);

    // Same level exported to top.v's write-window scheduler. Slight
    // over-estimate (the synced read pointer is stale -> the reader looks
    // less advanced), which only makes the "enough elasticity to take the
    // bus for a write" test marginally optimistic (~2 words, negligible).
    assign wr_fill = fill_level;

    //----------------------------------------------------------------------
    // Storage: one SDPB, 32-bit x 512 (ALL 512 slots used).
    //   ADA/ADB are 14 bits wide: ADA[13:5] = 9-bit slot, ADA[4] = 0,
    //   ADA[3:0] = byte enables; ADB[13:5] = 9-bit slot, ADB[4:0] = 0.
    //   Slot = pointer value, so the FIFO really is 512 words deep.
    //
    // ADB MUST BE rbin_next, NOT rbin. The SDPB output is registered
    // (READ_MODE=0): DO(T+1) = mem[ADB(T)], while rbin only advances one
    // cycle AFTER rd_en is seen. The pixel-side loader asserts rd_en in
    // cycle T and captures fifo_dout in T+1 with the SAME one-cycle
    // register delay, so addressing with the CURRENT pointer compares the
    // pointer of a cycle ago against data one cycle old - the pipeline
    // cancels and every 3-word group comes out as mem[R],mem[R],mem[R+1]
    // instead of mem[R],mem[R+1],mem[R+2]. The pixel side then sees its
    // first word repeated and the rest shifted by one word (4 bytes), i.e.
    // a scrambling that repeats every 3 words = 12 bytes = 4 PIXELS: on
    // screen that is exactly the "fine vertical stripes inside every
    // 128-byte block / electric-interference" look (measured 2026-10-02:
    // the 15 solid block-colour bars all came out striped, not solid).
    // Addressing with rbin_next advances with the strobe, so the register
    // delay is cancelled and the captured sequence is W0,W1,W2 ...
    // This is the same fix the known-good HyperRAM->HDMI reference carries.
    //----------------------------------------------------------------------
    SDPB #(
        .READ_MODE  (1'b0),      // bypass: 1-cycle read latency
        .BIT_WIDTH_0(32),
        .BIT_WIDTH_1(32),
        .RESET_MODE ("SYNC")
    ) u_fifo_ram (
        .DI      (wr_data),
        .ADA     ({wbin[AW-1:0], 1'b0, 4'b1111}),
        .CLKA    (wr_clk),
        .CEA     (wr_en && !full),
        .BLKSELA (3'b000),
        .RESETA  (1'b0),
        .DO      (rd_data),
        .ADB     ({rbin_next[AW-1:0], 5'b00000}),
        .CLKB    (rd_clk),
        .CEB     (1'b1),
        .OCE     (1'b1),
        .RESETB  (1'b0),
        .BLKSELB (3'b000)
    );

endmodule
