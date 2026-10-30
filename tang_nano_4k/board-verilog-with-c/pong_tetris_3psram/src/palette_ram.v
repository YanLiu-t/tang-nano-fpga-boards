//============================================================================
// PALETTE_RAM - 16-entry RGB444 colour palette (flip-flop bank)
//============================================================================
//
// The framebuffer holds 8-bit COLOUR INDICES (only 0..15 are meaningful). This
// table is the ONLY place in the whole design where an actual colour exists:
// index -> {B,G,R}. The C firmware fills it through the APB bridge (0x50 index
// / 0x54 data with auto-increment), so the "配色" of the picture is one
// hardware table shared by every game the C code implements; swapping games
// never touches the fabric.
//
// WHY 16 x RGB444 AND NOT 256 x RGB888:
//   GW1NSR-4C has NO distributed (LUT) RAM - "Not support distributed RAM in
//   current device" - and all ten BSRAM blocks are already allocated (M3 SRAM
//   x8, HyperRAM IP x1, video FIFO x1), so a large memory-mapped palette is
//   simply not buildable. This palette is therefore an explicit flip-flop bank
//   with a hand-written mux: it is NOT a Verilog memory array, which the
//   synthesizer would try (and fail) to map onto a RAM it cannot build.
//   16 entries x 12 bits = 192 FFs (+48 over the earlier RGB333 version, still
//   well inside the FF budget) and 4-bit channels give 16 levels per channel =
//   4096 colours instead of 512, so flat-shaded backgrounds can be given
//   proper hues rather than only the brightest three levels.
//
// MAP: each 8-bit channel of the written 0x00RRGGBB word contributes its HIGH
//   NIBBLE, i.e. level = byte >> 4 (0..15). C therefore writes nibble-aligned
//   values such as 0x00D0F0. The 4-bit level is expanded back to 8 bits by
//   bit replication: c -> {c, c} (= c * 17).
//
// The read port is combinational so the pixel path needs no extra pipeline
// stage; the write port runs in the APB (pclk) domain. A write can only
// mis-colour the single pixel being emitted in that instant (the palette is
// written once at startup), so no cross-domain shadow bank is needed.
//============================================================================

module palette_ram (
    input  wire        pclk,
    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [23:0] wdata,     // 0x00RRGGBB (bits [7:4] of each byte count)
    input  wire [3:0]  raddr,     // clk_p domain
    output wire [23:0] rgb        // {B,G,R} - what the SVO/TMDS stack wants
);

    localparam NP = 16;           // palette entries (indices 0..15)

    reg [NP*4-1:0] PR, PG, PB;    // 16 x 4-bit red / green / blue

    //----------------------------------------------------------------------
    // Write port (APB domain): take the top nibble of each 8-bit channel.
    //----------------------------------------------------------------------
    always @(posedge pclk) begin
        if (we && (waddr[7:4] == 4'b0000)) begin
            PR[waddr[3:0]*4 +: 4] <= wdata[23:20];
            PG[waddr[3:0]*4 +: 4] <= wdata[15:12];
            PB[waddr[3:0]*4 +: 4] <= wdata[7:4];
        end
    end

    //----------------------------------------------------------------------
    // Read port: 16:1 mux, one entry per case arm (parallel, not a memory)
    //----------------------------------------------------------------------
    reg [3:0] r4, g4, b4;

    always @(*) begin
        case (raddr)
            4'd0:  begin r4 = PR[3:0];   g4 = PG[3:0];   b4 = PB[3:0];   end
            4'd1:  begin r4 = PR[7:4];   g4 = PG[7:4];   b4 = PB[7:4];   end
            4'd2:  begin r4 = PR[11:8];  g4 = PG[11:8];  b4 = PB[11:8];  end
            4'd3:  begin r4 = PR[15:12]; g4 = PG[15:12]; b4 = PB[15:12]; end
            4'd4:  begin r4 = PR[19:16]; g4 = PG[19:16]; b4 = PB[19:16]; end
            4'd5:  begin r4 = PR[23:20]; g4 = PG[23:20]; b4 = PB[23:20]; end
            4'd6:  begin r4 = PR[27:24]; g4 = PG[27:24]; b4 = PB[27:24]; end
            4'd7:  begin r4 = PR[31:28]; g4 = PG[31:28]; b4 = PB[31:28]; end
            4'd8:  begin r4 = PR[35:32]; g4 = PG[35:32]; b4 = PB[35:32]; end
            4'd9:  begin r4 = PR[39:36]; g4 = PG[39:36]; b4 = PB[39:36]; end
            4'd10: begin r4 = PR[43:40]; g4 = PG[43:40]; b4 = PB[43:40]; end
            4'd11: begin r4 = PR[47:44]; g4 = PG[47:44]; b4 = PB[47:44]; end
            4'd12: begin r4 = PR[51:48]; g4 = PG[51:48]; b4 = PB[51:48]; end
            4'd13: begin r4 = PR[55:52]; g4 = PG[55:52]; b4 = PB[55:52]; end
            4'd14: begin r4 = PR[59:56]; g4 = PG[59:56]; b4 = PB[59:56]; end
            default: begin r4 = PR[63:60]; g4 = PG[63:60]; b4 = PB[63:60]; end
        endcase
    end

    // 4-bit -> 8-bit by bit replication, packed as {B, G, R}
    assign rgb = { {b4, b4},
                   {g4, g4},
                   {r4, r4} };

endmodule