module uart_byte_rx_test(
    Clk,
    Reset_n,
    uart_rx,
    Led,
    Rx_Data
);

input Clk;
input Reset_n;
input uart_rx;
output reg Led;
output [7:0]Rx_Data;

wire Rx_Done;

uart_byte_rx uart_byte_rx(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .uart_rx(uart_rx),
    .Rx_Done(Rx_Done),
    .Rx_Data(Rx_Data)
);
defparam uart_byte_rx.BAUD = 115200;

always@(posedge Clk or negedge Reset_n)
if(!Reset_n)
    Led <= 0;
else if(Rx_Done)
    Led <= ~Led;

endmodule