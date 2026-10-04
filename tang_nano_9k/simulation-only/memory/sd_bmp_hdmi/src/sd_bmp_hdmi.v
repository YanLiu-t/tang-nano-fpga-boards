module sd_bmp_hdmi(
    input        sys_clk,         //系统时钟
    input        sys_rst_n,       //系统复位，低电平有效
    //SD 卡接口
    input        sd_miso,         //SD 卡 SPI 串行输入数据信号
    output       sd_clk,          //SD 卡 SPI 时钟信号
    output       sd_cs,           //SD 卡 SPI 片选信号
    output       sd_mosi,         //SD 卡 SPI 串行输出数据信号
    //DDR3
    output       ddr_reset_n,     //ddr3 复位
    output [13:0]ddr_addr,        //ddr3 地址
    output [2:0] ddr_bank,        //ddr3 banck 选择
    output       ddr_cs,          //ddr3 片选
    output       ddr_ras,         //ddr3 行选择
    output       ddr_cas,         //ddr3 列选择
    output       ddr_we,          //ddr3 读写选择
    output       ddr_ck,
    output       ddr_ck_n,
    output       ddr_cke,         //ddr3 时钟使能
    output       ddr_odt,
    output [1:0] ddr_dm,
    inout  [1:0] ddr_dqs_n,
    inout  [15:0]ddr_dq,          //ddr3 数据
    inout  [1:0] ddr_dqs,
    //HDMI 接口
    output       tmds_clk_p,      // TMDS 时钟通道
    output       tmds_clk_n,
    output [2:0] tmds_data_p,     // TMDS 数据通道
    output [2:0] tmds_data_n
);

//parameter define
parameter V_CMOS_DISP  = 11'd768;   //CMOS 分辨率--行
parameter H_CMOS_DISP  = 11'd1024;  //CMOS 分辨率--列
//DDR3 读写最大地址 1024 * 768 = 786432
parameter DDR_MAX_ADDR = 786432;
//SD 卡读扇区个数 1024 * 768 * 3 / 512 + 1 = 4609
parameter SD_SEC_NUM   = 4609;

//wire define
wire        sd_init_done;       //SD 卡初始化完成信号
wire        sys_init_done;      //系统初始化完成(DDR 初始化+摄像头初始化)
wire        clk_50m;            //50mhz 时钟
wire        lcd_clk;            //分频产生的 LCD 采样时钟
wire        wr_en;              //DDR3 控制器模块写使能
wire        ddr_wr_en;          //DDR3 控制器模块写使能
wire [15:0] wr_data;            //DDR3 控制器模块写数据
wire [15:0] ddr_wr_data;        //DDR3 控制器模块写数据
wire        rdata_req;          //DDR3 控制器模块读使能
wire [23:0] ddr_max_addr;       //DDR 读写最大地址
wire [12:0] h_disp;             //LCD 屏水平分辨率
wire [15:0] rd_data;            //DDR3 控制器模块读数据
wire [15:0] lcd_id;             //LCD 屏的 ID 号
wire [15:0] sd_sec_num;         //SD 卡读扇区个数
wire        sd_rd_busy;         //读忙信号
wire        sd_rd_val_en;       //数据读取有效使能信号
wire [15:0] sd_rd_val_data;     //读数据
wire        sd_rd_start_en;     //开始写 SD 卡数据信号
wire [31:0] sd_rd_sec_addr;     //读数据扇区地址
wire        clk_50m_180deg;
wire        pixel_clk;          //像素时钟 65M
wire        pixel_clk_5x;       //5 倍像素时钟 325M
wire        rd_vsync;

wire        rst_n;
wire        lock_o;
wire        lock;
wire        lock_i;
wire        memory_clk;
wire        init_calib_complete;

//*****************************************************
//** main code
//*****************************************************
//待时钟锁定后产生复位结束信号
assign rst_n = sys_rst_n & lock_o;
//系统初始化完成：DDR3 初始化完成 & SD 卡初始化完成
assign sys_init_done = init_calib_complete & sd_init_done;
//DDR3 控制器模块为写使能和写数据赋值
assign wr_en  = ddr_wr_en;
assign wr_data= ddr_wr_data;

