//============================================================================
// APB2 SLAVE REGISTER BRIDGE - UART image byte stream (Tang Nano 4K)
//============================================================================
//
// Runs in the EMPU APB2 master clock domain (master_pclk, ~27 MHz).
// The Cortex-M3 (C firmware) receives the 640x480 RGB888 image over UART0,
// packs every 4 bytes into a 32-bit word, and writes those words here.
// The fabric side (top.v) packs 4 words = 16 bytes into one HyperRAM write
// burst. After the last word the firmware writes CTRL to start the display.
//
// Register map:
//   0x00 WR_DATA    WO [31:0] image word; writing toggles out_req (handshake)
//   0x04 CTRL       WO bit0 = start display (level, latched in fabric)
//   0x08 STATUS     RO bit1 = out_req, bit0 = out_ack (2-flop synced)
//
// Handshake is LEVEL (identical to the proven apb_pong_reg / old apb_fb_reg):
//   firmware writes WR_DATA (out_req toggles), fabric two-flop synchronizes
//   data+req into its own domain, consumes the word, toggles out_ack.
//   firmware polls STATUS bit0 until it matches the toggled req value.
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

    // Fabric-side image write window (level handshake, see top.v)
    output reg  [31:0] out_data,       // 4 bytes (RGB888), MSB = first byte
    output reg         out_req,        // toggles once per written word
    output reg         out_start,      // latched high when CTRL[0]=1
    input  wire        out_ack         // toggles once per consumed word
);

    //----------------------------------------------------------------------
    // APB protocol (always ready, no decode errors)
    //----------------------------------------------------------------------
    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    //----------------------------------------------------------------------
    // Handshake sync (fabric clk <-> pclk)
    //   ack_s0/ack_s1: 2-flop sync of out_ack from the fabric domain.
    //   req_s0/req_s1: same-domain pipeline of out_req so the STATUS read
    //                  timing matches ack_s1.
    //----------------------------------------------------------------------
    reg ack_s0, ack_s1;
    reg req_s0, req_s1;
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ack_s0 <= 1'b0; ack_s1 <= 1'b0;
            req_s0 <= 1'b0; req_s1 <= 1'b0;
        end else begin
            ack_s0 <= out_ack; ack_s1 <= ack_s0;
            req_s0 <= out_req; req_s1 <= req_s0;
        end
    end

    //----------------------------------------------------------------------
    // Combinational read mux
    //----------------------------------------------------------------------
    always @(*) begin
        case (paddr)
            8'h08: prdata = {30'b0, req_s1, ack_s1};
            default: prdata = 32'b0;
        endcase
    end

    //----------------------------------------------------------------------
    // Writes + hardware defaults
    //----------------------------------------------------------------------
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            out_data  <= 32'd0;
            out_req   <= 1'b0;
            out_start <= 1'b0;
        end else if (psel && penable && pwrite) begin
            case (paddr)
                8'h00: begin
                          out_data <= pwdata;
                          out_req  <= ~out_req;   // toggle: one word written
                       end
                8'h04: begin
                          if (pwdata[0])
                              out_start <= 1'b1;  // latch start-display level
                       end
                default: ;
            endcase
        end
    end

endmodule