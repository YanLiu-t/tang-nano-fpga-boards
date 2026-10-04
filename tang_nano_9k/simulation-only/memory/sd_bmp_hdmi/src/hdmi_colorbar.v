module hdmi_colorbar(
input sys_clk,
input sys_rst_n,

output tmds_clk_p,      // TMDS 时钟差分正端
output tmds_clk_n,      // TMDS 时钟差分负端
output [2:0] tmds_data_p,// 三路TMDS数据差分正端
output [2:0] tmds_data_n // 三路TMDS数据差分负端
);

//wire define
wire pixel_clk;        // 基础像素时钟
wire pixel_clk_5x;     // 5倍频高速串行时钟
wire lock;             // PLL锁定标志
wire rst_n;            // 系统同步复位

wire [10:0] pixel_xpos_w; // 当前像素横坐标
wire [10:0] pixel_ypos_w; // 当前像素纵坐标
wire [23:0] pixel_data_w; // 输出RGB888像素数据

wire video_hs;         // 行同步信号
wire video_vs;         // 场同步信号
wire video_de;         // 数据有效使能
wire [23:0] video_rgb; // 最终输出RGB图像数据

//*****************************************************
//** main code
//*****************************************************
// 复位：系统复位 + PLL锁定，只有时钟稳定后才释放复位
assign rst_n = sys_rst_n & lock;

//例化 PLL IP 核，输入系统时钟，输出5倍像素时钟
rpll_pixel_clk_5x rpll_pixel_clk_5x(
.clkout (pixel_clk_5x),
.lock   (lock),
.reset  (~sys_rst_n),
.clkin  (sys_clk)
);

//例化5分频模块，从5倍频时钟分出基础像素时钟
clk_div5 clk_div5(
.clkout  (pixel_clk),
.hclkin  (pixel_clk_5x),
.resetn  (rst_n)
);

//例化视频时序驱动：生成行场同步、坐标、DE信号
video_driver u_video_driver(
.pixel_clk   (pixel_clk),
.sys_rst_n   (rst_n),

.video_hs    (video_hs),
.video_vs    (video_vs),
.video_de    (video_de),
.video_rgb   (video_rgb),
.data_req    (),

.pixel_xpos  (pixel_xpos_w),
.pixel_ypos  (pixel_ypos_w),
.pixel_data  (pixel_data_w)
);

//例化画面生成模块：彩条图案输出
video_display u_video_display(
.pixel_clk   (pixel_clk),
.sys_rst_n   (rst_n),

.pixel_xpos  (pixel_xpos_w),
.pixel_ypos  (pixel_ypos_w),
.pixel_data  (pixel_data_w)
);

//例化HDMI/DVI顶层发送器：RGB转差分TMDS信号
dvi_transmitter_top u_rgb2dvi_0(
.pclk        (pixel_clk),
.pclk_x5     (pixel_clk_5x),
.reset_n     (rst_n),

.video_din   (video_rgb),
.video_hsync (video_hs),
.video_vsync (video_vs),
.video_de    (video_de),

.tmds_clk_p  (tmds_clk_p),
.tmds_clk_n  (tmds_clk_n),
.tmds_data_p (tmds_data_p),
.tmds_data_n (tmds_data_n)
);

endmodule