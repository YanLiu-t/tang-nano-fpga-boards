module voltage_calc(
    input wire clk,
    input wire [15:0] adc_data,
    input wire data_valid,
    output reg [11:0] voltage_mv  // 0-3300mV
);

// --------------------------------------------------
// 1. 均值滤波：收集 16 次数据求平均
// --------------------------------------------------
reg [19:0] sum;          // 20位宽，足够容纳 16个 16位数据相加防溢出
reg [4:0] count;         // 计数器 0-15
reg [15:0] adc_avg;      // 滤波后的平均值
reg avg_ready;           // 平均值计算完成标志

always @(posedge clk) begin
    avg_ready <= 1'b0;
    if(data_valid) begin
        if(count == 5'd15) begin
            // 算上当前数据，除以16 (右移4位就是除以16)
            adc_avg <= (sum + adc_data) >> 4; 
            sum <= 20'd0;
            count <= 5'd0;
            avg_ready <= 1'b1;
        end else begin
            sum <= sum + adc_data;
            count <= count + 1'b1;
        end
    end
end

// --------------------------------------------------
// 2. 计算电压 (当平均值准备好时才计算一次)
// --------------------------------------------------
reg [11:0] voltage_calc_out;
always @(posedge clk) begin
    if(avg_ready) begin
        voltage_calc_out <= (adc_avg[15:4] * 32'd3300) >> 12;
    end
end

// --------------------------------------------------
// 3. 刷新率限制 (让人眼看着舒服，约0.1秒更新一次数码管)
// --------------------------------------------------
// 假设系统时钟 27MHz，0.1秒需要计数 2,700,000 次
reg [21:0] refresh_cnt; 

always @(posedge clk) begin
    if(refresh_cnt >= 22'd2_700_000) begin
        refresh_cnt <= 0;
        // 每隔0.1秒，才把计算好的电压推给外部数码管
        voltage_mv <= voltage_calc_out; 
    end else begin
        refresh_cnt <= refresh_cnt + 1'b1;
    end
end

endmodule