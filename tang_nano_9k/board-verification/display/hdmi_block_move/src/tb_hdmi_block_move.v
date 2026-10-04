`timescale 1ns/1ns

module tb_hdmi_block_move();

reg sys_clk ;
reg sys_rst_n ;

wire tmds_clk_p ; // TMDS 时钟通道
wire tmds_clk_n ;
wire [2:0] tmds_data_p ; // TMDS 数据通道
wire [2:0] tmds_data_n ;

//GRS 全局复位（高云FPGA仿真原语）
GSR GSR(.GSRI(1'b1));

//时钟与复位初始化
initial begin
    sys_clk = 1'b1;
    sys_rst_n <= 1'b0;
    #201
    sys_rst_n <= 1'b1;
end

//生成50MHz系统时钟，周期20ns
always #10 sys_clk <= ~sys_clk;

//重定义参数：缩短方块移动分频计数，仿真加速，不用等750000周期
defparam hdmi_block_move_inst.u_video_display.DIV_CNT = 75;

//例化顶层待测模块
hdmi_block_move hdmi_block_move_inst(
    .sys_clk    (sys_clk ),
    .sys_rst_n  (sys_rst_n ),

    .tmds_clk_p (tmds_clk_p ), // TMDS 时钟差分正端
    .tmds_clk_n (tmds_clk_n ),
    .tmds_data_p(tmds_data_p), // TMDS 三路数据差分正端
    .tmds_data_n(tmds_data_n)
);

endmodule