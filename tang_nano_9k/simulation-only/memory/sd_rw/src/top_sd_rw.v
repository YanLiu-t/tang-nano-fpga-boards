module top_sd_rw(
input sys_clk ,         //系统时钟
input sys_rst_n ,       //系统复位，低电平有效

//SD 卡接口
input sd_miso ,         //SD 卡 SPI 串行输入数据信号
output sd_clk ,         //SD 卡 SPI 时钟信号
output sd_cs ,          //SD 卡 SPI 片选信号
output sd_mosi ,        //SD 卡 SPI 串行输出数据信号

//LED
output [3:0] led        //LED 灯
);

//wire define
wire clk_ref ;
wire clk_ref_180deg ;
wire rst_n ;
wire locked ;
wire wr_start_en ;      //开始写 SD 卡数据信号
wire [31:0] wr_sec_addr ;//写数据扇区地址
wire [15:0] wr_data ;   //写数据
wire rd_start_en ;      //开始读 SD 卡数据信号
wire [31:0] rd_sec_addr ;//读数据扇区地址
wire error_flag ;       //SD 卡读写错误的标志
wire wr_busy ;          //写数据忙信号
wire wr_req ;           //写数据请求信号
wire rd_busy ;          //读忙信号
wire rd_val_en ;        //数据读取有效使能信号
wire [15:0] rd_val_data ;//读数据
wire sd_init_done ;     //SD 卡初始化完成信号

//*****************************************************
//** main code
//*****************************************************

assign rst_n = sys_rst_n & locked;

gowin_rpll u_gowin_rpll(
.clkout(clk_ref),        //output clkout
.lock(locked),           //output lock
.clkoutp(clk_ref_180deg),//output clkoutp
.clkin(sys_clk)          //input clkin
);

//产生 SD 卡测试数据
data_gen u_data_gen(
.clk         (clk_ref),
.rst_n       (rst_n),
.sd_init_done(sd_init_done),
.wr_busy     (wr_busy),
.wr_req      (wr_req),
.wr_start_en (wr_start_en),
.wr_sec_addr (wr_sec_addr),
.wr_data     (wr_data),
.rd_val_en   (rd_val_en),
.rd_val_data (rd_val_data),
.rd_start_en (rd_start_en),
.rd_sec_addr (rd_sec_addr),
.error_flag  (error_flag)
);

//SD 卡顶层控制模块
sd_ctrl_top u_sd_ctrl_top(
.clk_ref        (clk_ref),
.clk_ref_180deg (clk_ref_180deg),
.rst_n          (rst_n),
//SD 卡接口
.sd_miso        (sd_miso),
.sd_clk         (sd_clk),
.sd_cs          (sd_cs),
.sd_mosi        (sd_mosi),
//用户写 SD 卡接口
.wr_start_en    (wr_start_en),
.wr_sec_addr    (wr_sec_addr),
.wr_data        (wr_data),
.wr_busy        (wr_busy),
.wr_req         (wr_req),
//用户读 SD 卡接口
.rd_start_en    (rd_start_en),
.rd_sec_addr    (rd_sec_addr),
.rd_busy        (rd_busy),
.rd_val_en      (rd_val_en),
.rd_val_data    (rd_val_data),

.sd_init_done   (sd_init_done)
);

//led 警示
led_alarm #(
.L_TIME (25'd25_000_000)
)
u_led_alarm(
.clk        (clk_ref),
.rst_n      (rst_n),
.led        (led),
.error_flag (error_flag)
);

endmodule
