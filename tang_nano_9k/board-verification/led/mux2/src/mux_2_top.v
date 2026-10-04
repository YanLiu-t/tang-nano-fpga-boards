module top(
    input  wire sel,  // 板载S2按键（sel选择端）
    input  wire a,    // 外接引脚控制的a输入
    output wire out   // 板载LED
);

// 2选1多路选择器
mux2_top u_mux2(
    .a(a),
    .b(1'b1),
    .sel(sel),
    .out(out)  
);

endmodule

// 2选1多路选择器子模块
module mux2_top(
    input  wire a,
    input  wire b,
    input  wire sel,
    output wire out
);

assign out = ~(sel ? b : a);

endmodule