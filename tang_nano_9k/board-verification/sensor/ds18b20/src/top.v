module top(
    input  wire clk,        
    input  wire rst_n,      
    inout  wire ds_dq,      
    
    // 595 接口
    output wire hc_dio,       
    output wire hc_sclk,      
    output wire hc_rclk       
);

    wire [15:0] temp_raw;
    wire        temp_valid;
    reg  [15:0] bcd_data;
    
    wire [7:0] seg_val;
    wire [7:0] sel_val;
    wire next_digit_sig;

    // 1. 挂载 DS18B20 驱动 (用上一条回复里给你的完整版本)
    ds18b20_driver u_ds18b20(
        .clk(clk),
        .rst_n(rst_n),
        .dq(ds_dq),
        .temp_out(temp_raw),
        .temp_valid(temp_valid)
    );

    // 2. 数据处理：把 12 位温度乘 10，准备显示一位小数
    wire [19:0] temp_calc = (temp_raw[11:0] * 10) >> 4;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bcd_data <= 16'h000C;
        end else if(temp_valid) begin
            bcd_data[15:12] <= (temp_calc / 100) % 10; // 十位
            bcd_data[11:8]  <= (temp_calc / 10) % 10;  // 个位
            bcd_data[7:4]   <= temp_calc % 10;         // 小数位
            bcd_data[3:0]   <= 4'hC;                   // 字母 'C'
        end
    end

    // 3. 挂载温度翻译扫描层
    Display_Scan u_scan(
        .Clk(clk),
        .Reset_n(rst_n),
        .next_digit(next_digit_sig),
        .bcd_data(bcd_data),
        .SEG(seg_val),
        .SEL(sel_val)
    );

    // 4. 挂载【你的专属测电压成功版】595 驱动
    HC595_Driver u_hc595 (
        .Clk(clk),
        .Reset_n(rst_n),
        .SEG(seg_val),
        .SEL(sel_val),
        .DIO(hc_dio),
        .SRCLK(hc_sclk),
        .RCLK(hc_rclk),
        .next_digit(next_digit_sig)
    );

endmodule