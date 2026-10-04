module ir_transmitter(
    input clk,            // 27MHz 系统时钟
    input rst_n,          // 复位键
    input tx_en,          // 发射触发脉冲
    input [7:0] cmd,      // 需要发射的命令码
    output ir_tx          // 红外/普通LED输出引脚
);

    // 1. 产生 38kHz 载波 (27MHz / 38000 ≈ 710 周期)
    reg [9:0] carrier_cnt;
    reg carrier_clk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            carrier_cnt <= 0;
            carrier_clk <= 0;
        end else if (carrier_cnt >= 709) begin
            carrier_cnt <= 0;
            carrier_clk <= ~carrier_clk;
        end else begin
            carrier_cnt <= carrier_cnt + 1;
        end
    end

    // 2. 产生 10us 滴答基准 (27MHz / 270 = 100kHz)
    reg [8:0] tick_cnt;
    wire tick = (tick_cnt == 269);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick_cnt <= 0;
        else if (tick) tick_cnt <= 0;
        else tick_cnt <= tick_cnt + 1;
    end

    // 3. NEC 发射状态机
    localparam S_IDLE       = 3'd0;
    localparam S_LEAD_HIGH  = 3'd1; // 9ms 引导码高电平(载波)
    localparam S_LEAD_LOW   = 3'd2; // 4.5ms 引导码低电平
    localparam S_BIT_HIGH   = 3'd3; // 560us 数据位高电平(载波)
    localparam S_BIT_LOW    = 3'd4; // 560us(逻辑0)/1690us(逻辑1) 低电平
    localparam S_END_HIGH   = 3'd5; // 560us 结束位

    reg [2:0] state;
    reg [15:0] timer_10us;
    reg [5:0] bit_cnt;
    reg [31:0] tx_data;
    reg carrier_en;

    assign ir_tx = carrier_en ? carrier_clk : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            timer_10us <= 0;
            bit_cnt <= 0;
            tx_data <= 0;
            carrier_en <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    carrier_en <= 0;
                    timer_10us <= 0;
                    bit_cnt <= 0;
                    if (tx_en) begin
                        // 组装 NEC 标准数据帧：{~cmd, cmd, ~addr, addr}
                        tx_data <= {~cmd, cmd, 8'hFF, 8'h00}; 
                        state <= S_LEAD_HIGH;
                    end
                end

                S_LEAD_HIGH: begin // 9ms = 900 个 10us
                    carrier_en <= 1;
                    if (tick) begin
                        if (timer_10us >= 899) begin
                            timer_10us <= 0;
                            state <= S_LEAD_LOW;
                        end else begin
                            timer_10us <= timer_10us + 1;
                        end
                    end
                end

                S_LEAD_LOW: begin // 4.5ms = 450 个 10us
                    carrier_en <= 0;
                    if (tick) begin
                        if (timer_10us >= 449) begin
                            timer_10us <= 0;
                            state <= S_BIT_HIGH;
                        end else begin
                            timer_10us <= timer_10us + 1;
                        end
                    end
                end

                S_BIT_HIGH: begin // 560us = 56 个 10us
                    carrier_en <= 1;
                    if (tick) begin
                        if (timer_10us >= 55) begin
                            timer_10us <= 0;
                            state <= S_BIT_LOW;
                        end else begin
                            timer_10us <= timer_10us + 1;
                        end
                    end
                end

                S_BIT_LOW: begin // 数据0: 560us(56个10us) / 数据1: 1690us(169个10us)
                    carrier_en <= 0;
                    if (tick) begin
                        if ((tx_data[bit_cnt] == 1'b0 && timer_10us >= 55) ||
                            (tx_data[bit_cnt] == 1'b1 && timer_10us >= 168)) begin
                            timer_10us <= 0;
                            if (bit_cnt >= 31) begin
                                state <= S_END_HIGH;
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                                state <= S_BIT_HIGH;
                            end
                        end else begin
                            timer_10us <= timer_10us + 1;
                        end
                    end
                end

                S_END_HIGH: begin // 560us 脉冲结尾
                    carrier_en <= 1;
                    if (tick) begin
                        if (timer_10us >= 55) begin
                            timer_10us <= 0;
                            carrier_en <= 0;
                            state <= S_IDLE;
                        end else begin
                            timer_10us <= timer_10us + 1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule