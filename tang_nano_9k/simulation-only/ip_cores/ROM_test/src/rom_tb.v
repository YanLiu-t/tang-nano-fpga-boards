`timescale 1ns/1ps
module rom_tb;

reg clk;
reg [11:0]addr;
wire [9:0]dout;

    Gowin_pROM your_instance_name(
        .dout(dout), //output [9:0] dout
        .clk(clk), //input clk
        .oce(oce), //input oce
        .ce(ce), //input ce
        .reset(reset), //input reset
        .ad(ad) //input [9:0] ad
    );


    GSR GSR(.GSRI(1'b1));
    initial clk=1;
    always #10 clk=~clk;

    initial begin
        addr=100;
        #501;
        repeat(2000)begin
            addr=addr+1;
            #20;
        end
        #2000;
        $stop;
    end
endmodule