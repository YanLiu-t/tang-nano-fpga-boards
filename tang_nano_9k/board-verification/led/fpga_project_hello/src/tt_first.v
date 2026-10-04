module led1(
    input clk,        // 时钟（默认27MHz）
    input reset,      // 低电平复位
    output reg red_led,
    output reg green_led,
    output reg yellow_led
);

// 0.2秒延时，27MHz时钟：27000000 * 0.2 = 5400000
parameter delaytime = 28'd5400000;
// 初始状态：红灯亮，其他灭（100）
parameter ledstyle = 3'b100;

reg [27:0] count;  // 计数器
reg [2:0] light;  // 统一管理3个LED的状态

// 计数器模块：0.2秒计数一次
always @(posedge clk or negedge reset) begin
    if(!reset)
        count <= 28'd0;
    else if(count < delaytime)
        count <= count + 1'd1;
    else
        count <= 28'd0;
end

// LED移位模块：0.2秒移位一次
always @(posedge clk or negedge reset) begin
    if(!reset)
        light <= ledstyle;
    else if(delaytime == count)
        light <= {light[1:0], light[2]};  // 循环左移：100 → 010 → 001 → 100
end

// 把状态分配到三个LED
always @(*) begin
    red_led   = light[2];
    green_led = light[1];
    yellow_led= light[0];
end

endmodule
