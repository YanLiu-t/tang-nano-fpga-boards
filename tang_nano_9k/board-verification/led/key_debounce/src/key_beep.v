module key_beep(
input           sys_clk,
input           sys_rst_n,

input           key_filter, //消抖完成的按键输入
output reg      beep        //蜂鸣器控制输出
);

reg key_filter_d0;
wire neg_key_filter;

//按键信号延迟一拍
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        key_filter_d0 <= 1'b1;
    else
        key_filter_d0 <= key_filter;
end

//下降沿检测：按键按下瞬间产生单周期脉冲
assign neg_key_filter = (~key_filter) & key_filter_d0;

//按键按下，翻转蜂鸣器状态
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        beep <= 1'b1;
    else if(neg_key_filter)
        beep <= ~beep;
end

endmodule