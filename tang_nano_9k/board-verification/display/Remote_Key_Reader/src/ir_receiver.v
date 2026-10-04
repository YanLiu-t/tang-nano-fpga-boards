module ir_receiver(
    input clk,            // 27MHz 系统时钟
    input rst_n,          // 低电平复位
    input ir_in,          // 红外接收头输入
    output reg [7:0] key_val,  // 提取出来的8位按键值
    output reg key_valid       // 成功接收的脉冲标志
);

    // 1. 同步与边沿检测 (消除亚稳态)
    reg [2:0] ir_sr;
    always @(posedge clk) ir_sr <= {ir_sr[1:0], ir_in};
    wire ir_fall = (ir_sr[2:1] == 2'b10); // 检测到下降沿

    // 2. 产生 10us 的基准时钟滴答 (27MHz / 270 = 100kHz)
    reg [8:0] tick_cnt;
    wire tick = (tick_cnt == 269);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick_cnt <= 0;
        else if (tick) tick_cnt <= 0;
        else tick_cnt <= tick_cnt + 1;
    end

    // 3. 计算两次下降沿之间的时间 (单位：10us)
    reg [15:0] time_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) time_cnt <= 0;
        else if (ir_fall) time_cnt <= 0;
        else if (tick && time_cnt < 16'hFFFF) time_cnt <= time_cnt + 1;
    end

    // 4. NEC 协议解码状态机
    reg [5:0] bit_cnt;
    reg [31:0] shift_reg; // 暂存32位数据

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 0;
            key_valid <= 0;
            key_val <= 0;
            shift_reg <= 0;
        end else begin
            key_valid <= 0; // 默认清零脉冲
            if (ir_fall) begin
                // 判断时间间隔 (带有一定宽容度)
                if (time_cnt > 1200 && time_cnt < 1500) begin
                    // 收到引导码 (13.5ms = 1350 * 10us)
                    bit_cnt <= 0;
                end else if (time_cnt > 80 && time_cnt < 150) begin
                    // 收到逻辑 '0' (1.12ms = 112 * 10us)
                    shift_reg <= {1'b0, shift_reg[31:1]};
                    bit_cnt <= bit_cnt + 1;
                end else if (time_cnt > 180 && time_cnt < 280) begin
                    // 收到逻辑 '1' (2.25ms = 225 * 10us)
                    shift_reg <= {1'b1, shift_reg[31:1]};
                    bit_cnt <= bit_cnt + 1;
                end

                // 接收满32位数据，输出按键值
                if (bit_cnt == 31 && time_cnt > 80) begin
                    // NEC协议的命令码在第16~23位
                    key_val <= {shift_reg[22:15], 1'b0}; // 修复位移偏差，提取8位Cmd
                    // 准确提取：shift_reg中存的是 [~cmd, cmd, ~addr, addr]
                    key_val <= shift_reg[23:16];
                    key_valid <= 1'b1;
                end
            end
        end
    end
endmodule