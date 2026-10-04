module uart_byte_rx_tb();
reg Clk;
reg Reset_n;
reg uart_rx;
wire Rx_Done;
wire [7:0]Rx_Data;

// 例化接收模块
uart_byte_rx uart_byte_rx(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .uart_rx(uart_rx),
    .Rx_Done(Rx_Done),
    .Rx_Data(Rx_Data)
);

// 生成50MHz时钟，周期20ns
initial Clk = 1;
always #10 Clk = ~Clk;

initial begin
    Reset_n = 0;
    uart_rx = 1;
    #201;
    Reset_n = 1;
    #200;

    // 第一帧数据 0x55 = 8'b01010101
    uart_rx = 0; #(5208*20);//起始位
    uart_rx = 1; #(5208*20);//bit0
    uart_rx = 0; #(5208*20);//bit1
    uart_rx = 1; #(5208*20);//bit2
    uart_rx = 0; #(5208*20);//bit3
    uart_rx = 1; #(5208*20);//bit4
    uart_rx = 0; #(5208*20);//bit5
    uart_rx = 1; #(5208*20);//bit6
    uart_rx = 0; #(5208*20);//bit7
    uart_rx = 1; #(5208*20);//停止位
    #(5208*20*10);

    // 第二帧数据 0xAA = 8'b10101010
    uart_rx = 0; #(5208*20);//起始位
    uart_rx = 0; #(5208*20);//bit0
    uart_rx = 1; #(5208*20);//bit1
    uart_rx = 0; #(5208*20);//bit2
    uart_rx = 1; #(5208*20);//bit3
    uart_rx = 0; #(5208*20);//bit4
    uart_rx = 1; #(5208*20);//bit5
    uart_rx = 0; #(5208*20);//bit6
    uart_rx = 1; #(5208*20);//bit7
    uart_rx = 1; #(5208*20);//停止位
    #(5208*20*10);

    // 第三帧数据 0x0F = 8'b00001111
    uart_rx = 0; #(5208*20);//起始位
    uart_rx = 1; #(5208*20);//bit0
    uart_rx = 1; #(5208*20);//bit1
    uart_rx = 1; #(5208*20);//bit2
    uart_rx = 1; #(5208*20);//bit3
    uart_rx = 0; #(5208*20);//bit4
    uart_rx = 0; #(5208*20);//bit5
    uart_rx = 0; #(5208*20);//bit6
    uart_rx = 0; #(5208*20);//bit7
    uart_rx = 1; #(5208*20);//停止位
    #(5208*20*10);

    $stop;
end

endmodule