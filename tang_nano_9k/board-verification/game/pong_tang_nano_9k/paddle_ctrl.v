//============================================================================
// 按键 → 球拍位置 + 游戏控制
//============================================================================
//
// 8 键映射:
//   KEY1 (keys[0]) → ↑  球拍向上移动 (位置减小)
//   KEY2 (keys[1]) → ↓  球拍向下移动 (位置增大)
//   KEY3 (keys[2]) → 重新发球/重置游戏
//   KEY4-KEY8      → 预留 (可以扩展)
//
// 按键按下 = 0 (active-low)
// 松开 = 1
//============================================================================

module paddle_ctrl (
    input  wire        clk,
    input  wire        resetn,
    input  wire  [7:0] keys,       // 8 个按键状态 (按下=0)
    input  wire        keys_valid, // 有新按键数据 (每次扫描到新数据时脉冲)
    output reg   [7:0] paddle_pos, // 球拍位置 0=顶, 255=底
    output wire        game_reset  // KEY3 按下时产生一个重置脉冲
);

    // 74HC165 位序反转: Q7 先出 D7, 但键盘 KEY1→D0, 所以反转位序
    wire [7:0] keys_r = {keys[0], keys[1], keys[2], keys[3],
                         keys[4], keys[5], keys[6], keys[7]};

    // 当前按键状态 (按下=1)
    wire key_up     = (keys_r[0] == 1'b0);  // KEY1 → 向上
    wire key_down   = (keys_r[1] == 1'b0);  // KEY2 → 向下
    wire key_reset  = (keys_r[2] == 1'b0);  // KEY3 → 重置

    // 消抖 + 边沿检测 (KEY3 仅按下瞬间触发一次)
    reg key_reset_last;
    reg reset_pulse;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            key_reset_last <= 1'b1;
            reset_pulse    <= 1'b0;
        end else if (keys_valid) begin
            reset_pulse    <= key_reset & ~key_reset_last; // 下降沿检测
            key_reset_last <= key_reset;
        end else begin
            reset_pulse    <= 1'b0;
        end
    end

    assign game_reset = reset_pulse;

    // 球拍移动控制
    // - 使用系统时钟 (50MHz), 不依赖 keys_valid 门控
    // - 按住按键持续移动 (按住 = 每 N 个时钟移动一次)
    // - 自动边界钳位: 到 0 或 255 就停
    reg [19:0] move_cnt;    // 分频计数器
    wire move_enable;
    assign move_enable = (move_cnt == 20'd50_000); // 50MHz / 50000 = 1000Hz 移动速度 (1ms/步)

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            paddle_pos <= 8'd128;  // 初始位置居中
            move_cnt   <= 20'd0;
        end else if (reset_pulse) begin
            paddle_pos <= 8'd128;  // KEY3 重置 → 回到中间
            move_cnt   <= 20'd0;
        end else begin
            move_cnt <= move_cnt + 20'd1;
            if (move_enable) begin
                case ({key_up, key_down})
                    2'b10: begin   // 只按 KEY1 → 向上
                        if (paddle_pos > 8'd4)
                            paddle_pos <= paddle_pos - 8'd4;
                    end
                    2'b01: begin   // 只按 KEY2 → 向下
                        if (paddle_pos < 8'd251)
                            paddle_pos <= paddle_pos + 8'd4;
                    end
                    default: begin // 都没按 或 同时按 → 停止
                        paddle_pos <= paddle_pos;
                    end
                endcase
            end
        end
    end

endmodule
