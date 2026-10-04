`timescale 1ns / 1ns

module breath_led_tb;

    // 1. 信号声明
    reg Clk;
    reg Reset_n;
    wire led;

    // 2. 实例化被测模块 (UUT)
    // 注意：这里使用 defparam 覆盖原代码中的参数，以便快速仿真
    breath_led #(
        .MCNT_us(54 - 1),      // 保持原值或根据需要调整
        .MCNT_ms_s(1000 - 1)   // 保持原值或根据需要调整
    ) u_breath_led (
        .Clk(Clk),
        .Reset_n(Reset_n),
        .led(led)
    );

    // 3. 产生时钟信号 (假设系统时钟为 50MHz, 周期 20ns)
    initial begin
        Clk = 0;
        forever #18 Clk = ~Clk; 
    end

    // 4. 产生复位信号
    initial begin
        Reset_n = 0;
        #100;       // 保持复位状态 100ns
        Reset_n = 1; // 释放复位
    end



endmodule