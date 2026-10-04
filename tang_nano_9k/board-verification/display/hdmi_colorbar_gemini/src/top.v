//========================================================
//  IP: Gowin_rPLL (保持原样)
//========================================================
module Gowin_rPLL (clkout, lock, clkin);

output clkout;
output lock;
input clkin;

wire clkoutp_o;
wire clkoutd_o;
wire clkoutd3_o;
wire gw_gnd;

assign gw_gnd = 1'b0;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp_o),
    .CLKOUTD(clkoutd_o),
    .CLKOUTD3(clkoutd3_o),
    .RESET(gw_gnd),
    .RESET_P(gw_gnd),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.IDIV_SEL = 0;
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.FBDIV_SEL = 4;
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.ODIV_SEL = 4;
defparam rpll_inst.PSDA_SEL = "0000";
defparam rpll_inst.DYN_DA_EN = "false";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW1NR-9C";

endmodule //Gowin_rPLL


//========================================================
//  视频时序发生器 (保持原样)
//========================================================
module hdmi_display(
    input  wire         clk_pixel,
    input  wire         rst_n,
    output reg  [23:0]  video_data,
    output reg          video_hsync,
    output reg          video_vsync,
    output reg          video_de
);

    localparam H_TOTAL  = 858;
    localparam H_ACTIVE = 720;
    localparam H_SYNC   = 62;
    localparam H_FRONT  = 16;

    localparam V_TOTAL  = 525;
    localparam V_ACTIVE = 480;
    localparam V_SYNC   = 6;
    localparam V_FRONT  = 9;

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 0;
                else
                    v_cnt <= v_cnt + 1;
            end else begin
                h_cnt <= h_cnt + 1;
            end
        end
    end

    wire h_active = (h_cnt < H_ACTIVE);
    wire v_active = (v_cnt < V_ACTIVE);
    wire h_sync   = (h_cnt >= (H_ACTIVE + H_FRONT)) && (h_cnt < (H_ACTIVE + H_FRONT + H_SYNC));
    wire v_sync   = (v_cnt >= (V_ACTIVE + V_FRONT)) && (v_cnt < (V_ACTIVE + V_FRONT + V_SYNC));

    always @(posedge clk_pixel) begin
        video_hsync <= ~h_sync;
        video_vsync <= ~v_sync;
        video_de    <= h_active && v_active;
    end

    wire [1:0] bar = (h_cnt < 240) ? 2'd0 : (h_cnt < 480) ? 2'd1 : 2'd2;

    always @(posedge clk_pixel) begin
        case (bar)
            2'd0: video_data <= {8'hFF, 8'h00, 8'h00}; // 红
            2'd1: video_data <= {8'h00, 8'hFF, 8'h00}; // 绿
            2'd2: video_data <= {8'h00, 8'h00, 8'hFF}; // 蓝
        endcase
    end

endmodule


