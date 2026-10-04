module ddr3_controler(
input clk ,
input memory_clk ,
input pll_lock ,
input rst_n ,
input wr_clk ,       //写 fifo 写时钟
input rd_clk ,       //读 fifo 读时钟
input wr_en ,        //写数据使能信号
input [15:0] wrdata ,//写有效数据
input rd_req ,       //读数据请求使能
input [27:0] app_addr_rd_min ,
input [27:0] app_addr_rd_max ,
input [7:0] rd_bust_len ,
input [27:0] app_addr_wr_min ,
input [27:0] app_addr_wr_max ,
input [7:0] wr_bust_len ,
input ddr3_read_valid , //DDR3 读使能
inout [15:0] ddr_dq ,
inout [1:0] ddr_dqs ,
inout [1:0] ddr_dqs_n ,
output init_calib_complete ,
output [13:0] ddr_addr ,  //ddr3 地址
output [2:0] ddr_bank ,   //ddr3 bank 选择
output ddr_cs ,
output ddr_ras ,
output ddr_cas ,
output ddr_we ,
output ddr_ck ,
output ddr_ck_n ,
output ddr_cke ,
output ddr_odt ,
output ddr_reset_n ,
output [1:0] ddr_dm ,
output [15:0] rddata     //读有效数据
);

//wire define
wire app_rdy ;
wire [2:0] app_cmd ;
wire app_en ;
wire [28:0] app_addr ;
wire app_wdf_rdy ;
wire [127:0] app_wdf_data ;
wire app_wdf_end ;
wire [127:0] app_rd_data ; //用户读数据
wire app_rd_data_valid ;
wire app_rd_data_end ;     //突发读当前时钟最后一个数据
wire sr_ack ;
wire ref_ack ;
wire [9:0] wfifo_rcount ;  //wfifo 写进数据计数
wire [9:0] rfifo_wcount ;  //rfifo 剩余数据计数

wire ui_clk;
wire app_wdf_wren;
wire rfifo_wren;
wire ddr_rst;

//*****************************************************
//** main code
//*****************************************************

ddr3_rw u_ddr3_rw(
.ui_clk        (ui_clk),
.ui_clk_sync_rst (ddr_rst | ~rst_n),
.init_calib_complete (init_calib_complete),
.app_rdy       (app_rdy),
.app_wdf_rdy   (app_wdf_rdy),
.app_rd_data_valid (app_rd_data_valid),
.app_addr      (app_addr),
.app_en        (app_en),
.app_wdf_wren  (app_wdf_wren),
.app_wdf_end   (app_wdf_end),
.app_cmd       (app_cmd),
//DDR3
.app_addr_rd_min (app_addr_rd_min),
.app_addr_rd_max (app_addr_rd_max),
.rd_bust_len     (rd_bust_len),
.app_addr_wr_min (app_addr_wr_min),
.app_addr_wr_max (app_addr_wr_max),
.wr_bust_len     (wr_bust_len),
//
.rfifo_wren      (rfifo_wren),
.ddr3_read_valid (ddr3_read_valid),
.wfifo_rcount    (wfifo_rcount),
.rfifo_wcount    (rfifo_wcount)
);

ddr3_memory_interface u_ddr3 (
.clk            (clk),
.memory_clk     (memory_clk),
.pll_lock       (pll_lock),
.rst_n          (rst_n),
.cmd_ready      (app_rdy),
.cmd            (app_cmd),
.cmd_en         (app_en),
.addr           (app_addr),
.wr_data_rdy    (app_wdf_rdy),
.wr_data        (app_wdf_data),
.wr_data_en     (app_wdf_wren),
.wr_data_end    (app_wdf_end),
.wr_data_mask   (16'b0),
.rd_data        (app_rd_data),
.rd_data_valid  (app_rd_data_valid),
.rd_data_end    (app_rd_data_end),
.sr_req         (1'b0),
.ref_req        (1'b0),
.sr_ack         (sr_ack),
.ref_ack        (ref_ack),
.init_calib_complete(init_calib_complete),
.clk_out        (ui_clk),

.burst          (1'b0),
.ddr_rst        (ddr_rst),

// mem interface
.O_ddr_addr     (ddr_addr),
.O_ddr_ba       (ddr_bank),
.O_ddr_cs_n     (ddr_cs),
.O_ddr_ras_n    (ddr_ras),
.O_ddr_cas_n    (ddr_cas),
.O_ddr_we_n     (ddr_we),
.O_ddr_clk      (ddr_ck),
.O_ddr_clk_n    (ddr_ck_n),
.O_ddr_cke      (ddr_cke),
.O_ddr_odt      (ddr_odt),
.O_ddr_reset_n  (ddr_reset_n),
.O_ddr_dqm      (ddr_dm),
.IO_ddr_dq      (ddr_dq),
.IO_ddr_dqs     (ddr_dqs),
.IO_ddr_dqs_n   (ddr_dqs_n)
);


ddr3_fifo_ctrl u_ddr3_fifo_ctrl (
.rst_n      (rst_n),
//
.wr_clk     (wr_clk),
.rd_clk     (rd_clk),
.ui_clk     (ui_clk),
.wr_en      (wr_en),
.wrdata     (wrdata),
.rfifo_din  (app_rd_data),
.rdata_req  (rd_req),
.rfifo_wren (rfifo_wren),
.wfifo_rden (app_wdf_wren),
.wfifo_dout (app_wdf_data),
.wfifo_rcount(wfifo_rcount),
.rfifo_wcount(rfifo_wcount),
.rddata     (rddata)
);

endmodule
