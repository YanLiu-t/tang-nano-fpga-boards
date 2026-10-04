`timescale 1ns / 1ps
module RAM_test_tb();

reg clka;
reg ena;
reg wea;
reg [15:0] addra;
reg [15:0] dina;
reg clkb;
reg enb;
reg [15:0] addrb;
wire [15:0] doutb;

GSR GSR(.GSRI(1'b1));

// 例化双端口RAM IP
Gowin_SDPB Gowin_SDPB(
    .dout(doutb),      //output [15:0] dout
    .clka(clka),       //input clka
    .cea(ena),         //input cea
    .clkb(clkb),       //input clkb
    .ceb(enb),         //input ceb
    .oce(1),           //input oce
//    .reset(0),         //input reset
    .ada(addra),       //input [15:0] ada
    .din(dina),        //input [15:0] din
    .adb(addrb)        //input [15:0] adb
);

// 生成A口时钟 20ns周期
initial clka = 1;
always #10 clka = ~clka;

// 生成B口时钟 30ns周期
initial clkb = 1;
always #15 clkb = ~clkb;

initial begin
    // 初始化所有信号
    ena = 0;
    wea = 0;
    addra = 0;
    addrb = 0;
    dina = 0;
    enb = 0;
    
    #201;
    // A口顺序写入 0~1023 共1024个地址
    repeat(1024) begin
        ena = 1;
        wea = 1;
        #20;
        dina = dina + 1;
        addra = addra + 1;
    end
    // 写完关闭写使能
    ena = 0;
    wea = 0;
    
    #20000;
    // B口从最后一个地址倒序读出
    addrb = 1023;
    #300;
    repeat(1024) begin
        enb = 1;
        #20;
        addrb = addrb - 1;
    end
    
    #2000;
    $stop;
end

endmodule