`timescale 1ns / 1ns

module sync_fifo_test();
reg Rst;
reg Clk;
reg [7:0]din;
reg wr_en;
reg rd_en;
wire [7:0]dout;
wire full;
wire almost_full;
wire empty;
wire almost_empty;
wire [7:0]data_count;

sync_fifo sync_fifo(
    .Data(din),        //input [7:0] Data
    .Clk(Clk),         //input Clk
    .WrEn(wr_en),      //input WrEn
    .RdEn(rd_en),      //input RdEn
    .Reset(Rst),       //input Reset
    .Wnum(data_count), //output [8:0] Wnum
    .Almost_Empty(almost_empty), //output Almost_Empty
    .Almost_Full(almost_full),   //output Almost_Full
    .Q(dout),          //output [7:0] Q
    .Empty(empty),     //output Empty
    .Full(full)        //output Full
);

// 生成时钟激励
initial Clk = 1;
always #10 Clk = ~Clk;

initial begin
    Rst    = 1'b1;
    wr_en  = 1'b0;
    rd_en  = 1'b0;
    din    = 8'hff;
    #21;
    Rst = 1'b0;

    //写操作，从0到255，共256个数据
    while(full == 1'b0)
    begin
        @(posedge Clk);
        #1;
        wr_en = 1'b1;
        din   = din + 1'b1;
    end
    wr_en = 1'b0;

    //读操作，读256次
    while(empty == 1'b0)
    begin
        @(posedge Clk);
        #1;
        rd_en = 1'b1;
    end
    rd_en = 1'b0;

    //再次复位测试
    #200;
    Rst = 1'b1;
    #21;
    Rst = 1'b0;

    #2000;
    $stop;
end

endmodule