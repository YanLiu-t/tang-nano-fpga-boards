`timescale 1ns / 1ps

module async_fifo_tb;

//时钟信号
reg         WrClk;
reg         RdClk;

//写时钟域信号
reg         WrReset;
reg         WrEn;
reg [7:0]   Data;
wire [8:0]  Wnum;
wire        Almost_Full;

//读时钟域信号
reg         RdReset;
reg         RdEn;
wire [15:0] Q;
wire [8:0]  Rnum;
wire        Almost_Empty;
wire        Empty;

//例化FIFO，完全匹配IP端口名
async_fifo u_async_fifo(
    .Data(Data),
    .WrReset(WrReset),
    .RdReset(RdReset),
    .WrClk(WrClk),
    .RdClk(RdClk),
    .WrEn(WrEn),
    .RdEn(RdEn),
    .Wnum(Wnum),
    .Rnum(Rnum),
    .Almost_Empty(Almost_Empty),
    .Almost_Full(Almost_Full),
    .Q(Q),
    .Empty(Empty)
);

//产生写时钟 50MHz 周期20ns
initial begin
    WrClk = 0;
    forever #10 WrClk = ~WrClk;
end

//产生读时钟 50MHz 周期20ns
initial begin
    RdClk = 0;
    forever #10 RdClk = ~RdClk;
end

//复位+读写激励
initial begin
    //复位阶段
    WrReset = 1;
    RdReset = 1;
    WrEn = 0;
    RdEn = 0;
    Data = 8'd0;
    #50;
    WrReset = 0;
    RdReset = 0;
    #20;

    //连续写入数据
    repeat(300) begin
        @(posedge WrClk);
        WrEn = 1;
        Data = Data + 1'b1;
    end
    @(posedge WrClk);
    WrEn = 0;

    #100;
    //开始读取数据
    repeat(150) begin
        @(posedge RdClk);
        RdEn = 1;
    end
    @(posedge RdClk);
    RdEn = 0;

    #1000;
    $stop;
end

endmodule