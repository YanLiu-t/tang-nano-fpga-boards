module led_alarm #(parameter L_TIME = 25'd25_000_000 // 控制 led 闪烁时间（此为 500ms）
)(
//system clock
input clk ,         // 时钟信号
input rst_n ,       // 复位信号

//led interface
output [3:0] led ,  // LED 灯

//user interface
input error_flag    // 错误标志
);

//reg define
reg led_t ;         // 使用的 led 灯
reg [24:0] led_cnt; // led 计数

//*****************************************************
//** main code
//*****************************************************

//led 输出
assign led = {3'b000,led_t};

//错误标志为 1 时 led 闪烁，否则，LED0 常亮
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        led_cnt <= 25'd0;
        led_t <= 1'b0;
    end
    else begin
        if(error_flag) begin // 读到的值错误
            if(led_cnt == L_TIME - 1'b1) begin// 数据错误时 LED 灯每隔 L_TIME 时间闪烁
                led_cnt <= 25'd0;
                led_t <= ~led_t;
            end
            else
                led_cnt <= led_cnt + 25'd1;
        end
        else begin // 读完且读到的值正确
            led_cnt <= 25'd0;
            led_t <= 1'b1; // led 灯常亮
        end
    end
end

endmodule
