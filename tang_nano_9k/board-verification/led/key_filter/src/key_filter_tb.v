`timescale 1ns/1ns
module key_filter_tb;
    reg Clk;
    reg Reset_n;
    reg Key;
    wire Key_P_Flag;
    wire Key_R_Flag;
    wire key_state;

key_filter key_filter_inst(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Key(Key),
    .Key_P_Flag(Key_P_Flag),
    .Key_R_Flag(Key_R_Flag),
    .key_state(key_state)
);

initial Clk= 1;
always#10 Clk = ~Clk;

initial begin
    Reset_n = 0;
    Key = 1;
    #201;
    Reset_n = 1;

    //第一次按下测试
    //空闲稳定
    Key = 1; #100000000;//空闲 稳定 100ms

    //按下抖动
    Key = 0; #18000000;//按下 抖动 低18ms
    Key = 1; #2000000;//按下 抖动 高2ms
    Key = 0; #1000000;//按下 抖动 低1ms
    Key = 1; #200000;//按下 抖动 高0.2ms
    Key = 0; #20000000;//按下 稳定 低20ms

    //按下稳定
    Key = 0; #50000000;//按下 稳定 继续50ms

    //释放抖动
    Key = 1; #2000000;//释放 抖动 高2ms
    Key = 0; #1000000;//释放 抖动 低1ms
    Key = 1; #20000000;//释放 稳定 高20ms

    //释放稳定
    Key = 1; #50000000;//释放 稳定 继续50ms

    //第二次按下测试
    //空闲稳定
    Key = 1; #100000000;//释放 稳定 继续100ms
end
endmodule