//========================================================
//  HDMI 发送模块 (已修复：时钟引脚通过 OSER10 发送，确保相位对齐)
//========================================================
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

    // 【新增】时钟也走 OSER10 串行器，发送固定的 10'b1111100000 
    // 这样能保证时钟和数据的延迟路径完全一致
    wire clk_serial;
    OSER10 ser_clk(
        .Q    (clk_serial),
        .D0   (1'b0), .D1   (1'b0), .D2   (1'b0), .D3   (1'b0), .D4   (1'b0),
        .D5   (1'b1), .D6   (1'b1), .D7   (1'b1), .D8   (1'b1), .D9   (1'b1),
        .PCLK (clk_pixel),
        .FCLK (clk_tmds),
        .RESET(~rst_n)
    );
    ELVDS_OBUF obuf_clk(
        .I  (clk_serial),
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


//========================================================
//  TMDS 编码器 (已修复：增加 de_reg 和 ctrl_reg，解决流水线数据错位)
//========================================================
module TMDS_encoder(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  data_in,
    input  wire [1:0]  ctrl,
    input  wire        de,
    output reg  [9:0]  data_out
);

    function [3:0] count_ones;
        input [7:0] d;
        integer i;
        begin
            count_ones = 0;
            for (i = 0; i < 8; i = i + 1)
                count_ones = count_ones + d[i];
        end
    endfunction

    wire [3:0] n1_d = count_ones(data_in);
    reg [3:0] disparity;
    reg [8:0] q_m;
    
    // 【新增】打一拍寄存器，保证控制信号和算出来的 q_m 在同一周期
    reg       de_reg;
    reg [1:0] ctrl_reg;

    wire [3:0] n1_q_m;
    assign n1_q_m = count_ones(q_m[7:0]);

    always @(posedge clk) begin
        de_reg   <= de;
        ctrl_reg <= ctrl;

        if (n1_d > 4 || (n1_d == 4 && data_in[0] == 0)) begin
            q_m[0] <= data_in[0];
            q_m[1] <= q_m[0] ^~ data_in[1];
            q_m[2] <= q_m[1] ^~ data_in[2];
            q_m[3] <= q_m[2] ^~ data_in[3];
            q_m[4] <= q_m[3] ^~ data_in[4];
            q_m[5] <= q_m[4] ^~ data_in[5];
            q_m[6] <= q_m[5] ^~ data_in[6];
            q_m[7] <= q_m[6] ^~ data_in[7];
            q_m[8] <= 0;
        end else begin
            q_m[0] <= data_in[0];
            q_m[1] <= q_m[0] ^ data_in[1];
            q_m[2] <= q_m[1] ^ data_in[2];
            q_m[3] <= q_m[2] ^ data_in[3];
            q_m[4] <= q_m[3] ^ data_in[4];
            q_m[5] <= q_m[4] ^ data_in[5];
            q_m[6] <= q_m[5] ^ data_in[6];
            q_m[7] <= q_m[6] ^ data_in[7];
            q_m[8] <= 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 10'b1101010100;
            disparity <= 0;
        end else if (!de_reg) begin // 使用打拍后的 de_reg
            case (ctrl_reg)         // 使用打拍后的 ctrl_reg
                2'b00:   data_out <= 10'b1101010100;
                2'b01:   data_out <= 10'b0010101011;
                2'b10:   data_out <= 10'b0101010100;
                default: data_out <= 10'b1010101011;
            endcase
            disparity <= 0;
        end else begin
            if (disparity == 0 || n1_q_m == 4) begin
                if (q_m[8]) begin
                    data_out <= {~q_m[8], q_m[8], q_m[7:0]};
                    disparity <= disparity + (n1_q_m - 4);
                end else begin
                    data_out <= {q_m[8], q_m[8], ~q_m[7:0]};
                    disparity <= disparity + (4 - n1_q_m);
                end
            end else begin
                if ((disparity > 0 && n1_q_m > 4) || (disparity < 0 && n1_q_m < 4)) begin
                    data_out <= {1'b1, q_m[8], ~q_m[7:0]};
                    disparity <= disparity + (q_m[8] ? (n1_q_m - 4) : (4 - n1_q_m));
                end else begin
                    data_out <= {1'b0, q_m[8], q_m[7:0]};
                    disparity <= disparity + (q_m[8] ? (4 - n1_q_m) : (n1_q_m - 4));
                end
            end
        end
    end

endmodule


//========================================================
//  顶层模块 (保持原样)
//========================================================
module top(
    input  wire clk,          
    output wire hdmi_clk_p,   
    output wire hdmi_clk_n,   
    output wire hdmi_d0_p,    
    output wire hdmi_d0_n,    
    output wire hdmi_d1_p,    
    output wire hdmi_d1_n,    
    output wire hdmi_d2_p,    
    output wire hdmi_d2_n     
);

    wire clk_pixel;    
    wire clk_tmds;     
    wire locked;       

    assign clk_pixel = clk;

    Gowin_rPLL u_pll(
        .clkin  (clk),
        .clkout (clk_tmds),
        .lock   (locked)
    );

    wire [23:0] video_data;
    wire video_hsync;
    wire video_vsync;
    wire video_de;

    hdmi_display u_display(
        .clk_pixel   (clk_pixel),
        .rst_n       (locked),
        .video_data  (video_data),
        .video_hsync (video_hsync),
        .video_vsync (video_vsync),
        .video_de    (video_de)
    );

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