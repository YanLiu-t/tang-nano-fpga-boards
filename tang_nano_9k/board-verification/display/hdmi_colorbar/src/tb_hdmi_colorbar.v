`timescale 1ns/1ns
module tb_hdmi_colorbar();

reg sys_clk ;
reg sys_rst_n ;

wire tmds_clk_p ;      // TMDS 差分时钟正极
wire tmds_clk_n ;      // TMDS 差分时钟负极
wire [2:0] tmds_data_p;// 三路TMDS差分数据正极
wire [2:0] tmds_data_n;// 三路TMDS差分数据负极

// 高云FPGA全局复位原语，仿真时关闭硬件全局复位
GSR GSR(.GSRI(1'b1));

// 复位初始化
initial begin
    sys_clk = 1'b1;
    sys_rst_n <= 1'b0;
    #201        // 保持低复位201ns
    sys_rst_n <= 1'b1;
end

// 生成系统时钟：周期20ns，对应50MHz输入晶振
always #10 sys_clk <= ~sys_clk;

// 例化HDMI彩条顶层待测模块
hdmi_colorbar hdmi_colorbar_inst(
.sys_clk     (sys_clk),
.sys_rst_n   (sys_rst_n),

.tmds_clk_p  (tmds_clk_p),
.tmds_clk_n  (tmds_clk_n),
.tmds_data_p (tmds_data_p),
.tmds_data_n (tmds_data_n)
);

endmodule