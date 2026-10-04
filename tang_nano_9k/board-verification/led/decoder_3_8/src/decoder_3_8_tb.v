`timescale 1ns/1ns
module decoder_3_8_tb();

reg A0;
reg A1;
reg A2;

wire Y0;
wire Y1;
wire Y2;
wire Y3;
wire Y4;
wire Y5;
wire Y6;
wire Y7;

// 例化3-8译码器
decoder_3_8 decoder_3_8_inst0(
    .A0(A0),
    .A1(A1),
    .A2(A2),
    .Y0(Y0),
    .Y1(Y1),
    .Y2(Y2),
    .Y3(Y3),
    .Y4(Y4),
    .Y5(Y5),
    .Y6(Y6),
    .Y7(Y7)
);

// 产生输入激励，间隔20ns遍历全部3位输入组合
initial begin
    A2 = 0;A1 = 0;A0 = 0;
    #20;
    A2 = 0;A1 = 0;A0 = 1;
    #20;
    A2 = 0;A1 = 1;A0 = 0;
    #20;
    A2 = 0;A1 = 1;A0 = 1;
    #20;
    A2 = 1;A1 = 0;A0 = 0;
    #20;
    A2 = 1;A1 = 0;A0 = 1;
    #20;
    A2 = 1;A1 = 1;A0 = 0;
    #20;
    A2 = 1;A1 = 1;A0 = 1;
    #20;
end

endmodule