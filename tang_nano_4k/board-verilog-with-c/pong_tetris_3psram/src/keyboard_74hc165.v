//============================================================================
// 74HC165 移位寄存器键盘驱动
//============================================================================
//
// 华智创客 8键数字无冲键盘接口:
//   PL = 并行加载 (低有效)
//   CP = 时钟 (上升沿)
//   Q7 = 串行数据输出
//   CE = 使能 (低有效, 接GND即可)
//
// 工作原理:
//   1. PL 拉低 → 把 8 个按键状态加载到移位寄存器
//   2. PL 拉高 → 准备移位
//   3. CP 发 8 个脉冲 → 从 Q7 读出 8 位数据
//      bit7=KEY8, bit6=KEY7, ... bit0=KEY1
//
//   按键按下 = 0 (低电平), 松开 = 1 (高电平)
//============================================================================

module keyboard_74hc165 (
    input  wire clk,        // 系统时钟
    input  wire resetn,     // 复位 (低有效)
    // --- 74HC165 接口 ---
    output reg  pl,         // 并行加载
    output reg  cp,         // 时钟
    input  wire q7,         // 串行数据
    // --- 按键输出 ---
    output reg  [7:0] keys, // 8 个按键状态 (按下=0, 松开=1)
    output reg  valid       // 有新数据
);

    // 状态机
    localparam S_LOAD   = 2'b00;  // PL 低, 加载按键
    localparam S_SETUP  = 2'b01;  // PL 高, 准备移位
    localparam S_SHIFT  = 2'b10;  // 发 CP 脉冲, 读数据
    localparam S_WAIT   = 2'b11;  // 等待下一次读取

    reg [1:0] state;
    reg [2:0] bit_cnt;          // 已读位数 0-7
    reg [4:0] wait_cnt;         // 周期计数器 (0..16)
    reg [17:0] clk_div;         // 分频计数器 (低速读键盘)
    reg [7:0] sh;               // 移位暂存: 半成品绝不外泄

    // 扫描周期: 约每 7.4ms 读一次 (27MHz 时钟)
    // 简化: 每 200000 个 27MHz 周期读一次
    localparam [17:0] PERIOD = 18'd200_000; // 27MHz / 200000 = 135Hz 刷新

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state     <= S_LOAD;
            pl        <= 1'b1;
            cp        <= 1'b0;
            bit_cnt   <= 0;
            keys      <= 8'hFF;  // 默认全松开
            sh        <= 8'hFF;
            valid     <= 1'b0;
            wait_cnt  <= 0;
            clk_div   <= 0;
        end else begin
            valid <= 1'b0;

            case (state)

                S_LOAD: begin
                    pl <= 1'b0;            // PL 拉低, 锁存按键
                    cp <= 1'b0;
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt == 16) begin    // 延时约 320ns (足够 74HC165 建立)
                        state    <= S_SETUP;
                        wait_cnt <= 0;
                    end
                end

                S_SETUP: begin
                    pl <= 1'b1;            // PL 拉高, 准备移位
                    cp <= 1'b0;
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt == 8) begin     // 延时 160ns
                        state    <= S_SHIFT;
                        wait_cnt <= 0;
                    end
                end

                S_SHIFT: begin
                    // 74HC165 时序: PL 变高后 Q7 立刻输出 D7, 之后每个 CP
                    // 上升沿把下一位移到 Q7. 所以必须在 "本位的时钟沿之前"
                    // 采样, 再打一拍 CP 去准备下一位.
                    //
                    // 关键: 整个移位过程读写 sh, 只有 8 位全部收齐才一次性
                    // 拷进 keys. 旧代码每个采样点都直接改 keys, 于是 keys 在
                    // 移位的 ~5us 里一直是"半成品"(低位被串入的 1 冲掉 -> 读成
                    // 0 = 按下). C 端只要在这个窗口读 REG_KEY, 就会看到若干
                    // 按键被误判为按下(典型表现: 方块不受控地往左漂).
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt == 0) begin
                        sh <= {sh[6:0], q7};     // 先采样当前 Q7
                        if (bit_cnt == 7) begin
                            keys <= {sh[6:0], q7}; // 8 位到齐, 整字节对外更新
                            state    <= S_WAIT;
                            bit_cnt  <= 0;
                            valid    <= 1'b1;   // 8 位都读完了
                            wait_cnt <= 0;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end else if (wait_cnt == 8) begin
                        cp <= 1'b1;             // 上升沿, 移位准备下一位
                    end else if (wait_cnt == 16) begin
                        cp <= 1'b0;
                        wait_cnt <= 0;
                    end
                end

                S_WAIT: begin
                    pl       <= 1'b1;
                    cp       <= 1'b0;
                    clk_div  <= clk_div + 1;
                    if (clk_div == PERIOD) begin
                        state   <= S_LOAD;
                        wait_cnt<= 0;
                        clk_div <= 0;
                    end
                end

            endcase
        end
    end

endmodule
