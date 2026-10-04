`timescale 1ns/1ns
module flow_led_tb();
reg Clk;
reg Reset_n;
wire[3:0] led;

initial begin
Clk<=0;
Reset_n<=0;
#200
Reset_n<=1'b1;
#20
$finish;
end

flow_led flow_led_tb(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .led(led)

);




always #10 Clk=~Clk;

endmodule