//============================================================================
// ASYNC_FIFO - 128 x 32-bit dual-clock FIFO for the HyperRAM video stream
//============================================================================
//
// Write side runs in the HyperRAM clk_out domain (31.5 MHz): read bursts
// dump 32 words here as rd_data_valid pulses arrive.
// Read side runs in the pixel clock domain (25.2 MHz): the pixel streamer
// consumes words (3 words -> 4 pixels).
//
// Storage is ONE explicit SDPB block (the same primitive/pinout proven in
// the old line_buffer, including the two independent port clocks). All
// empty/full logic is fabric: 8-bit pointers (7 address bits + 1 wrap bit)
// with Gray-code 2-flop crossing.
//
// Read port has 1-cycle latency (SDPB READ_MODE=0 bypass): assert rd_en in
// cycle T with rbin pointing at the wanted slot, rd_data holds that word in
// T+1. rd_en is ignored while empty.
//
// wr_can_burst is the writer-side gate for a 32-word HyperRAM burst: it is
// high while the fill level is <= 96 words (32 free slots). The pixel side
// waits for rd_fill >= 64 before starting a frame, so the FIFO stays near
// full (~5 us / 96 words of elasticity) and the IP read-latency/refresh
// gap between bursts can never starve the active display area.
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

    input  wire        rd_clk,        // read clock (clk_p, 25.2 MHz)
    input  wire        rd_rst_n,      // read-domain async reset (active low)
    input  wire        rd_en,         // read advance (ignored when empty)
    output wire [31:0] rd_data,       // 1-cycle-latency read data
    output wire        empty,         // read-domain empty
    output wire        rd_has_word,   // read-domain: at least 1 word available
    output wire [7:0]  rd_fill        // read-domain fill level (synced wptr)
);

    localparam AW = 7;  // 128 slots
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
    // Gate a 32-word burst while at least 32 slots are free (fill <= 96).
    // Keeps the FIFO near-full in steady state (~5 us of pixel elasticity)
    // so HyperRAM read-latency/refresh gaps never starve the display.
    assign wr_can_burst = (fill_level <= 8'd96);

    //----------------------------------------------------------------------
    // Storage: one SDPB, 32-bit x 512 (only slots 0..127 used).
    //   ADA/ADB are 14 bits wide: slot[13:7] (7 bits, 128 slots), then
    //   ADA[6:5]=0, ADA[4]=0, ADA[3:0]=byte enables; ADB[6:0]=0.
    //----------------------------------------------------------------------
    SDPB #(
        .READ_MODE  (1'b0),      // bypass: 1-cycle read latency
        .BIT_WIDTH_0(32),
        .BIT_WIDTH_1(32),
        .RESET_MODE ("SYNC")
    ) u_fifo_ram (
        .DI      (wr_data),
        .ADA     ({wbin[AW-1:0], 2'b00, 1'b0, 4'b1111}),
        .CLKA    (wr_clk),
        .CEA     (wr_en && !full),
        .BLKSELA (3'b000),
        .RESETA  (1'b0),
        .DO      (rd_data),
        .ADB     ({rbin[AW-1:0], 7'b0000000}),
        .CLKB    (rd_clk),
        .CEB     (1'b1),
        .OCE     (1'b1),
        .RESETB  (1'b0),
        .BLKSELB (3'b000)
    );

endmodule
