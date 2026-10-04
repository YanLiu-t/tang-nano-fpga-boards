module top
(
input           sys_clk,         //系统时钟，50MHz
input           sys_rst_n,       //复位,低有效
inout  [15:0]   ddr_dq,          //ddr3 数据
inout  [1:0]    ddr_dqs,
inout  [1:0]    ddr_dqs_n,
output [13:0]   ddr_addr,        //ddr3 地址
output [2:0]    ddr_bank,        //ddr3 bank 选择
output          ddr_cs,          //ddr3 片选
output          ddr_ras,         //ddr3 行选择
output          ddr_cas,         //ddr3 列选择
output          ddr_we,          //ddr3 读写选择
output          ddr_ck,
output          ddr_ck_n,
output          ddr_cke,         //ddr3 时钟使能
output          ddr_odt,
output          ddr_reset_n,     //ddr3 复位
output [1:0]    ddr_dm,
output [1:0]    led              //led 灯
);

//wire define
wire [27:0] app_addr_rd_min ;
wire [15:0] wr_data ;             //写入 DDR3 的数据
wire [27:0] app_addr_rd_max ;
wire [7:0]  rd_bust_len ;
wire [27:0] app_addr_wr_min ;
wire [27:0] app_addr_wr_max ;
wire [7:0]  wr_bust_len ;
wire [15:0] rd_data ; /*synthesis syn_keep=1*/
wire        pll_lock ;
wire        memory_clk;
wire        init_calib_complete;
wire        wr_en;
wire        rd_req;
wire        error;
wire        rst_n;

//*****************************************************
//** main code
//*****************************************************

assign app_addr_rd_min = 28'd0;
assign app_addr_rd_max = 28'd1024;
assign rd_bust_len     = 8'd64;
assign app_addr_wr_min = 28'd0;
assign app_addr_wr_max = 28'd1024;
assign wr_bust_len     = 8'd64;

//复位信号
assign rst_n = pll_lock && sys_rst_n;

ddr3_controler u_ddr3_controler(
.clk                (sys_clk) ,
.memory_clk         (memory_clk) ,
.pll_lock           (pll_lock) ,
.rst_n              (sys_rst_n) ,
.init_calib_complete(init_calib_complete) ,  //ddr3 初始化完成信号
.ddr_addr           (ddr_addr) ,
.ddr_bank           (ddr_bank) ,
.ddr_cs             (ddr_cs) ,
.ddr_ras            (ddr_ras) ,
.ddr_cas            (ddr_cas) ,
.ddr_we             (ddr_we) ,
.ddr_ck             (ddr_ck) ,
.ddr_ck_n           (ddr_ck_n) ,
.ddr_cke            (ddr_cke) ,
.ddr_odt            (ddr_odt) ,
.ddr_reset_n        (ddr_reset_n) ,
.ddr_dm             (ddr_dm) ,
.ddr_dq             (ddr_dq) ,
.ddr_dqs            (ddr_dqs) ,
.ddr_dqs_n          (ddr_dqs_n) ,
.wr_clk             (sys_clk) ,
.rd_clk             (sys_clk) ,
.wr_en              (wr_en) ,
.wrdata             (wr_data) ,
.rd_req             (rd_req) ,              //读 fifo 读使能
.app_addr_rd_min    (app_addr_rd_min) ,     //读 ddr3 的起始地址
.app_addr_rd_max    (app_addr_rd_max) ,     //读 ddr3 的结束地址
.rd_bust_len        (rd_bust_len) ,         //从 ddr3 中读数据时的突发长度
.app_addr_wr_min    (app_addr_wr_min) ,     //写 ddr3 的起始地址
.app_addr_wr_max    (app_addr_wr_max) ,     //写 ddr3 的结束地址
.wr_bust_len        (wr_bust_len) ,         //从 ddr3 中写数据时的突发长度
.ddr3_read_valid    (1'b1) ,
.rddata             (rd_data)
);

gowin_rpll pll(
.clkout(memory_clk) ,   //output clkout
.lock  (pll_lock) ,     //output lock
.clkin (sys_clk)        //input clkin
);

test_data u_test_data(
.clk_50m            (sys_clk) ,
.rst_n              (rst_n) ,
.init_calib_complete(init_calib_complete) , //ddr3 初始化完成信号
.rd_data            (rd_data) ,
.rd_req             (rd_req) ,
.wr_data            (wr_data) ,
.wr_en              (wr_en) ,
.error              (error)
);

led_disp u_led_disp(
.clk_50m     (sys_clk) ,
.rst_n       (rst_n) ,
.error_flag  (error) ,         //DDR3 初始化失败或者读写错误都认为是实验失败
.init_calib_complete(init_calib_complete) ,
.led         (led)
);

endmodule
