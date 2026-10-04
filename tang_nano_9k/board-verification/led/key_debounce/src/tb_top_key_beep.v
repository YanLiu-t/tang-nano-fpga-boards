`timescale 1ns / 1ns //仿真单位/仿真精度

module tb_top_key_beep();

//parameter define
parameter CLK_PERIOD = 37;       // 27MHz时钟：约37ns一个周期，精准匹配硬件
parameter CNT_MAX    = 20'd10;    // 仿真消抖计数(仅仿真用，很小，仿真跑得快)

//reg define
reg sys_clk;
reg sys_rst_n;
reg key;

//wire define
wire beep;

//信号初始化、复位+模拟按键抖动
initial begin
    sys_clk    <= 1'b0;
    sys_rst_n  <= 1'b0;
    key        <= 1'b1;
    #200
    sys_rst_n  <= 1'b1;   //释放复位
    
    //模拟多次按键抖动（短时间高低来回跳=机械抖动）
    #20  key <= 1'b0;
    #20  key <= 1'b1;
    #50  key <= 1'b0; 
    #40  key <= 1'b1;
    #20  key <= 1'b0;
    #300 key <= 1'b1;     //这次低电平持续时间足够长，消抖生效
    #50  key <= 1'b0;
    #40  key <= 1'b1;
    #300 key <= 1'b0;
    #1000 $finish;        //仿真结束，不然无限跑
end

//循环生成系统时钟
always #(CLK_PERIOD/2) sys_clk = ~sys_clk;

//例化顶层模块，传入仿真专用小计数CNT_MAX
top_key_beep #(
    .CNT_MAX (CNT_MAX) 
)u_top_key_beep(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .key        (key),
    .beep       (beep)
);

endmodule