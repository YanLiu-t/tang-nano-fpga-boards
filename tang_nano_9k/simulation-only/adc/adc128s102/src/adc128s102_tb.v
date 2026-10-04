`timescale 1ns/1ns
`define clock_period 20

module adc128s102_tb;
    reg Clk;
    reg Reset_n;

    reg Conv_Go;
    reg [2:0]Addr;

    wire Conv_Done;
    wire[11:0]Data;

    wire ADC_SCLK;
    wire ADC_CS_N;
    wire ADC_DIN;
    reg ADC_DOUT;

adc128s102 adc128s102(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Conv_Go(Conv_Go),
    .Addr(Addr),
    .Conv_Done(Conv_Done),
    .Data(Data),
    .ADC_SCLK(ADC_SCLK),
    .ADC_CS_N(ADC_CS_N),
    .ADC_DIN(ADC_DIN),
    .ADC_DOUT(ADC_DOUT)
);

initial Clk = 1;
always #(`clock_period/2) Clk = ~Clk;

initial begin
    Reset_n = 0;
    Conv_Go = 0;
    Addr = 0;
    #201;
    Reset_n = 1;
    #200;
    Conv_Go = 1;
    Addr = 3;
    #20;
    Conv_Go = 0;
    wait(!ADC_CS_N);
    //16'h0A58
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB15
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB14
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB13
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB12
    @(negedge ADC_SCLK);
    ADC_DOUT = 1; //DB11
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB10
    @(negedge ADC_SCLK);
    ADC_DOUT = 1; //DB9
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB8
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB7
    @(negedge ADC_SCLK);
    ADC_DOUT = 1; //DB6
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB5
    @(negedge ADC_SCLK);
    ADC_DOUT = 1; //DB4
    @(negedge ADC_SCLK);
    ADC_DOUT = 1; //DB3
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB2
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB1
    @(negedge ADC_SCLK);
    ADC_DOUT = 0; //DB0
    wait(ADC_CS_N);
    #20000;

    Conv_Go = 1;
    Addr = 2;
    #20;
    Conv_Go = 0;
    wait(!ADC_CS_N);
    //16'h0893
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 1;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 1;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 1;
    @(negedge ADC_SCLK);
    ADC_DOUT = 1;
    @(negedge ADC_SCLK);
    ADC_DOUT = 0;
    @(negedge ADC_SCLK);
    ADC_DOUT = 1;
    wait(ADC_CS_N);
    #200;
    #2000;
    $stop;
end

endmodule