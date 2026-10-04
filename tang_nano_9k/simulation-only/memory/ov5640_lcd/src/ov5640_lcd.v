module ov5640_lcd(
input               sys_clk ,         //系统时钟
input               sys_rst_n ,       //系统复位，低电平有效
input               cam_pclk ,        //cmos 数据像素时钟
input               cam_vsync ,       //cmos 场同步信号
input               cam_href ,        //cmos 行同步信号
input      [7:0]    cam_data ,        //cmos 数据
inout               cam_sda ,         //cmos SCCB_SDA 线
output              cam_scl ,         //cmos SCCB_SCL 线
output              cam_rst_n ,       //cmos 复位信号，低电平有效
output              cam_pwdn ,        //电源休眠模式 0：正常模式 1：电源休眠模式
output              ddr_reset_n ,     //ddr3 复位
output     [13:0]   ddr_addr ,        //ddr3 地址
output     [2:0]    ddr_bank ,        //ddr3 banck 选择
output              ddr_cs ,          //ddr3 片选
output              ddr_ras ,         //ddr3 行选择
output              ddr_cas ,         //ddr3 列选择
output              ddr_we ,          //ddr3 读写选择
output              ddr_ck ,
output              ddr_ck_n ,
output              ddr_cke ,         //ddr3 时钟使能
output              ddr_odt ,
output     [1:0]    ddr_dm ,          //ddr3 数据掩码
inout      [1:0]    ddr_dqs_n ,
inout      [15:0]   ddr_dq ,
inout      [1:0]    ddr_dqs ,
inout      [23:0]   lcd_rgb ,         //LCD 颜色数据
output              lcd_de ,          //LCD 数据输入使能
output              lcd_hs ,          //LCD 行同步信号
output              lcd_vs ,          //LCD 场同步信号
output              lcd_bl ,          //LCD 背光控制信号
output              lcd_rst ,         //LCD 复位信号
output              lcd_pclk          //LCD 采样时钟
);

//wire define
wire                rst_n;
wire                pll_lock;
wire                memory_clk;
wire                init_calib_complete ;
wire                cmos_frame_valid ;    //数据有效使能信号
wire      [15:0]    wr_data ;             //DDR3 控制器模块写数据
wire                rdata_req ;           //DDR3 控制器模块读使能
wire      [27:0]    ddr3_addr_max ;       //存入 DDR3 的最大读写地址
wire      [12:0]    h_disp ;              //LCD 屏水平分辨率
wire                cmos_frame_vsync ;    //输出帧有效场同步信号
wire      [15:0]    rd_data ;             //DDR3 控制器模块读数据
wire      [15:0]    lcd_id ;              //LCD 屏的 ID 号
wire      [12:0]    v_disp ;              //LCD 屏垂直分辨率
wire      [12:0]    total_h_pixel ;       //水平总像素大小
wire      [12:0]    total_v_pixel ;       //垂直总像素大小
wire      [12:0]    y_addr_st ;
wire      [12:0]    y_addr_end ;
wire                sys_init_done ;        //系统初始化完成(DDR 初始化)
wire                lcd_clk ;             //分频产生的 LCD 采样时钟
wire                rd_vsync;

//*****************************************************
//** main code
//*****************************************************
//待时钟锁定后产生复位结束信号
assign rst_n = sys_rst_n & pll_lock;

//系统初始化完成：DDR3 初始化完成
assign sys_init_done = init_calib_complete;

//摄像头图像分辨率设置模块
picture_size u_picture_size (
    .rst_n          (rst_n),
    .clk            (sys_clk),
    .lcd_id         (lcd_id),              //LCD 的器件 ID

    .cmos_h_pixel   (h_disp ),             //摄像头水平分辨率
    .cmos_v_pixel   (v_disp ),             //摄像头垂直分辨率
    .total_h_pixel  (total_h_pixel ),      //水平总像素大小
    .total_v_pixel  (total_v_pixel ),      //垂直总像素大小
    .y_addr_st      (y_addr_st ),
    .y_addr_end     (y_addr_end),
    .ddr3_addr_max  (ddr3_addr_max)        //ddr3 最大读写地址
);

