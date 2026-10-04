//声明了名称为led的模块，同时表示此模块开始
//此模块有2个输入参数，6个输出参数
module led (
    input sys_clk,          //时钟信号输入
    input sys_rst_n,        //重置信号输入
    output reg [5:0] led    //对应6个LED的输出
);

//两次流水灯变化间的时钟周期数
//由于板载晶振是27MHz，27000000个时钟周期就是1秒    
//当前对应的是0.2秒走一步
parameter delayClockCycles=28'd27000000*0.2;
//时钟周期计数器，用于控制LED亮灭延时，28bit
reg [27:0] counter;
//流水灯的亮灭模式,注意每个LED灯是低电平点亮
parameter ledPattern=6'b000001;//5亮1灭流水灯效果
//parameter ledPattern=6'b111110;//1亮5灭流水灯效果

//用于实现随时钟信号更新时钟周期计数器
//时钟上升沿或重置下降沿触发工作
always @(posedge sys_clk or negedge sys_rst_n) begin
    //如果重置是低电平
    if (!sys_rst_n)
        //时钟计数器清零
        counter <= 28'd0;
    //如果时钟周期计数器小于delayClockCycles则加1  
    else if (counter < delayClockCycles)
        counter <= counter + 1'd1;
    //否则时钟周期计数器归0
    else
        counter <= 28'd0;
end

//用于实现随时钟信号流水灯效果
//时钟上升沿或重置下降沿触发工作
always @(posedge sys_clk or negedge sys_rst_n) begin
    //如果重置是低电平
    if (!sys_rst_n)
        //6个LED灯恢复初始状态
        led <= ledPattern;
    //如果时钟周期计数器等于delayClockCycles
    else if (counter == delayClockCycles)       
        //将led对应的6个bit中的第一个挪到最后
        led[5:0] <= {led[4:0],led[5]};
end

//模块结束
endmodule
