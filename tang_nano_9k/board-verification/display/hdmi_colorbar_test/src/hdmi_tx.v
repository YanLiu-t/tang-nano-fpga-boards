module hdmi_tx(
    input  wire         clk_pixel,
    input  wire         clk_tmds,
    input  wire         rst_n,
    input  wire [23:0]  video_data,
    input  wire         video_hsync,
    input  wire         video_vsync,
    input  wire         video_de,
    output wire         hdmi_clk_p,
    output wire         hdmi_clk_n,
    output wire         hdmi_d0_p,
    output wire         hdmi_d0_n,
    output wire         hdmi_d1_p,
    output wire         hdmi_d1_n,
    output wire         hdmi_d2_p,
    output wire         hdmi_d2_n
);

    wire [9:0] tmds_red, tmds_green, tmds_blue;

    TMDS_encoder enc_r(
        .clk      (clk_pixel),
        .rst_n    (rst_n),
        .data_in  (video_data[23:16]),
        .ctrl     (2'b00),
        .de       (video_de),
        .data_out (tmds_red)
    );

    TMDS_encoder enc_g(
        .clk      (clk_pixel),
        .rst_n    (rst_n),
        .data_in  (video_data[15:8]),
        .ctrl     ({video_vsync, video_hsync}),
        .de       (video_de),
        .data_out (tmds_green)
    );

    TMDS_encoder enc_b(
        .clk      (clk_pixel),
        .rst_n    (rst_n),
        .data_in  (video_data[7:0]),
        .ctrl     (2'b00),
        .de       (video_de),
        .data_out (tmds_blue)
    );

    ELVDS_OBUF obuf_clk(
        .I  (~clk_pixel),
        .O  (hdmi_clk_p),
        .OB (hdmi_clk_n)
    );

    wire d0_serial;
    OSER10 ser0(
        .Q    (d0_serial),
        .D0   (tmds_blue[0]), .D1   (tmds_blue[1]), .D2   (tmds_blue[2]),
        .D3   (tmds_blue[3]), .D4   (tmds_blue[4]), .D5   (tmds_blue[5]),
        .D6   (tmds_blue[6]), .D7   (tmds_blue[7]), .D8   (tmds_blue[8]),
        .D9   (tmds_blue[9]),
        .PCLK (clk_pixel),
        .FCLK (clk_tmds),
        .RESET(~rst_n)
    );
    ELVDS_OBUF obuf0(
        .I  (d0_serial),
        .O  (hdmi_d0_p),
        .OB (hdmi_d0_n)
    );

    wire d1_serial;
    OSER10 ser1(
        .Q    (d1_serial),
        .D0   (tmds_green[0]), .D1   (tmds_green[1]), .D2   (tmds_green[2]),
        .D3   (tmds_green[3]), .D4   (tmds_green[4]), .D5   (tmds_green[5]),
        .D6   (tmds_green[6]), .D7   (tmds_green[7]), .D8   (tmds_green[8]),
        .D9   (tmds_green[9]),
        .PCLK (clk_pixel),
        .FCLK (clk_tmds),
        .RESET(~rst_n)
    );
    ELVDS_OBUF obuf1(
        .I  (d1_serial),
        .O  (hdmi_d1_p),
        .OB (hdmi_d1_n)
    );

    wire d2_serial;
    OSER10 ser2(
        .Q    (d2_serial),
        .D0   (tmds_red[0]), .D1   (tmds_red[1]), .D2   (tmds_red[2]),
        .D3   (tmds_red[3]), .D4   (tmds_red[4]), .D5   (tmds_red[5]),
        .D6   (tmds_red[6]), .D7   (tmds_red[7]), .D8   (tmds_red[8]),
        .D9   (tmds_red[9]),
        .PCLK (clk_pixel),
        .FCLK (clk_tmds),
        .RESET(~rst_n)
    );
    ELVDS_OBUF obuf2(
        .I  (d2_serial),
        .O  (hdmi_d2_p),
        .OB (hdmi_d2_n)
    );

endmodule