`timescale 1ns/1ps

module PLL_tb;

reg clkin;
reg reset;

wire clkout;
wire clkoutp;
wire lock;

// 实例化PLL
Gowin_rPLL uut(
    .clkout(clkout),
    .lock(lock),
    .clkoutp(clkoutp),
    .reset(reset),
    .clkin(clkin)
);

//27MHz输入时钟
initial
    clkin = 0;

always #18.518 clkin = ~clkin;

//复位
initial begin
    reset = 1;
    #100;
    reset = 0;

    #5000;
    $stop;
end

endmodule