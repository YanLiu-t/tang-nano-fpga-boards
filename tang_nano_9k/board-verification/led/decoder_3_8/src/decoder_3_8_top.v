module dec38_key(
    input wire S1, // P88 输入C
    input wire S2, // P87 输入B
    output wire LED0,LED1,LED2,LED3,LED4,LED5 // 6颗板载LED，Y0~Y5
);
// 第三位输入A固定为0，简化测试，只测000~110组合
wire A = 1'b0;
wire C = S1;
wire B = S2;

// 3-8译码逻辑，低电平输出
wire [7:0] Y;
assign Y[0] = ~(~C & ~B & ~A);
assign Y[1] = ~(~C & ~B &  A);
assign Y[2] = ~(~C &  B & ~A);
assign Y[3] = ~(~C &  B &  A);
assign Y[4] = ~( C & ~B & ~A);
assign Y[5] = ~( C & ~B &  A);
assign Y[6] = ~( C &  B & ~A);
assign Y[7] = ~( C &  B &  A);

// 绑定板载LED，LED低电平点亮
assign LED0 = Y[0];
assign LED1 = Y[1];
assign LED2 = Y[2];
assign LED3 = Y[3];
assign LED4 = Y[4];
assign LED5 = Y[5];
endmodule