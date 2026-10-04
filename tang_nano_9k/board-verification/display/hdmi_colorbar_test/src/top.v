module top(
    input  wire clk,          // 52脚，27MHz晶振
    output wire hdmi_clk_p,   // 24脚
    output wire hdmi_clk_n,   // 23脚
    output wire hdmi_d0_p,    // 27脚
    output wire hdmi_d0_n,    // 26脚
    output wire hdmi_d1_p,    // 30脚
    output wire hdmi_d1_n,    // 29脚
    output wire hdmi_d2_p,    // 34脚
    output wire hdmi_d2_n     // 33脚
);

    wire clk_pixel;    // 像素时钟 27MHz
    wire clk_tmds;     // 5倍频 135MHz
    wire locked;       // PLL锁定信号

    // 像素时钟直接用电振27MHz
    assign clk_pixel = clk;

    // PLL: 27MHz → 135MHz（用于OSER10串行化）
    Gowin_rPLL u_pll(
        .clkin  (clk),
        .clkout (clk_tmds),
        .lock   (locked)
    );

    // 视频信号
    wire [23:0] video_data;
    wire video_hsync;
    wire video_vsync;
    wire video_de;

    // 720×480 三色彩条生成
    hdmi_display u_display(
        .clk_pixel   (clk_pixel),
        .rst_n       (locked),
        .video_data  (video_data),
        .video_hsync (video_hsync),
        .video_vsync (video_vsync),
        .video_de    (video_de)
    );

    // HDMI 发送
    hdmi_tx u_hdmi(
        .clk_pixel   (clk_pixel),
        .clk_tmds    (clk_tmds),
        .rst_n       (locked),
        .video_data  (video_data),
        .video_hsync (video_hsync),
        .video_vsync (video_vsync),
        .video_de    (video_de),
        .hdmi_clk_p  (hdmi_clk_p),
        .hdmi_clk_n  (hdmi_clk_n),
        .hdmi_d0_p   (hdmi_d0_p),
        .hdmi_d0_n   (hdmi_d0_n),
        .hdmi_d1_p   (hdmi_d1_p),
        .hdmi_d1_n   (hdmi_d1_n),
        .hdmi_d2_p   (hdmi_d2_p),
        .hdmi_d2_n   (hdmi_d2_n)
    );

endmodule