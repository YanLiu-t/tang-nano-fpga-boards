module key_led(
    //输入端口
    input           sys_clk,
    input           sys_rst_n,
    input           key,    //修改：单按键
    //输出端口
    output reg [3:0] led 
);

//参数：27MHz晶振，计时0.5s
parameter CNT_MAX = 25'd13500000;

//寄存器定义
reg [24:0] cnt;
reg [1:0]  led_flag;

//计数器 0.5秒计时
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt <= 25'd0;
    else if(cnt < (CNT_MAX - 25'd1))
        cnt <= cnt + 25'd1;
    else
        cnt <= 25'd0;
end

//LED状态切换标志位
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        led_flag <= 2'd0;
    else if(cnt == (CNT_MAX - 25'd1)) 
        led_flag <= led_flag + 2'd1;
    else
        led_flag <= led_flag;
end 

//LED控制：单按键逻辑，按住流水，松开全灭
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        led <= 4'b0000;
    else begin
        if(key == 1'b1) begin
            //按键松开，LED全部熄灭
            led <= 4'b0000;
        end
        else begin
            //按键长按，正向流水灯（原版key0逻辑）
            if(led_flag == 2'd0)
                led <= 4'b0001;
            else if(led_flag == 2'd1)
                led <= 4'b0010;
            else if(led_flag == 2'd2)
                led <= 4'b0100;
            else
                led <= 4'b1000; 
        end
    end
end 

endmodule