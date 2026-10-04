module swi_led(
input clk ,
input rst_n ,
input [7:0] swi ,
output reg[7:0] led
);

//*****************************************************
//** main code
//*****************************************************

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)
        led <= 8'b0000_0000;
    else
        led <= swi;
end

endmodule