//ov5640 驱动
ov5640_dri u_ov5640_dri(
    .clk            (sys_clk),
    .rst_n          (rst_n),

    .cam_pclk       (cam_pclk ),
    .cam_vsync      (cam_vsync),
    .cam_href       (cam_href ),
    .cam_data       (cam_data ),
    .cam_rst_n      (cam_rst_n),
    .cam_pwdn       (cam_pwdn ),
    .cam_scl        (cam_scl ),
    .cam_sda        (cam_sda ),

    .capture_start  (init_calib_complete),
    .cmos_h_pixel   (h_disp),
    .cmos_v_pixel   (v_disp),
    .total_h_pixel  (total_h_pixel),
    .total_v_pixel  (total_v_pixel),
    .y_addr_st      (y_addr_st),
    .y_addr_end     (y_addr_end),
    .cmos_frame_vsync(cmos_frame_vsync),
    .cmos_frame_href (),
    .cmos_frame_valid(cmos_frame_valid),
    .cmos_frame_data (wr_data)
);

ddr3_top u_ddr3_top(
    .clk            (sys_clk) ,
    .memory_clk     (memory_clk) ,
    .pll_lock       (pll_lock) ,
    .rst_n          (sys_rst_n) ,
    .init_calib_complete(init_calib_complete) , //ddr3 初始化完成信号
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
    .wr_clk         (cam_pclk) ,
    .rd_clk         (lcd_clk) ,
    .wr_en          (cmos_frame_valid) ,
    .wrdata         (wr_data) ,
    .rd_req         (rdata_req) ,      //读 fifo 读使能
    .app_addr_rd_min(28'd0) ,          //读 ddr3 的起始地址
    .app_addr_rd_max(ddr3_addr_max[27:0]) , //读 ddr3 的结束地址
    .rd_bust_len    (h_disp[10:3]) ,   //从 ddr3 中读数据时的突发长度
    .app_addr_wr_min(28'd0) ,          //写 ddr3 的起始地址
    .app_addr_wr_max(ddr3_addr_max[27:0]) , //写 ddr3 的结束地址
    .wr_bust_len    (h_disp[10:3]) ,   //从 ddr3 中写数据时的突发长度
    .ddr3_read_valid(1'b1) ,
    .rd_load        (rd_vsync) ,
    .wr_load        (cmos_frame_vsync) ,
    .ddr3_pingpang_en(1'b1) ,
    .rddata         (rd_data)
);

gowin_rpll pll(
    .clkout(memory_clk) ,   //output clkout
    .lock  (pll_lock) ,     //output lock
    .clkin (sys_clk)        //input clkin
);

//LCD 驱动显示模块
lcd_rgb_top u_lcd_rgb_top(
    .sys_clk        (sys_clk ),
    .sys_rst_n      (rst_n ),
    .sys_init_done  (sys_init_done),

    //lcd 接口
    .lcd_id         (lcd_id),       //LCD 屏的 ID 号
    .lcd_hs         (lcd_hs),       //LCD 行同步信号
    .lcd_vs         (lcd_vs),       //LCD 场同步信号
    .lcd_de         (lcd_de),       //LCD 数据输入使能
    .lcd_rgb        (lcd_rgb),      //LCD 颜色数据
    .lcd_bl         (lcd_bl),       //LCD 背光控制信号
    .lcd_rst        (lcd_rst),      //LCD 复位信号
    .lcd_pclk       (lcd_pclk),     //LCD 采样时钟
    .lcd_clk        (lcd_clk),      //LCD 驱动时钟
    //用户接口
    .out_vsync      (rd_vsync),     //lcd 场信号
    .h_disp         (),             //行分辨率
    .v_disp         (),             //场分辨率
    .pixel_xpos     (),
    .pixel_ypos     (),
    .data_in        (rd_data),      //rfifo 输出数据
    .data_req       (rdata_req)     //请求数据输入
);

endmodule
