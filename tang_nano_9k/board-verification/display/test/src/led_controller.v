// 模块名称：led_controller
// 功能描述：基于按键输入控制红绿双色LED的多种显示模式，包括常亮、指定次数闪烁和交替闪烁。所有按键事件由外部解码模块提供键值和有效脉冲，本模块据此切换工作状态。
//   1. 闪烁节奏由300ms定时器控制（27MHz时钟下计数8_100_000个周期）。
//   2. 对于“闪烁N次”的需求（N=1~3），使用目标次数寄存器(target_blinks)和已闪次数计数器(blink_cnt)，
//      每次完整亮灭算一次，达到目标后自动回到全灭状态。
//   3. 交替闪烁模式(S_ALT_BLINK)不受次数限制，持续翻转红绿灯状态，直到收到新按键。
//   4. 按键有效信号(key_valid)到来时立即重置定时器和闪烁计数，并切换至新状态，保证响应实时性。
// 接口时序：
//   - clk：27MHz系统时钟，所有时序逻辑上升沿触发。
//   - rst_n：异步复位，低电平有效，复位后所有状态归零（全灭、定时器清零、闪烁计数清零）。
//   - key_val[7:0]：按键扫描码，由解码模块给出，仅在key_valid为高时有效。
//   - key_valid：脉冲信号，高电平持续一个时钟周期，表示key_val上的是新按键值。
//   - red_led / green_led：输出高电平点亮对应LED，组合逻辑根据当前状态和led_status实时更新。

