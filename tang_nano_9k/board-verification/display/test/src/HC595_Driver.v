/*
================================================================================
模块名称：HC595_Driver
功能：两片74HC595级联驱动，接收并行SEG段码、SEL位选，输出串行时序
输入：
    Clk：27MHz系统时钟
    Reset_n：低电平复位
    SEG[7:0]：数码管段选并行输入
    SEL[7:0]：数码管位选并行输入
输出：
    DIO：595串行数据
    SRCLK：移位寄存器时钟
    RCLK：锁存时钟
    next_digit：握手脉冲，一组16bit发送锁存完成后输出脉冲，通知扫描模块切换数码管
时序说明：先发SEG8bit，再发SEL8bit；SRCLK上升沿移入数据；RCLK上升沿锁存输出
================================================================================
*/
module HC595_Driver(
    input Clk,                      // 系统时钟 27MHz
    input Reset_n,                  // 低电平复位
    input [7:0] SEG,                // 段选信号输入（已取反，共阳极适配）
    input [7:0] SEL,                // 位选信号输入（已取反，共阳极适配）
    output reg DIO,                 // 串行数据输出到74HC595
    output reg SRCLK,               // 移位寄存器时钟（上升沿移入数据）
    output reg RCLK,                // 存储寄存器时钟（上升沿锁存数据）
    output wire next_digit          // 完成一次传输指示脉冲，告诉外层切换下一位
);

    // ==================== 参数定义 ====================
    parameter CLOCK_FREQ = 27_000_000;          // 系统时钟频率 27MHz
    parameter SRCLK_FREQ = 1_000_000;           // 移位时钟频率 1MHz
    parameter MCNT = CLOCK_FREQ / (SRCLK_FREQ * 2) - 1;  // 分频计数器最大值
    
    // ==================== 内部信号 ====================
    reg [7:0] div_cnt;              // 分频计数器，用于产生1MHz移位节拍
    reg [5:0] cnt;                  // 状态计数器：0~32，共33个状态

    // ==================== 时钟分频 ====================
    // 功能：将27MHz时钟分频到1MHz（用于74HC595的移位时钟）
    // 原理：每MCNT+1个时钟周期翻转一次，产生1MHz的移位节拍
    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) 
            div_cnt <= 0;                      // 复位时分频计数器清零
        else if(div_cnt >= MCNT)
            div_cnt <= 0;                      // 计数到最大值，重新开始
        else 
            div_cnt <= div_cnt + 1'b1;         // 正常计数累加
    end

    // ==================== 状态计数器 ====================
    // 功能：0~32循环计数，控制74HC595的数据传输时序
    // 时序分配：
    //   cnt 0~15：发送SEG[7:0]（16个状态，每bit占2个状态）
    //   cnt 16~31：发送SEL[7:0]（16个状态）
    //   cnt 32：产生锁存脉冲RCLK
    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) 
            cnt <= 0;                          // 复位时状态清零
        else if(div_cnt == MCNT) begin         // 分频节拍到达，状态前进
            if(cnt >= 6'd32)
                cnt <= 0;                      // 计数到32，循环回到0
            else
                cnt <= cnt + 1'b1;             // 状态计数器+1
        end
    end

    // ==================== 完成指示信号 ====================
    // 功能：当状态数到32（锁存完成）的瞬间，产生一个高电平脉冲
    // 用途：通知外层模块可以更新SEG/SEL数据，切换到下一位数码管
    assign next_digit = (div_cnt == MCNT) && (cnt == 6'd32);

    // ==================== 74HC595时序控制 ====================
    // 功能：按照74HC595的时序要求，串行发送16位数据
    // 数据格式：先发SEG[7:0]（段码），再发SEL[7:0]（位选）
    // 时序说明：
    //   1. 在SRCLK上升沿，DIO上的数据被移入移位寄存器
    //   2. 数据发送完成后，RCLK上升沿将移位寄存器数据锁存到输出
    //   3. 两个74HC595级联：第一个接收SEG，第二个接收SEL
    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) begin 
            DIO <= 1'b0; SRCLK <= 1'b0; RCLK <= 1'b0;  // 复位所有输出引脚为低电平
        end else begin
            case(cnt)
                // ---- 发送SEG[7:0]（段码数据） ----
                0:  begin DIO <= SEG[7]; SRCLK <= 1'b0; RCLK <= 1'b0; end  // 准备SEG[7]数据到DIO
                1:  begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[7]
                2:  begin DIO <= SEG[6]; SRCLK <= 1'b0; end                 // 准备SEG[6]数据
                3:  begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[6]
                4:  begin DIO <= SEG[5]; SRCLK <= 1'b0; end                 // 准备SEG[5]
                5:  begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[5]
                6:  begin DIO <= SEG[4]; SRCLK <= 1'b0; end                 // 准备SEG[4]
                7:  begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[4]
                8:  begin DIO <= SEG[3]; SRCLK <= 1'b0; end                 // 准备SEG[3]
                9:  begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[3]
                10: begin DIO <= SEG[2]; SRCLK <= 1'b0; end                 // 准备SEG[2]
                11: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[2]
                12: begin DIO <= SEG[1]; SRCLK <= 1'b0; end                 // 准备SEG[1]
                13: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[1]
                14: begin DIO <= SEG[0]; SRCLK <= 1'b0; end                 // 准备SEG[0]
                15: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEG[0]
                
                // ---- 发送SEL[7:0]（位选数据） ----
                16: begin DIO <= SEL[7]; SRCLK <= 1'b0; end                 // 准备SEL[7]
                17: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[7]
                18: begin DIO <= SEL[6]; SRCLK <= 1'b0; end                 // 准备SEL[6]
                19: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[6]
                20: begin DIO <= SEL[5]; SRCLK <= 1'b0; end                 // 准备SEL[5]
                21: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[5]
                22: begin DIO <= SEL[4]; SRCLK <= 1'b0; end                 // 准备SEL[4]
                23: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[4]
                24: begin DIO <= SEL[3]; SRCLK <= 1'b0; end                 // 准备SEL[3]
                25: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[3]
                26: begin DIO <= SEL[2]; SRCLK <= 1'b0; end                 // 准备SEL[2]
                27: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[2]
                28: begin DIO <= SEL[1]; SRCLK <= 1'b0; end                 // 准备SEL[1]
                29: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[1]
                30: begin DIO <= SEL[0]; SRCLK <= 1'b0; end                 // 准备SEL[0]
                31: begin SRCLK <= 1'b1; end                                 // SRCLK上升沿移入SEL[0]
                
                // ---- 锁存数据 ----
                32: begin RCLK <= 1'b1; end                                  // RCLK上升沿锁存，595输出更新
                
                default: begin DIO <= 1'b0; SRCLK <= 1'b0; RCLK <= 1'b0; end // 异常安全状态，全部输出拉低
            endcase
        end
    end
endmodule