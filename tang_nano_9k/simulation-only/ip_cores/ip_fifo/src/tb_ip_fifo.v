`timescale 1ns / 1ps   // 仿真时间单位1ns，时间精度1ps
module tb_ip_fifo();

// Gowin专用全局复位GSR，仿真必须例化，否则部分IP复位异常
GSR GSR(.GSRI(1'b1));

// 参数：输入系统时钟周期 20ns，对应50MHz时钟
parameter CLK_PERIOD = 20;

// 仿真激励信号，reg类型，只能在tb里使用
reg sys_clk;
reg sys_rst_n;

// 初始化：先拉低复位200ns，再释放复位
initial begin
    sys_clk    = 1'b0;
    sys_rst_n  = 1'b0;
    #200
    sys_rst_n  = 1'b1;
end

// 循环生成系统时钟：每半个周期翻转电平
always #(CLK_PERIOD / 2) sys_clk = ~sys_clk;

// 例化顶层FIFO工程模块，把仿真激励信号接入顶层
ip_fifo u_ip_fifo(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n)
);

endmodule