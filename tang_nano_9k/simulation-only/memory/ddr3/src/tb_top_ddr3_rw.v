`timescale 1ps/100fs

module tb_top_ddr3_rw;

//***************************************************************************
// The following parameters refer to width of various ports
//***************************************************************************
parameter CS_WIDTH    = 1;    // # of unique CS outputs to memory.
parameter DM_WIDTH    = 2;    // # of DM (data mask)
parameter DQ_WIDTH    = 16;   // # of DQ (data)
parameter DQS_WIDTH   = 2;    // # of DQ per DQS
parameter ODT_WIDTH   = 1;    // # of ODT outputs to memory.
parameter ROW_WIDTH   = 14;   // # of memory Row Address bits.

//**************************************************************************//
// Local parameters Declarations
//**************************************************************************//
localparam real TPROP_DQS          = 0.00;  // Delay for DQS signal during Write Operation
localparam real TPROP_DQS_RD       = 0.00;  // Delay for DQS signal during Read Operation
localparam real TPROP_PCB_CTRL     = 0.00;  // Delay for Address and Ctrl signals
localparam real TPROP_PCB_DATA     = 0.00;  // Delay for data signal during Write operation
localparam real TPROP_PCB_DATA_RD  = 0.00;  // Delay for data signal during Read operation
localparam MEMORY_WIDTH = 16;
localparam NUM_COMP     = DQ_WIDTH / MEMORY_WIDTH;

//**************************************************************************//
// Wire Declarations
//**************************************************************************//
reg                                 sys_clk;
reg                                 sys_rst_n;
wire [1:0]                          led;
wire                                ddr3_reset_n;
wire [DQ_WIDTH-1:0]                 ddr3_dq_fpga;
wire [DQS_WIDTH-1:0]                ddr3_dqs_p_fpga;
wire [DQS_WIDTH-1:0]                ddr3_dqs_n_fpga;
wire [ROW_WIDTH-1:0]                ddr3_addr_fpga;
wire [3-1:0]                        ddr3_ba_fpga;
wire                                ddr3_ras_n_fpga;
wire                                ddr3_cas_n_fpga;
wire                                ddr3_we_n_fpga;
wire [1-1:0]                        ddr3_cke_fpga;
wire [1-1:0]                        ddr3_ck_p_fpga;
wire [1-1:0]                        ddr3_ck_n_fpga;
wire                                init_calib_complete;
wire [(CS_WIDTH*1)-1:0]             ddr3_cs_n_fpga;
wire [DM_WIDTH-1:0]                 ddr3_dm_fpga;
wire [ODT_WIDTH-1:0]                ddr3_odt_fpga;

reg [(CS_WIDTH*1)-1:0]              ddr3_cs_n_sdram_tmp;
reg [DM_WIDTH-1:0]                  ddr3_dm_sdram_tmp;
reg [ODT_WIDTH-1:0]                 ddr3_odt_sdram_tmp;

wire [DQ_WIDTH-1:0]                 ddr3_dq_sdram;
reg [ROW_WIDTH-1:0]                 ddr3_addr_sdram [0:1];
reg [3-1:0]                         ddr3_ba_sdram [0:1];
reg                                 ddr3_ras_n_sdram;
reg                                 ddr3_cas_n_sdram;
reg                                 ddr3_we_n_sdram;
wire [(CS_WIDTH*1)-1:0]             ddr3_cs_n_sdram;
wire [ODT_WIDTH-1:0]                ddr3_odt_sdram;
reg [1-1:0]                         ddr3_cke_sdram;
wire [DM_WIDTH-1:0]                 ddr3_dm_sdram;
wire [DQS_WIDTH-1:0]                ddr3_dqs_p_sdram;
wire [DQS_WIDTH-1:0]                ddr3_dqs_n_sdram;
reg [1-1:0]                         ddr3_ck_p_sdram;
reg [1-1:0]                         ddr3_ck_n_sdram;

//**************************************************************************//
// Reset Generation
//**************************************************************************//
initial begin
    sys_rst_n = 1'b0;
    #200000
    sys_rst_n = 1'b1;
end

//**************************************************************************//
// Clock Generation  50MHz, period=20000ps
//**************************************************************************//
initial sys_clk = 1'b0;
always sys_clk = #10000 ~sys_clk;

always @(*) begin
    ddr3_ck_p_sdram  <= ddr3_ck_p_fpga;
    ddr3_ck_n_sdram  <= ddr3_ck_n_fpga;
    ddr3_addr_sdram[0] <= ddr3_addr_fpga;
    ddr3_addr_sdram[1] <= ddr3_addr_fpga;
    ddr3_ba_sdram[0]   <= ddr3_ba_fpga;
    ddr3_ba_sdram[1]   <= ddr3_ba_fpga;
    ddr3_ras_n_sdram   <= ddr3_ras_n_fpga;
    ddr3_cas_n_sdram   <= ddr3_cas_n_fpga;
    ddr3_we_n_sdram    <= ddr3_we_n_fpga;
    ddr3_cke_sdram     <= ddr3_cke_fpga;
end

always @(*)
    ddr3_cs_n_sdram_tmp <= ddr3_cs_n_fpga;
assign ddr3_cs_n_sdram = ddr3_cs_n_sdram_tmp;

always @(*)
    ddr3_dm_sdram_tmp <= ddr3_dm_fpga; //DM signal generation
assign ddr3_dm_sdram = ddr3_dm_sdram_tmp;

always @(*)
    ddr3_odt_sdram_tmp <= ddr3_odt_fpga;
assign ddr3_odt_sdram = ddr3_odt_sdram_tmp;

// Controlling the bi‑directional BUS
genvar dqwd;
generate
for (dqwd = 1;dqwd < DQ_WIDTH;dqwd = dqwd+1) begin : dq_delay
//WireDelay #
//(
//    .Delay_g    (TPROP_PCB_DATA),
//    .Delay_rd   (TPROP_PCB_DATA_RD),
//    .ERR_INSERT ("OFF")
//)
//u_delay_dq
//(
//    .A             (ddr3_dq_fpga[dqwd]),
//    .B             (ddr3_dq_sdram[dqwd]),
//    .reset         (sys_rst_n),
//    .phy_init_done (u_top.init_calib_complete)
//);
end

//WireDelay #
//(
//    .Delay_g    (TPROP_PCB_DATA),
//    .Delay_rd   (TPROP_PCB_DATA_RD),
//    .ERR_INSERT ("OFF")
//)
//u_delay_dq_0
//(
//    .A             (ddr3_dq_fpga[0]),
//    .B             (ddr3_dq_sdram[0]),
//    .reset         (sys_rst_n),
//    .phy_init_done (u_top.init_calib_complete)
//);
endgenerate

genvar dqswd;
generate
for (dqswd = 0;dqswd < DQS_WIDTH;dqswd = dqswd+1) begin : dqs_delay
//WireDelay #
//(
//    .Delay_g    (TPROP_DQS),
//    .Delay_rd   (TPROP_DQS_RD),
//    .ERR_INSERT ("OFF")
//)
//u_delay_dqs_p
//(
//    .A             (ddr3_dqs_p_fpga[dqswd]),
//    .B             (ddr3_dqs_p_sdram[dqswd]),
//    .reset         (sys_rst_n),
//    .phy_init_done (u_top.init_calib_complete)
//);

//WireDelay #
//(
//    .Delay_g    (TPROP_DQS),
//    .Delay_rd   (TPROP_DQS_RD),
//    .ERR_INSERT ("OFF")
//)
//u_delay_dqs_n
//(
//    .A             (ddr3_dqs_n_fpga[dqswd]),
//    .B             (ddr3_dqs_n_sdram[dqswd]),
//    .reset         (sys_rst_n),
//    .phy_init_done (u_top.init_calib_complete)
//);
end
endgenerate

//===========================================================================
// FPGA Memory Controller
//===========================================================================
top u_top(
    .ddr_dq        (ddr3_dq_fpga),
    .ddr_dqs_n     (ddr3_dqs_n_fpga),
    .ddr_dqs       (ddr3_dqs_p_fpga),
    .ddr_addr      (ddr3_addr_fpga),
    .ddr_bank      (ddr3_ba_fpga),
    .ddr_ras       (ddr3_ras_n_fpga),
    .ddr_cas       (ddr3_cas_n_fpga),
    .ddr_we        (ddr3_we_n_fpga),
    .ddr_reset_n   (ddr3_reset_n),
    .ddr_ck        (ddr3_ck_p_fpga),
    .ddr_ck_n      (ddr3_ck_n_fpga),
    .ddr_cke       (ddr3_cke_fpga),
    .ddr_cs        (ddr3_cs_n_fpga),
    .ddr_dm        (ddr3_dm_fpga),
    .ddr_odt       (ddr3_odt_fpga),
    .sys_clk       (sys_clk),
    .sys_rst_n     (sys_rst_n),
    .led           (led)
);

//**************************************************************************//
// Memory Models instantiations
//**************************************************************************//
genvar r,i;
generate
//for (r = 0; r < CS_WIDTH; r = r + 1) begin: mem_rnk
//    for (i = 0; i < NUM_COMP; i = i + 1) begin: gen_mem
//        ddr3_model u_comp_ddr3
//        (
//            .rst_n     (ddr3_reset_n),
//            .ck        (ddr3_ck_p_sdram),
//            .ck_n      (ddr3_ck_n_sdram),
//            .cke       (ddr3_cke_sdram[r]),
//            .cs_n      (ddr3_cs_n_sdram[r]),
//            .ras_n     (ddr3_ras_n_sdram),
//            .cas_n     (ddr3_cas_n_sdram),
//            .we_n      (ddr3_we_n_sdram),
//            .dm_tdqs   (ddr3_dm_sdram[(2*(i+1)-1):(2*i)]),
//            .ba        (ddr3_ba_sdram[r]),
//            .addr      (ddr3_addr_sdram[r]),
//            .dq        (ddr3_dq_sdram[16*(i+1)-1:16*(i)]),
//            .dqs       (ddr3_dqs_p_sdram[(2*(i+1)-1):(2*i)]),
//            .dqs_n     (ddr3_dqs_n_sdram[(2*(i+1)-1):(2*i)]),
//            .tdqs_n    (),
//            .odt       (ddr3_odt_sdram[r])
//        );
//    end
//end
endgenerate

endmodule
