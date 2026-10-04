module top_adc_led(
    input wire clk,           // 27MHz系统时钟 PIN_52
    
    // TM7705接口
    output wire tm7705_rst,    // PIN_25
    output wire tm7705_sclk,   // PIN_26
    input wire tm7705_dout,    // PIN_27
    output wire tm7705_cs,     // PIN_28
    output wire tm7705_din,    // PIN_29
    input wire tm7705_drdy,    // PIN_30
    
    // HC595数码管接口
    output wire dio,           // PIN_31
    output wire srclk,         // PIN_33
    output wire rclk           // PIN_34
);

// 内部信号
wire [15:0] adc_data;
wire adc_data_valid;
wire [11:0] voltage_mv;  // 0-3300mV

// TM7705驱动
tm7705_ctrl u_tm7705(
    .clk(clk),
    .rst_n(1'b1),
    .adc_rst(tm7705_rst),
    .adc_sclk(tm7705_sclk),
    .adc_dout(tm7705_dout),
    .adc_cs(tm7705_cs),
    .adc_din(tm7705_din),
    .adc_drdy(tm7705_drdy),
    .adc_data(adc_data),
    .data_valid(adc_data_valid)
);

// 电压转换
voltage_calc u_vcalc(
    .clk(clk),
    .adc_data(adc_data),
    .data_valid(adc_data_valid),
    .voltage_mv(voltage_mv)
);

// HC595数码管显示
hc595_display u_display(
    .clk(clk),
    .voltage_mv(voltage_mv),
    .dio(dio),
    .srclk(srclk),
    .rclk(rclk)
);

endmodule