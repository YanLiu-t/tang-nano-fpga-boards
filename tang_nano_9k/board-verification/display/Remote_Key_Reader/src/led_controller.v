module led_controller(
    input clk,             // 27MHz 系统时钟
    input rst_n,           // 复位键
    input [7:0] key_val,   // 从解码模块传来的键值
    input key_valid,       // 收到新按键时的脉冲标志
    
    output reg red_led,    // 红灯输出 (高电平点亮)
    output reg green_led   // 绿灯输出 (高电平点亮)
);

    // 300ms 计时器 (27MHz * 0.3s = 8_100_000) - 控制闪烁节奏
    parameter TIME_300MS = 8_100_000;
    reg [23:0] timer;
    wire tick = (timer == TIME_300MS - 1);

    // 状态机编码
    parameter S_OFF        = 3'd0;
    parameter S_RED_ON     = 3'd1;
    parameter S_GREEN_ON   = 3'd2;
    parameter S_RED_BLINK  = 3'd3;
    parameter S_GREEN_BLINK= 3'd4;
    parameter S_ALT_BLINK  = 3'd5;

    reg [2:0] state;         // 当前状态
    reg [1:0] target_blinks; // 目标闪烁次数 (1~3次)
    reg [1:0] blink_cnt;     // 已经完成的闪烁次数
    reg led_status;          // 控制闪烁时的亮(1)/灭(0)翻转

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer <= 0;
            state <= S_OFF;
            target_blinks <= 0;
            blink_cnt <= 0;
            led_status <= 0;
        end else if (key_valid) begin
            // 收到新按键时，重置所有状态并马上点亮
            timer <= 0;
            blink_cnt <= 0;
            led_status <= 1; 
            
            // ★ 这里填入你测出的按键码 ★
            case (key_val)
                8'h19: begin state <= S_RED_ON; end                           // 按键 1：红常亮
                8'h31: begin state <= S_GREEN_ON; end                         // 按键 2：绿常亮
                8'hbd: begin state <= S_RED_BLINK;   target_blinks <= 1; end  // 按键 3：红闪 1 下
                8'h11: begin state <= S_GREEN_BLINK; target_blinks <= 1; end  // 按键 4：绿闪 1 下
                8'h39: begin state <= S_RED_BLINK;   target_blinks <= 2; end  // 按键 5：红闪 2 下
                8'hb5: begin state <= S_GREEN_BLINK; target_blinks <= 2; end  // 按键 6：绿闪 2 下
                8'h85: begin state <= S_RED_BLINK;   target_blinks <= 3; end  // 按键 7：红闪 3 下
                8'hA5: begin state <= S_GREEN_BLINK; target_blinks <= 3; end  // 按键 8：绿闪 3 下
                8'h95: begin state <= S_ALT_BLINK; end                        // 按键 9：交替闪烁
                default: ; // 其他按键保持当前状态
            endcase
            
        end else begin
            // 只有在需要闪烁的状态下，计时器才工作
            if (state != S_OFF && state != S_RED_ON && state != S_GREEN_ON) begin
                if (tick) begin
                    timer <= 0;
                    if (state == S_RED_BLINK || state == S_GREEN_BLINK) begin
                        if (led_status == 1'b1) begin
                            led_status <= 1'b0; // 亮了 300ms 后，熄灭
                        end else begin
                            // 熄灭了 300ms 后，判断是否闪够了次数
                            if (blink_cnt + 1 >= target_blinks) begin
                                state <= S_OFF; // 闪够了，进入全灭状态
                            end else begin
                                blink_cnt <= blink_cnt + 1; // 没闪够，次数+1
                                led_status <= 1'b1;         // 再次点亮
                            end
                        end
                    end else if (state == S_ALT_BLINK) begin
                        led_status <= ~led_status; // 交替模式永远在翻转
                    end
                end else begin
                    timer <= timer + 1;
                end
            end else begin
                timer <= 0; // 常亮或常灭时，计时器归零待命
            end
        end
    end

    // 将状态映射到物理 LED 引脚上
    always @(*) begin
        red_led = 1'b0;
        green_led = 1'b0;
        case (state)
            S_RED_ON:      red_led = 1'b1;
            S_GREEN_ON:    green_led = 1'b1;
            S_RED_BLINK:   red_led = led_status;
            S_GREEN_BLINK: green_led = led_status;
            S_ALT_BLINK: begin
                red_led = led_status;
                green_led = ~led_status;
            end
            default: ; // S_OFF 状态默认全灭
        endcase
    end
endmodule