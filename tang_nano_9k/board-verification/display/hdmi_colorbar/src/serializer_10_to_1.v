module serializer_10_to_1(
input paralell_clk,       // 输入并行数据时钟
input serial_clk_5x,      // 输入5倍速串行时钟
input [9:0] paralell_data,// 10bit并行TMDS编码数据输入
input reset,              // 复位信号

output serial_data        // 1bit串行差分前数据输出
);

// 调用高云FPGA专用10:1串化原语OSER10
OSER10 u_OSER10(
.Q      (serial_data),
.D0     (paralell_data[0]),
.D1     (paralell_data[1]),
.D2     (paralell_data[2]),
.D3     (paralell_data[3]),
.D4     (paralell_data[4]),
.D5     (paralell_data[5]),
.D6     (paralell_data[6]),
.D7     (paralell_data[7]),
.D8     (paralell_data[8]),
.D9     (paralell_data[9]),
.PCLK   (paralell_clk),   // 并行像素时钟
.FCLK   (serial_clk_5x),  // 5倍高速串行移位时钟
.RESET  (reset)
);

// 原语参数配置
defparam u_OSER10.GSREN = "false";  // 关闭全局同步复位
defparam u_OSER10.LSREN  = "true";  // 开启本地同步复位

endmodule