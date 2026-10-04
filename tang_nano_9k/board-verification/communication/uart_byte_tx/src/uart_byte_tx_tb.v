`timescale 1ns / 1ps

module uart_byte_tx_tb();

    reg Clk;
    reg Reset_n;
    reg [7:0]Data;
    wire uart_tx;
    wire Led;

    uart_byte_tx uart_byte_tx(
        .Clk(Clk),
        .Reset_n(Reset_n),
        .Data(Data),
        .uart_tx(uart_tx),
        .Led(Led)
    );

    defparam uart_byte_tx.MCNT_DLY = 500000 - 1;

    initial Clk = 1;
    always #10 Clk = !Clk;

    initial begin
        Reset_n = 0;
        #201;
        Reset_n = 1;
        Data = 8'b0101_0101;
        #30000000;
        Data = 8'b1010_1010;
        #30000000;
        $stop;
    end

endmodule