//读取 SD 卡图片
sd_read_photo u_sd_read_photo(
    .clk            (sys_clk),
    //系统初始化完成之后,再开始从 SD 卡中读取图片
    .rst_n          (rst_n & sys_init_done ),
    .ddr_max_addr   (DDR_MAX_ADDR),
    .sd_sec_num     (SD_SEC_NUM),
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
    .wr_start_en    (1'b0),     //不需要写入数据,写入接口赋值为 0
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

//ddr3_top u_ddr3_top(
//    .clk            (sys_clk),
//    .memory_clk     (memory_clk),
//    .pll_lock       (lock),
//    .rst_n          (sys_rst_n),
//    .init_calib_complete (init_calib_complete), //ddr3 初始化完成信号
//    .ddr_addr       (ddr_addr),
//    .ddr_bank       (ddr_bank),
//    .ddr_cs         (ddr_cs),
//    .ddr_ras        (ddr_ras),
//    .ddr_cas        (ddr_cas),
//    .ddr_we         (ddr_we),
//    .ddr_ck         (ddr_ck),
//    .ddr_ck_n       (ddr_ck_n),
//    .ddr_cke        (ddr_cke),
//    .ddr_odt        (ddr_odt),
//    .ddr_reset_n    (ddr_reset_n),
//    .ddr_dm         (ddr_dm),
//    .ddr_dq         (ddr_dq),
//    .ddr_dqs        (ddr_dqs),
//    .ddr_dqs_n      (ddr_dqs_n),
//    .wr_clk         (sys_clk),
//    .rd_clk         (pixel_clk),
//    .wr_en          (wr_en),
//    .wrdata         (wr_data),
//    .rd_req         (rdata_req),    //读 fifo 读使能
//    .app_addr_rd_min(28'd0),        //读 ddr3 的起始地址
//    .app_addr_rd_max(DDR_MAX_ADDR), //读 ddr3 的结束地址
//    .rd_bust_len    (H_CMOS_DISP[10:3]), //从 ddr3 中读数据时的突发长度
//    .app_addr_wr_min(28'd0),        //写 ddr3 的起始地址
//    .app_addr_wr_max(DDR_MAX_ADDR), //写 ddr3 的结束地址
//    .wr_bust_len    (H_CMOS_DISP[10:3]), //从 ddr3 中写数据时的突发长度
//    .ddr3_read_valid(1'b1),
//    .rd_load        (rd_vsync),
//    .wr_load        (1'b0),
//    .ddr3_pingpang_en(1'b1),
//    .rddata         (rd_data)
//);

//时钟 IP 核
rpll_pixel_clk_5x u_rpll_pixel_clk_5x(
    .clkout(pixel_clk_5x),  //output clkout
    .lock(lock_i),          //output lock
    .reset(~sys_rst_n),     //input reset
    .clkin(sys_clk)         //input clkin
);

clk_div5 u_clk_div5(
    .clkout(pixel_clk),     //output clkout
    .hclkin(pixel_clk_5x),  //input hclkin
    .resetn(rst_n)          //input resetn
);

ddr_rpll u_ddr_rpll(
    .clkout(memory_clk),    //output clkout
    .lock(lock),            //output lock
    .reset(~sys_rst_n),     //input reset
    .clkin(sys_clk)         //input clkin
);

sd_rpll u_sd_rpll(
    .clkout(clk_50m),       //output clkout
    .lock(lock_o),          //output lock
    .clkoutp(clk_50m_180deg),//output clkoutp
    .reset(~sys_rst_n),     //input reset
    .clkin(sys_clk)         //input clkin
);

//HDMI 顶层模块
hdmi_corlorbar u_hdmi_top(
    .hdmi_clk     (pixel_clk),
    .hdmi_clk_5   (pixel_clk_5x),
    .sys_rst_n    (rst_n & sys_init_done),
    //HDMI interface
    .tmds_clk_p   (tmds_clk_p),
    .tmds_clk_n   (tmds_clk_n),
    .tmds_data_p  (tmds_data_p),
    .tmds_data_n  (tmds_data_n),
    //user interface
    .rd_data      (rd_data),
    .rd_en        (rdata_req),
    .video_vs     (rd_vsync),
    .pixel_xpos   (),
    .pixel_ypos   ()
);

endmodule