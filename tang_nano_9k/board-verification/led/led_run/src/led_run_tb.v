`timescale 1ns/1ns
module led_run_tb();
    reg Clk;
    reg Reset_n;
    wire [5:0]Led;

    initial Clk = 1;
    always #10 Clk=!Clk;
    initial begin
        Reset_n = 0;
        #201;
        Reset_n= 1;
        #40000000;
        $Sstop;
    end
    led_run led_run(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .Led (Led)
        );
endmodule