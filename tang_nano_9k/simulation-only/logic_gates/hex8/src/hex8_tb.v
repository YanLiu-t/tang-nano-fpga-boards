`timescale 1ns/1ns
module hex8_tb();
reg Clk;
reg Reset_n;
reg [31:0]Disp_Data;
wire [7:0]SEL;
wire [7:0]SEG;

hex8 hex8(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Disp_Data(Disp_Data),
    .SEL(SEL),
    .SEG(SEG)
);

initial Clk = 1;
always#10 Clk = ~Clk;

initial begin
    Reset_n = 0;
    Disp_Data = 32'h12345678;
    #201;
    Reset_n = 1;
    #20000000;  //延时10ms
    Disp_Data = 32'h9abcdef0;
    #20000000;  //延时10ms
    $stop;
end

endmodule