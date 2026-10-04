module sd_bmp_lcd(
input sys_clk ,                     //系统时钟
input sys_rst_n ,                   //系统复位，低电平有效
//SD 卡接口
input sd_miso ,                     //SD 卡 SPI 串行输入数据信号
output sd_clk ,                     //SD 卡 SPI 时钟信号
output sd_cs ,                      //SD 卡 SPI 片选信号
output sd_mosi ,                    //SD 卡 SPI 串行输出数据信号
//DDR3
output ddr_reset_n ,                //ddr3 复位
output [13:0] ddr_addr ,            //ddr3 地址
output [2:0] ddr_bank ,             //ddr3 banck 选择
output ddr_cs ,                     //ddr3 片选
output ddr_ras ,                    //ddr3 行选择
output ddr_cas ,                    //ddr3 列选择
output ddr_we ,                     //ddr3 读写选择
output ddr_ck ,
output ddr_ck_n ,
output ddr_cke ,                    //ddr3 时钟使能
output ddr_odt ,
output [1:0] ddr_dm ,
inout [1:0] ddr_dqs_n ,
inout [15:0] ddr_dq ,               //ddr3 数据
inout [1:0] ddr_dqs ,
//lcd 接口
output lcd_hs ,                     //LCD 行同步信号
output lcd_vs ,                     //LCD 场同步信号
output lcd_de ,                     //LCD 数据输入使能
inout [23:0] lcd_rgb ,              //LCD 颜色数据
output lcd_bl ,                     //LCD 背光控制信号
output lcd_rst ,                    //LCD 复位信号
output lcd_pclk                     //LCD 采样时钟
);

//wire define
wire sd_init_done ;                 //SD 卡初始化完成信号
wire sys_init_done ;                //系统初始化完成(DDR 初始化+SD卡初始化)
wire clk_50m ;                      //50mhz 时钟
wire lcd_clk ;                      //分频产生的 LCD 采样时钟
wire wr_en ;                        //DDR3 控制器模块写使能
wire ddr_wr_en ;                    //DDR3 控制器模块写使能
wire [15:0] wr_data ;               //DDR3 控制器模块写数据
wire [15:0] ddr_wr_data ;           //DDR3 控制器模块写数据
wire rdata_req ;                    //DDR3 控制器模块读使能
wire [23:0] ddr_max_addr ;          //DDR 读写最大地址
wire [12:0] h_disp ;                //LCD 屏水平分辨率
wire [15:0] rd_data ;               //DDR3 控制器模块读数据
wire [15:0] lcd_id ;                //LCD 屏的 ID 号
wire [15:0] sd_sec_num ;            //SD 卡读扇区个数
wire sd_rd_busy ;                   //读忙信号
wire sd_rd_val_en ;                 //数据读取有效使能信号
wire [15:0] sd_rd_val_data ;        //读数据
wire sd_rd_start_en ;               //开始读 SD 卡数据信号
wire [31:0] sd_rd_sec_addr ;        //读数据扇区地址
wire clk_50m_180deg ;
wire rst_n;
wire lock_o;
wire lock;
wire memory_clk;
wire init_calib_complete;
wire rd_vsync;
wire [12:0] v_disp;

//*****************************************************
//** main code
//*****************************************************
//待时钟锁定后产生复位结束信号
assign rst_n = sys_rst_n & lock_o;
//系统初始化完成：DDR3 初始化完成 & SD 卡初始化完成
assign sys_init_done = init_calib_complete & sd_init_done;
//DDR3 控制器模块为写使能和写数据赋值
assign wr_en = ddr_wr_en;
assign wr_data = ddr_wr_data;

//DDR 和 SD 卡参数计算模块
sd_ddr_size u_sd_rd_size(
.clk        (sys_clk ),
.rst_n      (rst_n),
.id_lcd     (lcd_id),              //LCD 的器件 ID

.ddr_max_addr(ddr_max_addr),
.sd_sec_num (sd_sec_num)
);

//读取 SD 卡图片
sd_read_photo u_sd_read_photo(
.clk            (sys_clk),
//系统初始化完成之后,再开始从 SD 卡中读取图片
.rst_n          ( rst_n & sys_init_done ),
.ddr_max_addr   (ddr_max_addr),
.sd_sec_num     (sd_sec_num),
.rd_busy        (sd_rd_busy),
.sd_rd_val_en   (sd_rd_val_en),
.sd_rd_val_data (sd_rd_val_data),
.rd_start_en    (sd_rd_start_en),
.rd_sec_addr    (sd_rd_sec_addr),
.ddr_wr_en      (ddr_wr_en),
.ddr_wr_data    (ddr_wr_data)
);

