//============================================================================
// FRAMEBUFFER - 160x120 monochrome (1 bit/pixel), 32-bit write words
//                 displayed 4x4 up-scaled on the 640x480 HDMI output
//============================================================================
// WHY 160x120 instead of 640x480 / 320x240:
//   GW1NSR-4C has only 10 BSRAM blocks (16Kbit usable each, 2KB). The
//   EMPU Cortex-M3 already occupies 8 blocks for its 16KB SRAM, leaving
//   exactly 2 blocks = 32768 bits for the framebuffer.
//     640x480 mono  needs 307200 bits = 19 blocks  -> impossible
//     320x240 mono  needs  76800 bits =  5 blocks  -> impossible
//     160x120 mono  needs  19200 bits =  2 blocks  -> fits
//   Each stored pixel is shown as a 4x4 block (uniform integer scaling),
//   which is invisible for the blocky pong graphics.
//
// WHY explicit SDPB primitives instead of inference:
//   Gowin's RAM inference on this device repeatedly failed to map the
//   memory to BSRAM and fell back to 492528 flip-flops (over the 3573
//   DFF limit). Explicitly instantiating the SDPB primitive maps to block
//   RAM 100% of the time - no inference involved.
//
// Storage: 600 words x 32 bit = 2 x SDPB (32-bit wide, 512 words each).
//   word 0..599  ->  block = word[9],  slot = word[8:0]
// Write side (APB bridge, master_pclk domain), LEVEL handshake:
//   wr_req toggles per word, wr_addr/wr_data stable before the toggle and
//   two-flop synchronized here; ack toggles once the word is written.
//   SDPB write: ADA[13:5] = slot, ADA[3:0] = 4'b1111 (byte enables).
// Read side (clk_p 25.2 MHz): every output pixel (ax,ay) reads the logical
//   pixel (ax>>2, ay>>2), so each stored pixel is repeated 4x4.
//   SDPB READ_MODE=0 (bypass): 1-cycle latency, aligned with dx/dy.
//   During a stall rd_advance=0 holds ax/ay, so ADB holds and DO just
//   refreshes the same word - stall-correct without any read enable.
//============================================================================
`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module framebuffer #( `SVO_DEFAULT_PARAMS ) (
    input clk,               // pixel clock 25.2 MHz (RAM + display)
    input resetn,            // clk-domain reset

    // write handshake (driven by apb_pong_reg, master_pclk domain)
    input  wr_req,           // level, toggles per word
    input  [13:0] wr_addr,   // word index 0..599
    input  [31:0] wr_data,   // 32 pixels, bit31 = leftmost
    output ack,              // level, toggles per written word

    // monochrome SVO stream (640x480, each bit repeated 4x4)
    output out_axis_tvalid,
    input  out_axis_tready,
    output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
    output [0:0] out_axis_tuser
);
    `SVO_DECLS

    //----------------------------------------------------------------------
    // write-side CDC: two-flop sync of req/addr/data
    //----------------------------------------------------------------------
    reg req_s1, req_s2, req_prev;
    reg [13:0] a_s0, a_s1;
    reg [31:0] d_s0, d_s1;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            req_s1  <= 1'b0; req_s2  <= 1'b0; req_prev <= 1'b0;
            a_s0    <= 14'd0; a_s1   <= 14'd0;
            d_s0    <= 32'd0; d_s1   <= 32'd0;
        end else begin
            req_s1 <= wr_req;
            req_s2 <= req_s1;
            a_s0   <= wr_addr;
            a_s1   <= a_s0;
            d_s0   <= wr_data;
            d_s1   <= d_s0;
            req_prev <= req_s2;
        end
    end

    // one-clock write-enable pulse when a new request level arrives
    wire we = req_s2 ^ req_prev;

    //--- write acknowledge ------------------------------------------------
    reg ack_r;
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            ack_r <= 1'b0;
        else if (we)
            ack_r <= ~ack_r;
    end

    assign ack = ack_r;

    //----------------------------------------------------------------------
    // display address counters (clk_p domain)
    //----------------------------------------------------------------------
    reg [9:0] ax, dx;         // current / displayed x (0..639)
    reg [8:0] ay, dy;         // current / displayed y (0..479)
    reg rd_valid;

    wire rd_advance = !rd_valid || out_axis_tready;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ax <= 10'd0; ay <= 9'd0;
            dx <= 10'd0; dy <= 9'd0;
            rd_valid <= 1'b0;
        end else if (rd_advance) begin
            dx <= ax;
            dy <= ay;
            rd_valid <= 1'b1;
            if (ax == 10'd639) begin
                ax <= 10'd0;
                if (ay == 9'd479)
                    ay <= 9'd0;
                else
                    ay <= ay + 1'b1;
            end else begin
                ax <= ax + 1'b1;
            end
        end
    end

    //----------------------------------------------------------------------
    // logical (framebuffer) coordinates: (ax,ay) >> 2  ->  0..159 x 0..119
    // word = (ay>>2)*5 + ((ax>>2)>>5)
    //----------------------------------------------------------------------
    wire [7:0]  ly = ay[8:2];      // ay>>2, 0..119
    wire [7:0]  lx = ax[9:2];      // ax>>2, 0..159
    wire [11:0] wrow  = {4'b0, ly} * 12'd5;       // ly*5 <= 595
    wire [11:0] raddr = wrow + {8'b0, lx[7:5]};   // + (lx>>5) <= 4

    wire       rblk = raddr[9];      // 0..1
    wire [8:0] rsel = raddr[8:0];    // 0..511

    wire       wblk = a_s1[9];       // 0..1
    wire [8:0] wsel = a_s1[8:0];

    //----------------------------------------------------------------------
    // 2 x SDPB block RAM (32-bit x 512 words each = 16384 bits)
    //   write: ADA = {slot, 1'b0, 4'b1111}  (ADA[13:5]=slot, ADA[3:0]=byte en)
    //   read:  ADB = {slot, 5'b00000}
    //   READ_MODE=0 (bypass): DO = registered mem[ADB], 1-cycle latency
    //----------------------------------------------------------------------
    wire [31:0] do_b [0:1];

    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin : fbram
            SDPB #(
                .READ_MODE  (1'b0),      // bypass: 1-cycle read latency
                .BIT_WIDTH_0(32),        // write port data width
                .BIT_WIDTH_1(32),        // read port data width
                .RESET_MODE ("SYNC")
            ) u_sdpb (
                .DI(d_s1),
                .ADA({wsel, 1'b0, 4'b1111}),
                .CLKA(clk),
                .CEA(we && (wblk == i)),
                .BLKSELA(3'b000),
                .RESETA(1'b0),
                .DO(do_b[i]),
                .ADB({rsel, 5'b00000}),
                .CLKB(clk),
                .CEB(1'b1),
                .OCE(1'b1),
                .RESETB(1'b0),
                .BLKSELB(3'b000)
            );
        end
    endgenerate

    // read data mux: select the block by raddr[9]
    reg [31:0] rdata;
    always @(*) begin
        case (rblk)
            1'b0: rdata = do_b[0];
            1'b1: rdata = do_b[1];
            default: rdata = 32'b0;
        endcase
    end

    // rdata is aligned with dx/dy (1-cycle SDPB latency). The framebuffer
    // bit is (dx>>2) & 31 -> dx[6:2].
    wire cur_bit = rdata[31 - dx[6:2]];

    assign out_axis_tvalid = rd_valid;
    assign out_axis_tdata  = cur_bit ? 24'hFFFFFF : 24'h000000;
    assign out_axis_tuser  = (dx == 10'd0 && dy == 9'd0);

endmodule