module led_controller(
    input clk,             // 27MHz 系统时钟
    input rst_n,           // 异步复位信号，低电平有效
    input [7:0] key_val,   // 从解码模块传来的按键扫描码（PS/2或USB HID码）
    input key_valid,       // 脉冲标志，为高时表示key_val有效，持续一个时钟周期
    
    output reg red_led,    // 红灯输出，高电平点亮
    output reg green_led   // 绿灯输出，高电平点亮
);

    // 300ms 定时器参数：27MHz时钟下计数 27,000,000 * 0.3 = 8,100,000 个周期
    // 因此计数值从0到8_100_000-1即为300ms
    parameter TIME_300MS = 8_100_000;
    
    // 定时器计数器，宽度24位可容纳8_100_000（约2^23），故选用[23:0]
    reg [23:0] timer;
    
    // tick信号：组合逻辑，当timer计数到最后一个周期时产生一个高电平脉冲
    // 该脉冲有效时间仅一个时钟周期（因为timer在下一个clk会被复位）
    wire tick = (timer == TIME_300MS - 1);

    // ---------- 状态机编码 ----------
    parameter S_OFF        = 3'd0;  // 全灭状态
    parameter S_RED_ON     = 3'd1;  // 红灯常亮
    parameter S_GREEN_ON   = 3'd2;  // 绿灯常亮
    parameter S_RED_BLINK  = 3'd3;  // 红灯闪烁（受目标次数控制）
    parameter S_GREEN_BLINK= 3'd4;  // 绿灯闪烁（受目标次数控制）
    parameter S_ALT_BLINK  = 3'd5;  // 红绿交替闪烁（无限循环）

    reg [2:0] state;         // 当前状态寄存器
    reg [1:0] target_blinks; // 目标闪烁次数，取值范围1~3（由按键键值决定）
    reg [1:0] blink_cnt;     // 已经完成的闪烁次数（每亮+灭算一次）
    reg led_status;          // 当前LED亮灭状态，用于闪烁控制：1表示亮，0表示灭

    // -----------------------------------------------------------------
    // 时序逻辑：状态机转移、定时器计数、闪烁计数及led_status管理
    // 异步复位优先，随后处理按键有效事件，最后处理定时器超时事件
    // -----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位：所有寄存器清零，LED全灭
            timer <= 0;
            state <= S_OFF;
            target_blinks <= 0;
            blink_cnt <= 0;
            led_status <= 0;
        end else if (key_valid) begin
            // 检测到新按键，立即响应：重置定时器、闪烁计数，并置led_status为1（亮）
            // 这样做的目的是让闪烁或交替模式从“亮”状态开始，而非从灭开始，更符合直觉
            timer <= 0;
            blink_cnt <= 0;
            led_status <= 1; 
            
            // 根据键值(key_val)跳转到对应状态，并设置目标闪烁次数（如果需要）
            // 注意：此处键值为实际测试所得（例如键盘扫描码），用户可根据需要修改
            case (key_val)
                8'h19: begin state <= S_RED_ON; end                           // 按键 1：红灯常亮
                8'h31: begin state <= S_GREEN_ON; end                         // 按键 2：绿灯常亮
                8'hbd: begin state <= S_RED_BLINK;   target_blinks <= 1; end  // 按键 3：红灯闪烁1次
                8'h11: begin state <= S_GREEN_BLINK; target_blinks <= 1; end  // 按键 4：绿灯闪烁1次
                8'h39: begin state <= S_RED_BLINK;   target_blinks <= 2; end  // 按键 5：红灯闪烁2次
                8'hb5: begin state <= S_GREEN_BLINK; target_blinks <= 2; end  // 按键 6：绿灯闪烁2次
                8'h85: begin state <= S_RED_BLINK;   target_blinks <= 3; end  // 按键 7：红灯闪烁3次
                8'hA5: begin state <= S_GREEN_BLINK; target_blinks <= 3; end  // 按键 8：绿灯闪烁3次
                8'h95: begin state <= S_ALT_BLINK; end                        // 按键 9：红绿交替闪烁（无限）
                default: ; // 其他按键保持当前状态不变（不做任何响应）
            endcase
            
        end else begin
            // 无新按键时，根据当前状态决定定时器是否工作，以及进行闪烁控制
            
            // 只有处于闪烁或交替状态时，定时器才递增；常亮/全灭状态下定时器保持0
            if (state != S_OFF && state != S_RED_ON && state != S_GREEN_ON) begin
                
                if (tick) begin
                    // 当定时器达到300ms时（产生tick脉冲），定时器归零，并处理状态转移
                    timer <= 0;
                    
                    // 情况1：单一颜色闪烁（红或绿）
                    if (state == S_RED_BLINK || state == S_GREEN_BLINK) begin
                        if (led_status == 1'b1) begin
                            // 当前是亮状态，300ms后转为灭
                            led_status <= 1'b0;
                        end else begin
                            // 当前是灭状态，表示完成了一次“亮+灭”循环，判定是否达到目标次数
                            if (blink_cnt + 1 >= target_blinks) begin
                                // 已达到目标次数，转入全灭状态
                                state <= S_OFF;
                                // 注意：这里不改变led_status，但组合逻辑会根据state输出全灭
                            end else begin
                                // 未达到目标次数，闪烁次数+1，并重新点亮
                                blink_cnt <= blink_cnt + 1;
                                led_status <= 1'b1;
                            end
                        end
                    end else if (state == S_ALT_BLINK) begin
                        // 情况2：交替闪烁模式，每次300ms将led_status取反
                        // 从而实现红绿交替点亮（一个亮则另一个灭）
                        led_status <= ~led_status;
                    end
                    
                end else begin
                    // 未到300ms，定时器继续累加
                    timer <= timer + 1;
                end
                
            end else begin
                // 处于常亮或全灭状态时，定时器归零（不工作）
                timer <= 0;
            end
        end
    end

    // -----------------------------------------------------------------
    // 组合逻辑：根据当前状态和led_status，决定两个LED引脚的实际输出
    // 此处采用always @(*)纯组合电路，无时序依赖，确保输出实时跟随状态变化
    // -----------------------------------------------------------------
    always @(*) begin
        // 默认赋值：两个LED均为低电平（灭）
        red_led = 1'b0;
        green_led = 1'b0;
        
        case (state)
            S_RED_ON:      red_led = 1'b1;                 // 红灯常亮，绿灯灭
            S_GREEN_ON:    green_led = 1'b1;               // 绿灯常亮，红灯灭
            S_RED_BLINK:   red_led = led_status;           // 红灯跟随led_status，绿灯灭
            S_GREEN_BLINK: green_led = led_status;         // 绿灯跟随led_status，红灯灭
            S_ALT_BLINK: begin
                red_led = led_status;                      // 红灯取led_status
                green_led = ~led_status;                   // 绿灯取反，实现交替
            end
            default: ; // S_OFF 或未定义状态，均保持默认全灭
        endcase
    end
    
endmodule