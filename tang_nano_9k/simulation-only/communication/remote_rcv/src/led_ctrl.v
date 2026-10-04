module led_ctrl(
input sys_clk ,        //系统时钟
input sys_rst_n ,      //系统复位信号，低电平有效

input repeat_en ,      //重复码触发信号
output reg led         //LED 灯
);

//reg define
reg repeat_en_d0 ;     //repeat_en 信号打拍采沿
reg repeat_en_d1 ;
reg [22:0] led_cnt ;   //LED 灯计数器,用于控制 LED 灯亮灭

//wire define
wire pos_repeat_en;

//*****************************************************
//** main code
//*****************************************************

assign pos_repeat_en = ~repeat_en_d1 & repeat_en_d0;

//repeat_en 信号打拍采沿
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        repeat_en_d0 <= 1'b0;
        repeat_en_d1 <= 1'b0;
    end
    else begin
        repeat_en_d0 <= repeat_en;
        repeat_en_d1 <= repeat_en_d0;
    end
end 

//单次重复码:亮 80ms 灭 20ms
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        led <= 1'b0;
    else if (pos_repeat_en)          //收到重复码上升沿，LED点亮
        led <= 1'b1;
    else if (led_cnt < 23'd1_000_000)//计数低于100万，熄灭
        led <= 1'b0;
    else
        led <= led;
end

always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        led_cnt <= 23'd0;
    else if(pos_repeat_en)
        led_cnt <= 23'd5_000_000;  //总计时5ms
    else if(led_cnt != 23'd0)
        led_cnt <= led_cnt - 23'd1;
    else
        led_cnt <= led_cnt;
end 

endmodule