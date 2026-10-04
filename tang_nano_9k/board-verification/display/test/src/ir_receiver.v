//====================================================================================
// 模块名称：ir_receiver 红外NEC解码模块
// 模块用途：对VS1838B红外接收头输出波形进行采样，解析NEC红外遥控协议，输出按键键值与接收有效标志
// 设计思路：对外部红外信号打拍消除亚稳态；生成10us计时基准；测量下降沿间隔区分引导码、逻辑0、逻辑1；
//           使用移位寄存器缓存32位NEC帧数据，接收完成后提取命令字节输出按键值。
//====================================================================================
module ir_receiver(
    input clk,            // 27MHz 系统时钟
    input rst_n,          // 低电平复位，复位后内部全部状态清零
    input ir_in,          // 红外接收头输入信号，外部NEC红外波形
    output reg [7:0] key_val,  // 解码输出8位红外按键键值
    output reg key_valid       // 解码成功脉冲标志，高电平代表key_val数据有效
);

    // 1.同步打拍与下降沿检测，消除外部输入亚稳态
    reg [2:0] ir_sr;
    always @(posedge clk) ir_sr <= {ir_sr[1:0], ir_in}; // 三级寄存器对外部红外信号同步打拍
    wire ir_fall = (ir_sr[2:1] == 2'b10); // 检测信号下降沿：1变0，捕获红外波形跳变点

    // 2.产生10us基准计时滴答，用于测量NEC码高低电平时间
    reg [8:0] tick_cnt;
    wire tick = (tick_cnt == 269); // 27MHz计数270个周期，生成10us计时脉冲
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick_cnt <= 0;        // 复位，计时计数器清零
        else if (tick) tick_cnt <= 0;     // 计满10us，计数器清零重新计时
        else tick_cnt <= tick_cnt + 1;    // 时钟上升沿，计数器累加
    end

    // 3.测量两次下降沿之间的时间，单位10us，用来区分引导码、逻辑0、逻辑1
    reg [15:0] time_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) time_cnt <= 0;                 // 复位，时间测量计数器清零
        else if (ir_fall) time_cnt <= 0;           // 检测到下降沿，重置计时，开始下一段测量
        else if (tick && time_cnt < 16'hFFFF) time_cnt <= time_cnt + 1; // 每10us计数器加1
    end

    // 4.NEC协议解码状态相关寄存器
    reg [5:0] bit_cnt;        // 已经接收的数据bit计数，最多接收32bit
    reg [31:0] shift_reg;     // 移位寄存器，存放NEC完整32位接收数据

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 0;         // 复位，接收bit数清零
            key_valid <= 0;       // 复位，数据有效标志清零
            key_val <= 0;         // 复位，输出键值清零
            shift_reg <= 0;       // 复位，32位接收移位寄存器清零
        end else begin
            key_valid <= 0; // 默认拉低有效脉冲，只在接收完成时输出高脉冲
            if (ir_fall) begin // 每当捕获红外信号下降沿，判断这段波形含义
                // 判断时间间隔，设置阈值宽容度，兼容实际硬件误差
                if (time_cnt > 1200 && time_cnt < 1500) begin
                    // 识别引导码，13.5ms左右，一帧红外数据的起始标志
                    bit_cnt <= 0; // 收到引导码，重置bit计数，准备接收32位数据
                end else if (time_cnt > 80 && time_cnt < 150) begin
                    // 识别逻辑0，时间约1.12ms
                    shift_reg <= {1'b0, shift_reg[31:1]}; // 将0移入移位寄存器
                    bit_cnt <= bit_cnt + 1;               // 接收bit计数+1
                end else if (time_cnt > 180 && time_cnt < 280) begin
                    // 识别逻辑1，时间约2.25ms
                    shift_reg <= {1'b1, shift_reg[31:1]}; // 将1移入移位寄存器
                    bit_cnt <= bit_cnt + 1;               // 接收bit计数+1
                end

                // 接收满32bit，完成一帧NEC数据接收
                if (bit_cnt == 31 && time_cnt > 80) begin
                    // NEC32bit格式：[反命令,命令,反地址,地址]
                    key_val <= shift_reg[23:16]; // 提取8位命令字节作为按键键值
                    key_valid <= 1'b1;           // 拉高有效脉冲，通知顶层模块读取键值
                end
            end
        end
    end

endmodule