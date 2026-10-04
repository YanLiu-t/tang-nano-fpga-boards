module HC595_Driver_tb;

reg Clk;
reg Reset_n;
reg [7:0] SEL;
reg [7:0] SEG;
wire DIO;
wire SRCLK;
wire RCLK;

HC595_Driver u_HC595_Driver(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .SEG(SEG),
    .SEL(SEL),
    .DIO(DIO),
    .SRCLK(SRCLK),
    .RCLK(RCLK)
);

initial Clk = 1;
always #10 Clk = ~Clk;

initial begin
    Reset_n = 0;
    SEL = 8'b0000_0001;
    SEG = 8'b0101_0101;
    #201;
    Reset_n = 1;
    #5000;
    SEL = 8'b0000_0010;
    SEG = 8'b1010_1010;
    #5000;
    SEL = 8'b1010_0101;
    SEG = 8'b0000_1101;
    #5000;
    $stop;
end

endmodule