`timescale 1ns/1ns
module led_twinkle_tb();
    reg Clk;
    reg Reset_n;
    wire Led;

    initial Clk = 1;
    always #10 Clk=!Clk;
    initial begin
        Reset_n = 0;
        #201;
        Reset_n= 1;
        #2000000000;
        $Sstop;
    end
    led_twinkle led_twinkle(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .Led (Led)
        );
endmodule