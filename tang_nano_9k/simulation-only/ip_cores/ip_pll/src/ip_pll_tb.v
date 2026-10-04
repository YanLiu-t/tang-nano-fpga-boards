`timescale 1ns / 1ps


module tb_ip_pll;

// 端口定义
reg         sys_clk;
reg         sys_rst_n;
wire        clk_100m;
wire        clk_100m_180deg;
wire        clk_33m;
wire        clk_25m;

// 实例化PLL顶层
ip_pll u_ip_pll(
    .sys_clk         (sys_clk),
    .sys_rst_n       (sys_rst_n),
    .clk_100m        (clk_100m),
    .clk_100m_180deg(clk_100m_180deg),
    .clk_33m          (clk_33m),
    .clk_25m          (clk_25m)
);

// 输入时钟：周期27ns
initial begin
    sys_clk = 1'b0;
    forever #(27/2) sys_clk = ~sys_clk;
end

// 复位产生：先拉低200ns释放复位
initial begin
    sys_rst_n = 1'b0;
    #200
    sys_rst_n = 1'b1;
end

// 仿真时长控制，5us停止仿真
initial begin
    #5000
    $display("仿真完成，结束");
    $finish;
end

// 打印波形（Modelsim/iverilog 可导出波形）
initial begin
    $dumpfile("pll_wave.vcd");
    $dumpvars(0, tb_ip_pll);
end

endmodule