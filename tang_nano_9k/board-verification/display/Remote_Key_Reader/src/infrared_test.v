module infrared_test(
    input clk_27m,          // 27MHz系统时钟
    input ir_rx,            // VS1838B输出脚（空闲高，收到信号低）
    output reg led          // 板载LED（低电平点亮）
);

// ========== 1. 分频到约1MHz采样时钟 ==========
reg [4:0] div_cnt;
reg sample_clk;

always @(posedge clk_27m) begin
    if(div_cnt == 26) begin
        div_cnt <= 0;
        sample_clk <= ~sample_clk;
    end else begin
        div_cnt <= div_cnt + 1;
    end
end

// ========== 2. 同步到采样时钟域 ==========
reg ir_sync1, ir_sync2;

always @(posedge sample_clk) begin
    ir_sync1 <= ir_rx;
    ir_sync2 <= ir_sync1;
end

// ========== 3. 核心逻辑：检测到低电平就亮灯 ==========
reg [23:0] led_timer;

always @(posedge sample_clk) begin
    // 如果检测到红外信号（低电平），点亮LED并重置计时器
    if(ir_sync2 == 1'b0) begin
        led <= 1'b0;           // 低电平点亮（看你板子LED是低亮还是高亮，如果是高亮就改成1）
        led_timer <= 24'd0;
    end else begin
        // 没有信号时，计时1秒后熄灭
        if(led_timer == 24'd999999) begin
            led <= 1'b1;       // 熄灭（如果是低亮，高电平熄灭）
        end else begin
            led_timer <= led_timer + 1;
        end
    end
end

endmodule