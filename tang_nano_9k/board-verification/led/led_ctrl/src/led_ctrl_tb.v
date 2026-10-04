`timescale 1ns/1ns

module led_ctrl_tb();
 reg Clk;
 reg Reset_n;
 reg [7:0]SW;
 wire led;
 initial Clk=1;
 always #10 Clk=!Clk;
    initial begin
        Reset_n=0;
        SW=8'b1010_1001;
        #201;
        Reset_n=1;
        #40000000;
        $stop;
     end

    led_ctrl3 led_ctrl3(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .SW(SW),
    .Led(Led)
);
    defparam led_ctrl3.MCNT0=12500-1;
    defparam led_ctrl3.MCNT2=50000-1;
endmodule