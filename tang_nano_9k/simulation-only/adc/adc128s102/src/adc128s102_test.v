module adc128s102_test(
    input           Clk,
    input           Reset_n,
    input           Key,          // 外接按键输入
    input   [2:0]   Addr,         // ADC通道选择地址
    output    reg      Led,          // 采样完成翻转指示灯
    // HC595数码管驱动引脚
    output          HEX8_DIO,
    output          HEX8_SCLK,
    output          HEX8_RCLK,
    // ADC128S102 SPI引脚
    output          ADC_SCLK,
    output          ADC_CS_N,
    output          ADC_DIN,
    input           ADC_DOUT
);

// 内部连线定义
wire [11:0] ADC_Data;    // ADC采样12位数据
wire        Conv_Go;     // ADC启动转换信号
wire        Conv_Done;   // ADC转换完成标志
wire        Key_P_Flag;  // 按键按下上升沿标志
wire [31:0] Disp_Data;   // 送入数码管的32位显示数据

// 1. 数据拼接：高位补0，12位ADC数据放在低12位，适配8位数码管驱动
assign Disp_Data = {20'd0, ADC_Data};

// 2. 数码管HC595驱动模块例化
hex8_hc595 hex8_hc595(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Disp_Data(Disp_Data),
    .DIO(HEX8_DIO),
    .SRCLK(HEX8_SCLK),
    .RCLK(HEX8_RCLK)
);

// 3. ADC128S102 SPI采集模块例化
adc128s102 adc128s102(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Conv_Go(Conv_Go),
    .Addr(Addr),
    .Conv_Done(Conv_Done),
    .Data(ADC_Data),
    .ADC_SCLK(ADC_SCLK),
    .ADC_CS_N(ADC_CS_N),
    .ADC_DIN(ADC_DIN),
    .ADC_DOUT(ADC_DOUT)
);

// 4. 按键消抖模块例化，生成按键按下标志
wire Key_R_Flag;
key_filter key_filter(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Key(Key),
    .key_state(),        // 未使用，悬空
    .Key_P_Flag(Key_P_Flag),
    .Key_R_Flag(Key_R_Flag)
);

// 5. 逻辑连线：按键按下标志 = ADC启动转换信号
assign Conv_Go = Key_P_Flag;

// 6. 指示灯逻辑：ADC转换完成时LED翻转
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) begin
        Led <= 1'b0;
    end
    else if(Conv_Done) begin
        Led <= ~Led;
    end
end

endmodule