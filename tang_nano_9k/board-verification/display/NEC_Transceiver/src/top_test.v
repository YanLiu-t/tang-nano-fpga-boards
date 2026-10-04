module top_test(
    input clk,
    output ir_tx // 绑定你的发射引脚
);
    // 直接强制给高电平，把三极管完全导通
    assign ir_tx = 1'b1; 
endmodule