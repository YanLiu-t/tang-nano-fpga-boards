module hdmi_block_move(
input sys_clk,
input sys_rst_n,

output tmds_clk_p, // TMDS 时钟通道
output tmds_clk_n,
output [2:0] tmds_data_p, // TMDS 数据通道
output [2:0] tmds_data_n
);

//wire define
wire pixel_clk;
wire pixel_clk_5x;
wire rst_n;
wire lock;

wire [10:0] pixel_xpos_w;
wire [10:0] pixel_ypos_w;
wire [23:0] pixel_data_w;

wire video_hs;
wire video_vs;
wire video_de;
wire [23:0] video_rgb;

//*****************************************************
//** main code
//*****************************************************
assign rst_n = sys_rst_n & lock;

//例化 PLL IP 核
rpll_pixel_clk_5x rpll_pixel_clk_5x(
    .clkout (pixel_clk_5x),
    .lock   (lock ),
    .reset  (~sys_rst_n ),
    .clkin  (sys_clk )
);

clk_div5 clk_div5(
    .clkout  (pixel_clk ),
    .hclkin  (pixel_clk_5x),
    .resetn  (rst_n )
);

//例化视频显示驱动模块
video_driver u_video_driver(
    .pixel_clk (pixel_clk ),
    .sys_rst_n  (rst_n ),

    .video_hs   (video_hs ),
    .video_vs   (video_vs ),
    .video_de   (video_de ),
    .video_rgb  (video_rgb ),
    .data_req   (),

    .pixel_xpos(pixel_xpos_w),
    .pixel_ypos(pixel_ypos_w),
    .pixel_data(pixel_data_w)
);

//例化视频显示模块
video_display u_video_display(
    .pixel_clk  (pixel_clk ),
    .sys_rst_n   (rst_n ),

    .pixel_xpos (pixel_xpos_w),
    .pixel_ypos (pixel_ypos_w),
    .pixel_data (pixel_data_w)
);

//例化 HDMI 驱动模块
dvi_transmitter_top u_rgb2dvi_0(
    .pclk       (pixel_clk ),
    .pclk_x5    (pixel_clk_5x),
    .reset_n    (rst_n ),

    .video_din  (video_rgb),
    .video_hsync(video_hs),
    .video_vsync(video_vs),
    .video_de   (video_de),

    .tmds_clk_p (tmds_clk_p),
    .tmds_clk_n (tmds_clk_n),
    .tmds_data_p(tmds_data_p),
    .tmds_data_n(tmds_data_n)
);

endmodule