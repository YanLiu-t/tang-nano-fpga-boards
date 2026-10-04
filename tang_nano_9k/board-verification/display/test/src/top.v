//顶层模块设计思路
//核心思想：模块化集成，信号统一管理
//1. 功能分工
// 红外解码模块：负责接收解析遥控信号
// 显示控制模块：负责数码管内容显示
// HC595驱动模块：负责串行数据传输
// LED控制模块：负责状态指示
//2. 数据流
// 红外信号 -> 解码成键值 -> 锁存保持 -> 送显示和LED控制
//3. 关键处理
// 用latched_key锁存键值，保证显示稳定不闪烁
// 统一时钟和复位，保证各模块同步工作
module top(
    input sys_clk,    // 27MHz 开发板时钟输入
    input sys_rst_n,  // 复位按键输入(低电平有效)
    input ir_in,      // 红外接收头 VS1838B 的 OUT 脚输入
    
    // HC595 输出接口
    output hc595_dio,    // HC595 串行数据输出
    output hc595_srclk,  // HC595 移位寄存器时钟输出
    output hc595_rclk,   // HC595 锁存时钟输出
    
    // 两个 LED 指示灯输出 
    output red_led,    // 红色 LED 指示灯输出
    output green_led   // 绿色 LED 指示灯输出
);

    wire [7:0] w_key_val;    // 红外解码得到的 8 位键值数据
    wire w_key_valid;        // 红外解码有效标志(单周期脉冲)
    wire [7:0] w_seg;        // 数码管段选信号(8 位)
    wire [7:0] w_sel;        // 数码管位选信号(8 位)

    reg [7:0] latched_key;   // 锁存后的键值寄存器
    always @(posedge sys_clk or negedge sys_rst_n) begin  // 时序逻辑：时钟上升沿或复位下降沿触发
        if (!sys_rst_n)                      // 如果复位信号有效(低电平)
            latched_key <= 8'h00;            // 键值寄存器清零
        else if (w_key_valid)                // 否则如果有新的有效按键数据
            latched_key <= w_key_val;        // 锁存新的键值
    end

    // 1：红外解码模块实例化
    ir_receiver u_ir_rx(
        .clk        (sys_clk),       // 系统时钟连接
        .rst_n      (sys_rst_n),     // 复位信号连接
        .ir_in      (ir_in),         // 红外输入信号连接
        .key_val    (w_key_val),     // 输出解码键值
        .key_valid  (w_key_valid)    // 输出解码有效标志
    );

    // 2：数码管显示控制模块实例化
    display_ctrl u_disp(
        .clk        (sys_clk),       // 系统时钟连接
        .rst_n      (sys_rst_n),     // 复位信号连接
        .key_val    (latched_key),   // 输入锁存后的键值
        .SEG        (w_seg),         // 输出段选信号
        .SEL        (w_sel)          // 输出位选信号
    );

    // 3：HC595 驱动模块实例化
    HC595_Driver u_hc595(
        .Clk        (sys_clk),       // 系统时钟连接
        .Reset_n    (sys_rst_n),     // 复位信号连接
        .SEG        (w_seg),         // 输入段选信号
        .SEL        (w_sel),         // 输入位选信号
        .DIO        (hc595_dio),     // 输出串行数据到 HC595
        .SRCLK      (hc595_srclk),   // 输出移位时钟到 HC595
        .RCLK       (hc595_rclk)     // 输出锁存时钟到 HC595
    );

    // LED 状态机控制模块实例化
    led_controller u_led(
        .clk        (sys_clk),       // 系统时钟连接
        .rst_n      (sys_rst_n),     // 复位信号连接
        .key_val    (w_key_val),     // 直接接入解码出来的键值数据
        .key_valid  (w_key_valid),   // 接入按键有效脉冲信号
        .red_led    (red_led),       // 输出控制红色 LED
        .green_led  (green_led)      // 输出控制绿色 LED
    );

endmodule