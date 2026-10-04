module top(
    input sys_clk,    // 27MHz 开发板时钟
    input sys_rst_n,  // 复位按键
    input ir_in,      // 接 VS1838B 的 OUT 脚
    
    // HC595 输出接口
    output hc595_dio,
    output hc595_srclk,
    output hc595_rclk,
    
    // ★ 新增：两个 LED 指示灯输出 ★
    output red_led,
    output green_led
);

    wire [7:0] w_key_val;
    wire w_key_valid;
    wire [7:0] w_seg;
    wire [7:0] w_sel;

    reg [7:0] latched_key;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) 
            latched_key <= 8'h00; 
        else if (w_key_valid) 
            latched_key <= w_key_val;
    end

    // 1：红外解码 (保留你的原模块)
    ir_receiver u_ir_rx(
        .clk        (sys_clk),
        .rst_n      (sys_rst_n),
        .ir_in      (ir_in),
        .key_val    (w_key_val),
        .key_valid  (w_key_valid)
    );

    // 2：数码管逻辑 (保留你的原模块)
    display_ctrl u_disp(
        .clk        (sys_clk),
        .rst_n      (sys_rst_n),
        .key_val    (latched_key), 
        .SEG        (w_seg),
        .SEL        (w_sel)
    );

    // 3：HC595 驱动 (保留你的原模块)
    HC595_Driver u_hc595(
        .Clk        (sys_clk),
        .Reset_n    (sys_rst_n),
        .SEG        (w_seg),
        .SEL        (w_sel),
        .DIO        (hc595_dio),
        .SRCLK      (hc595_srclk),
        .RCLK       (hc595_rclk)
    );

    // ★ 4：新增：LED 状态机控制模块 ★
    led_controller u_led(
        .clk        (sys_clk),
        .rst_n      (sys_rst_n),
        .key_val    (w_key_val),   // 直接接入解码出来的数据
        .key_valid  (w_key_valid), // 接入按键脉冲
        .red_led    (red_led),     // 连到顶层管脚
        .green_led  (green_led)    // 连到顶层管脚
    );

endmodule