//SD 卡顶层控制模块
sd_ctrl_top u_sd_ctrl_top(
.clk_ref        (sys_clk),
.clk_ref_180deg (clk_50m_180deg),
.rst_n          (rst_n),
//SD 卡接口
.sd_miso        (sd_miso),
.sd_clk         (sd_clk),
.sd_cs          (sd_cs),
.sd_mosi        (sd_mosi),
//用户写 SD 卡接口
.wr_start_en    (1'b0),            //不需要写入数据,写入接口赋值为 0
.wr_sec_addr    (32'b0),
.wr_data        (16'b0),
.wr_busy        (),
.wr_req         (),
//用户读 SD 卡接口
.rd_start_en    (sd_rd_start_en),
.rd_sec_addr    (sd_rd_sec_addr),
.rd_busy        (sd_rd_busy),
.rd_val_en      (sd_rd_val_en),
.rd_val_data    (sd_rd_val_data),

.sd_init_done   (sd_init_done)
);

ddr3_top u_ddr3_top(
.clk            (sys_clk) ,
.memory_clk     (memory_clk) ,
.pll_lock       (lock) ,
.rst_n          (sys_rst_n) ,
.init_calib_complete (init_calib_complete) , //ddr3 初始化完成信号
.ddr_addr       (ddr_addr) ,
.ddr_bank       (ddr_bank) ,
.ddr_cs         (ddr_cs) ,
.ddr_ras        (ddr_ras) ,
.ddr_cas        (ddr_cas) ,
.ddr_we         (ddr_we) ,
.ddr_ck         (ddr_ck) ,
.ddr_ck_n       (ddr_ck_n) ,
.ddr_cke        (ddr_cke) ,
.ddr_odt        (ddr_odt) ,
.ddr_reset_n    (ddr_reset_n) ,
.ddr_dm         (ddr_dm) ,
.ddr_dq         (ddr_dq) ,
.ddr_dqs        (ddr_dqs) ,
.ddr_dqs_n      (ddr_dqs_n) ,
.wr_clk         (sys_clk) ,
.rd_clk         (lcd_clk) ,
.wr_en          (wr_en) ,
.wrdata         (wr_data) ,
.rd_req         (rdata_req) ,      //读 fifo 读使能
.app_addr_rd_min (28'd0) ,         //读 ddr3 的起始地址
.app_addr_rd_max ({4'd0,ddr_max_addr}) , //读 ddr3 的结束地址
.rd_bust_len    (h_disp[10:3]) ,   //从 ddr3 中读数据时的突发长度
.app_addr_wr_min (28'd0) ,         //写 ddr3 的起始地址
.app_addr_wr_max ({4'd0,ddr_max_addr}) , //写 ddr3 的结束地址
.wr_bust_len    (h_disp[10:3]) ,   //从 ddr3 中写数据时的突发长度
.ddr3_read_valid (1'b1) ,
.rd_load        (rd_vsync) ,
.wr_load        (1'b0) ,
.ddr3_pingpang_en (1'b1) ,
.rddata         (rd_data)
);

//时钟 IP 核
ddr_rpll u_ddr_rpll(
.clkout(memory_clk),                //output clkout
.lock(lock),                        //output lock
.reset(~sys_rst_n),                 //input reset
.clkin(sys_clk)                     //input clkin
);

sd_rpll u_sd_rpll(
.clkout(clk_50m),                   //output clkout
.lock(lock_o),                      //output lock
.clkoutp(clk_50m_180deg),           //output clkoutp
.reset(~sys_rst_n),                 //input reset
.clkin(sys_clk)                     //input clkin
);

//LCD 驱动显示模块
lcd_rgb_top u_lcd_rgb_top(
.sys_clk        (sys_clk),
.sys_rst_n      (rst_n),
.sys_init_done  (sys_init_done),

//lcd 接口
.lcd_id         (lcd_id),           //LCD 屏的 ID 号
.lcd_hs         (lcd_hs),           //LCD 行同步信号
.lcd_vs         (lcd_vs),           //LCD 场同步信号
.lcd_de         (lcd_de),           //LCD 数据输入使能
.lcd_rgb        (lcd_rgb),          //LCD 颜色数据
.lcd_bl         (lcd_bl),           //LCD 背光控制信号
.lcd_rst        (lcd_rst),          //LCD 复位信号
.lcd_pclk       (lcd_pclk),         //LCD 采样时钟
.lcd_clk        (lcd_clk),          //LCD 驱动时钟
//用户接口
.out_vsync      (rd_vsync),         //lcd 场信号
.h_disp         (h_disp),           //行分辨率
.v_disp         (v_disp),           //场分辨率
.pixel_xpos     (),
.pixel_ypos     (),
.data_in        (rd_data),          //rfifo 输出数据
.data_req       (rdata_req)         //请求数据输入
);

endmodule
