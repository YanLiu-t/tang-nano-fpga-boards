module ir_receiver(
    input clk,            
    input rst_n,          
    input ir_in,          
    output reg [7:0] key_val,  
    output reg key_valid       
);

    // 同步与边沿检测 (增加复位，消除上电毛刺)
    reg [2:0] ir_sr;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) ir_sr <= 3'b111;
        else ir_sr <= {ir_sr[1:0], ir_in};
    end
    wire ir_fall = (ir_sr[2:1] == 2'b10); 

    // 产生 10us 的滴答 (27MHz / 270)
    reg [8:0] tick_cnt;
    wire tick = (tick_cnt == 269);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick_cnt <= 0;
        else if (tick) tick_cnt <= 0;
        else tick_cnt <= tick_cnt + 1;
    end

    // 计算两次下降沿之间的时间
    reg [15:0] time_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) time_cnt <= 0;
        else if (ir_fall) time_cnt <= 0;
        else if (tick && time_cnt < 16'hFFFF) time_cnt <= time_cnt + 1;
    end

    // NEC 解码状态机
    reg [5:0] bit_cnt;
    reg [31:0] shift_reg; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 0;
            key_valid <= 0;
            key_val <= 0;
            shift_reg <= 0;
        end else begin
            key_valid <= 0; // 默认拉低脉冲
            if (ir_fall) begin
                if (time_cnt > 1200 && time_cnt < 1500) begin
                    bit_cnt <= 0; // 引导码
                end else if (time_cnt > 80 && time_cnt < 150) begin
                    shift_reg <= {1'b0, shift_reg[31:1]}; // 逻辑 0
                    bit_cnt <= bit_cnt + 1;
                end else if (time_cnt > 180 && time_cnt < 280) begin
                    shift_reg <= {1'b1, shift_reg[31:1]}; // 逻辑 1
                    bit_cnt <= bit_cnt + 1;
                end

                // 接收完 32 位并校验
                if (bit_cnt == 31 && time_cnt > 80) begin
                    key_val <= shift_reg[23:16]; // 提取命令码 Cmd
                    key_valid <= 1'b1;
                end
            end
        end
    end
endmodule