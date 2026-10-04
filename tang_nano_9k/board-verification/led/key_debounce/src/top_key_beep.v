module top_key_beep(
input           sys_clk ,    //系统时钟 27MHz
input           sys_rst_n ,  //系统复位，低电平有效

input           key ,        //外部按键输入
output          beep         //蜂鸣器输出，高电平鸣叫有效
);

//parameter define：27MHz 计时20ms，总时钟周期=27000000*0.02=540000
parameter CNT_MAX = 20'd540_000;

//wire define
wire key_filter ; //经过消抖稳定后的按键信号

//例化按键消抖模块，传递自定义消抖计数参数
key_debounce #(
    .CNT_MAX (CNT_MAX)
)u_key_debounce(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .key        (key),
    .key_filter (key_filter)
);

//例化蜂鸣器翻转控制模块
key_beep u_key_beep (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .key_filter (key_filter),
    .beep       (beep)
);

endmodule