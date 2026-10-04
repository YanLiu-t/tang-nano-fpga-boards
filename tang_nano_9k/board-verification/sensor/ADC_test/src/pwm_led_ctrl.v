module pwm_led_ctrl(
    input wire clk,
    input wire [11:0] voltage_mv,  // 0-3300mV
    output reg led_pwm
);

parameter PWM_BITS = 12;

reg [PWM_BITS-1:0] pwm_counter;
reg [PWM_BITS-1:0] pwm_threshold;

// PWM计数器，自由运行
always @(posedge clk) begin
    pwm_counter <= pwm_counter + 1;
end

// 电压映射到PWM占空比
// 0mV → 占空比0%，3300mV → 占空比100%
always @(posedge clk) begin
    if(voltage_mv >= 3300)
        pwm_threshold <= 4095;
    else if(voltage_mv == 0)
        pwm_threshold <= 0;
    else
        pwm_threshold <= (voltage_mv * 4095) / 3300;
end

// PWM输出，高电平LED亮
always @(posedge clk) begin
    if(pwm_counter < pwm_threshold)
        led_pwm <= 1'b1;
    else
        led_pwm <= 1'b0;
end

endmodule