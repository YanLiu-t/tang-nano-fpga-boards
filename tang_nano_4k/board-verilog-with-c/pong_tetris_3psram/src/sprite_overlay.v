//============================================================================
// SPRITE_OVERLAY - generic hardware rectangle table (game-agnostic)
//============================================================================
//
// The fabric knows NOTHING about paddles, balls, tetrominoes or any other game
// object. It offers NS free rectangles; each one is {x, y, w, h, colour
// index, enable}. The C firmware decides how many objects exist, how big they
// are and where they are; the hardware only does the per-pixel "is this pixel
// inside rectangle k?" test and reports the palette index of the winning one.
//
// NS = 5 is the MEASURED ceiling of GW1NSR-4C for this design, not a guess.
// The same netlist was placed with NS = 5,6,7,8 and only 5 was accepted
// ("Failed to place" with 21/42/81 REG unPlaced for 6/7/8). The wall is
// register-SITE placement, not logic volume: deleting the per-rectangle
// x0+w / y0+h adders (-168 ALU) and removing the async reset from 320 FFs
// both left the unPlaced count at ~80 with CLS pinned at 93%. 4 rectangles
// cover both games (Pong: ball + 2 paddles; Tetris: the four cells of the
// falling tetromino); the 5th is spare. The APB window only reaches
// rectangles 0..3, so apb_fb_reg.v adds a bank bit (register 0x40) that
// prepends to `sel`: sel = {bank, addr[6:5]} - that is what makes index 4
// reachable, and it stays correct for any future NS up to 8.
//
// Priority: the HIGHEST matching index wins (later table entries are painted
// over earlier ones), so the firmware writes back-to-front: background-most
// object at index 0, front-most object last.
//
// WHY THERE IS NO CDC SHADOW BANK HERE
//   The table is plain flip-flops in the APB (pclk) domain and the pixel path
//   only READS them combinationally. Writes are rare (a few per displayed
//   frame, only when an object actually moves) and each changed bit can only
//   affect the pixel being emitted in that instant: a one-pixel colour glitch
//   during a field update, which is invisible. A full cross-domain shadow
//   bank would cost another NS*42 FFs - the budget after adding the palette is
//   already tight on GW1NSR-4C - for no visible benefit. This is exactly the
//   same trade-off palette_ram.v makes.
//
// FIELD MAP (APB writes, payload stable while `we` is high):
//   field 0 : x0[9:0]                    field 3 : y1[9:0] = y0 + h
//   field 1 : y0[8:0]  (0..479)          field 4 : {22'b0, dash, enable, colour[3:0]}
//   field 2 : x1[9:0] = x0 + w
//   The rectangle covers x in [x0, x1) and y in [y0, y1); the C side always
//   supplies the exclusive right/bottom edges so the hit test needs no adder.
//
//   field 4 carries a per-rectangle DASH flag in bit 9 (wdata[9]). When set,
//   the rectangle is painted on a 2x2 checkerboard (every other 2x2 cluster),
//   so its fill reads as a dotted / dashed block instead of solid fill.
//============================================================================

module sprite_overlay #(
    parameter NS = 5              // number of rectangles (measured max)
)(
    input  wire        pclk,      // APB domain: the table lives here
    input  wire        presetn,

    input  wire        we,        // one-cycle strobe, sel/field/wdata stable
    input  wire [2:0]  sel,       // rectangle index 0..NS-1
    input  wire [2:0]  field,     // field selector (see field map above)
    input  wire [15:0] wdata,

    // pixel domain: current raster coordinate, combinational read only
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    output wire [7:0]  idx,       // palette index of the winning rectangle
    output wire        hit        // 1 when any enabled rectangle covers (x,y)
);

    localparam SW = 10;           // x0 bits (and right-edge bits)
    localparam SYW = 9;           // y0 bits
    localparam EW = 10;           // right edge (x0+w) bits
    localparam EH = 10;           // bottom edge (y0+h) bits
    localparam CW = 4;            // colour-index bits (16-entry palette)

    //------------------------------------------------------------------------
    // The table: NS x {x0, y0, x1, y1, colour, enable}
    //   x1 = x0 + w and y1 = y0 + h are the EXCLUSIVE right/bottom edges and
    //   are computed by the C firmware (game_hal.h spr_box). Computing them in
    //   hardware cost two extra adders per rectangle inside the per-pixel hit
    //   loop; at NS=8 that is ~160 ALU, and CLS - not FFs - is what GW1NSR-4C
    //   runs out of (the placer failed at 94% CLS with "N REG(s) unPlaced").
    //------------------------------------------------------------------------
    reg [NS*SW-1:0]  TX;
    reg [NS*SYW-1:0] TY;
    reg [NS*EW-1:0]  TXE;
    reg [NS*EH-1:0]  TYE;
    reg [NS*CW-1:0]  TC;
    reg [NS-1:0]     TE;
    reg [NS-1:0]     TD;     // per-rectangle dash flag (dotted fill)

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            TX <= 0; TY <= 0; TXE <= 0; TYE <= 0; TC <= 0; TE <= 0; TD <= 0;
        end else if (we && (sel < NS)) begin
            case (field)
                3'd0: TX[sel*SW  +: SW ] <= wdata[SW-1:0];
                3'd1: TY[sel*SYW +: SYW] <= wdata[SYW-1:0];
                3'd2: TXE[sel*EW +: EW ] <= wdata[EW-1:0];
                3'd3: TYE[sel*EH +: EH ] <= wdata[EH-1:0];
                3'd4: begin
                          TC[sel*CW +: CW] <= wdata[CW-1:0];
                          TE[sel]          <= wdata[8];
                          TD[sel]          <= wdata[9];
                      end
                default: ;
            endcase
        end
    end

    //------------------------------------------------------------------------
    // Per-pixel hit test (combinational). x1/y1 are stored edges, so there is
    // no adder here at all - just four range comparators per rectangle.
    //------------------------------------------------------------------------
    integer    k;
    reg [7:0]  cidx;
    reg        chit;

    // 2x2 checkerboard phase: a dashed rectangle paints only every other 2x2
    // cluster, so its fill looks dotted instead of solid.
    wire dash_on = ~(x[1] ^ y[1]);

    always @(*) begin
        cidx = 8'd0;
        chit = 1'b0;
        for (k = 0; k < NS; k = k + 1) begin
            if (TE[k] &&
                (x >= TX[k*SW  +: SW ]) && (x < TXE[k*EW +: EW]) &&
                (y >= TY[k*SYW +: SYW]) && (y < TYE[k*EH +: EH]) &&
                (!TD[k] || dash_on)) begin
                chit = 1'b1;
                cidx = TC[k*CW +: CW];
            end
        end
    end

    assign idx = cidx;
    assign hit = chit;

endmodule