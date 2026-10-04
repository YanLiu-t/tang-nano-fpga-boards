module ds18b20_driver(
    input  wire clk,        // 27MHz 系统时钟
    input  wire rst_n,      // 低电平复位
    inout  wire dq,         // 单总线数据引脚
    output reg  [15:0] temp_out, // 读出的 16位 原始温度数据
    output reg  temp_valid  // 温度数据有效脉冲
);

    // --- 1 微秒定时器基准 (适用于 27MHz 时钟) ---
    // 27个时钟周期 = 1微秒
    reg [4:0] cnt_1us;
    wire tick_1us = (cnt_1us == 26);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) cnt_1us <= 0;
        else if(tick_1us) cnt_1us <= 0;
        else cnt_1us <= cnt_1us + 1;
    end

    // --- 全局通用延时定时器 (单位: 微秒) ---
    reg [19:0] timer; // 最大需要计时到 750,000 us (750ms)，20位足够
    reg timer_en;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) timer <= 0;
        else if(!timer_en) timer <= 0;
        else if(tick_1us) timer <= timer + 1;
    end

    // --- 单总线三态门控制 ---
    reg dq_en;  // 输出使能：1为输出，0为高阻态(输入)
    reg dq_out; // 输出电平
    assign dq = dq_en ? dq_out : 1'bz;

    // --- 底层时序状态机 (位操作级) ---
    localparam S_IDLE       = 0;
    localparam S_RST_LOW    = 1;
    localparam S_RST_HIGH   = 2;
    localparam S_TX_BIT_L   = 3;
    localparam S_TX_BIT_H   = 4;
    localparam S_RX_BIT_L   = 5;
    localparam S_RX_BIT_WAIT= 6;
    localparam S_RX_BIT_H   = 7;
    localparam S_WAIT_750MS = 8;

    reg [3:0] state, return_state;
    reg [4:0] bit_cnt;
    reg [15:0] tx_data;
    reg [15:0] rx_data;

    // --- 顶层命令执行流程 (指令级) ---
    localparam SEQ_INIT     = 0;
    localparam SEQ_RST1     = 1; // 第一次复位
    localparam SEQ_WR_CONV  = 2; // 发送跳过ROM(0xCC) + 温度转换(0x44)
    localparam SEQ_WAIT     = 3; // 等待 750ms 转换完成
    localparam SEQ_RST2     = 4; // 第二次复位
    localparam SEQ_WR_READ  = 5; // 发送跳过ROM(0xCC) + 读暂存器(0xBE)
    localparam SEQ_RD_TEMP  = 6; // 读取 16位 温度数据
    localparam SEQ_DONE     = 7; // 完成一轮，输出数据

    reg [2:0] seq_state;

    // --- 核心双层状态机控制 ---
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state        <= S_IDLE;
            return_state <= S_IDLE;
            seq_state    <= SEQ_INIT;
            timer_en     <= 0;
            dq_en        <= 0;
            dq_out       <= 0;
            bit_cnt      <= 0;
            tx_data      <= 0;
            rx_data      <= 0;
            temp_out     <= 0;
            temp_valid   <= 0;
        end else if(tick_1us) begin
            case(state)
                S_IDLE: begin
                    timer_en <= 0;
                    dq_en    <= 0;
                    temp_valid <= 0;
                    
                    // 指令序列分发
                    case(seq_state)
                        SEQ_INIT: seq_state <= SEQ_RST1;
                        
                        SEQ_RST1: begin
                            state        <= S_RST_LOW;
                            return_state <= S_IDLE;
                            seq_state    <= SEQ_WR_CONV;
                        end
                        
                        SEQ_WR_CONV: begin
                            // 发送: Skip ROM(0xCC) -> Convert(0x44). 单总线低位先发。
                            tx_data      <= 16'h44CC; 
                            bit_cnt      <= 16;
                            state        <= S_TX_BIT_L;
                            return_state <= S_IDLE;
                            seq_state    <= SEQ_WAIT;
                        end
                        
                        SEQ_WAIT: begin
                            state        <= S_WAIT_750MS;
                            return_state <= S_IDLE;
                            seq_state    <= SEQ_RST2;
                        end
                        
                        SEQ_RST2: begin
                            state        <= S_RST_LOW;
                            return_state <= S_IDLE;
                            seq_state    <= SEQ_WR_READ;
                        end
                        
                        SEQ_WR_READ: begin
                            // 发送: Skip ROM(0xCC) -> Read Scratchpad(0xBE).
                            tx_data      <= 16'hBECC;
                            bit_cnt      <= 16;
                            state        <= S_TX_BIT_L;
                            return_state <= S_IDLE;
                            seq_state    <= SEQ_RD_TEMP;
                        end
                        
                        SEQ_RD_TEMP: begin
                            bit_cnt      <= 16;
                            state        <= S_RX_BIT_L;
                            return_state <= S_IDLE;
                            seq_state    <= SEQ_DONE;
                        end
                        
                        SEQ_DONE: begin
                            temp_out   <= rx_data;
                            temp_valid <= 1;         // 拉高一个微秒的有效脉冲
                            seq_state  <= SEQ_RST1;  // 回到开头，自动循环持续测温
                        end
                    endcase
                end

                /* --- 以下是底层 1-Wire 微秒时序实现 --- */
                
                S_RST_LOW: begin // 产生复位脉冲
                    timer_en <= 1;
                    dq_en    <= 1;
                    dq_out   <= 0;
                    if(timer >= 500) begin // 拉低 500us
                        timer_en <= 0;
                        state    <= S_RST_HIGH;
                    end
                end

                S_RST_HIGH: begin // 等待存在脉冲
                    timer_en <= 1;
                    dq_en    <= 0; // 释放总线
                    if(timer >= 500) begin // 释放并等待 500us，忽略存在脉冲的精确判断以防卡死
                        timer_en <= 0;
                        state    <= return_state;
                    end
                end

                S_TX_BIT_L: begin // 写数据位开始 (拉低)
                    timer_en <= 1;
                    dq_en    <= 1;
                    dq_out   <= 0;
                    if(tx_data[0] == 1) begin
                        if(timer >= 2) begin // 写 1: 只拉低 2us
                            timer_en <= 0;
                            state    <= S_TX_BIT_H;
                        end
                    end else begin
                        if(timer >= 60) begin // 写 0: 拉低 60us
                            timer_en <= 0;
                            state    <= S_TX_BIT_H;
                        end
                    end
                end

                S_TX_BIT_H: begin // 写数据位恢复 (释放总线)
                    timer_en <= 1;
                    dq_en    <= 0; 
                    if(tx_data[0] == 1) begin
                        if(timer >= 60) begin // 补足余下的时间槽
                            timer_en <= 0;
                            tx_data  <= {1'b0, tx_data[15:1]};
                            bit_cnt  <= bit_cnt - 1;
                            state    <= (bit_cnt == 1) ? return_state : S_TX_BIT_L;
                        end
                    end else begin
                        if(timer >= 2) begin // 补足余下的时间槽
                            timer_en <= 0;
                            tx_data  <= {1'b0, tx_data[15:1]};
                            bit_cnt  <= bit_cnt - 1;
                            state    <= (bit_cnt == 1) ? return_state : S_TX_BIT_L;
                        end
                    end
                end

                S_RX_BIT_L: begin // 读数据位开始 (拉低激活)
                    timer_en <= 1;
                    dq_en    <= 1;
                    dq_out   <= 0;
                    if(timer >= 2) begin // 强制拉低 2us
                        timer_en <= 0;
                        dq_en    <= 0;   // 释放总线，交给 DS18B20 驱动
                        state    <= S_RX_BIT_WAIT;
                    end
                end

                S_RX_BIT_WAIT: begin // 等待并采样
                    timer_en <= 1;
                    if(timer >= 10) begin // 释放后等待 10us 进行采样 (总时长约 12us，符合规范)
                        timer_en <= 0;
                        rx_data  <= {dq, rx_data[15:1]}; // 采样并右移
                        state    <= S_RX_BIT_H;
                    end
                end

                S_RX_BIT_H: begin // 读数据位结束 (等待时间槽结束)
                    timer_en <= 1;
                    if(timer >= 50) begin // 继续等待 50us 凑够 60us 以上的时间槽
                        timer_en <= 0;
                        bit_cnt  <= bit_cnt - 1;
                        state    <= (bit_cnt == 1) ? return_state : S_RX_BIT_L;
                    end
                end

                S_WAIT_750MS: begin // 测温等待时间
                    timer_en <= 1;
                    if(timer >= 750000) begin // 750,000 us = 750 ms
                        timer_en <= 0;
                        state    <= return_state;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule