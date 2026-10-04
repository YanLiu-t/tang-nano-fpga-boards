`timescale 1ns / 1ps

module tb_lcd_rgb_char();

//reg define
reg sys_clk;
reg sys_rst_n; 

//wire define
wire lcd_de ;
wire lcd_hs ;
wire lcd_vs ;
wire lcd_bl ;
wire lcd_clk;
wire lcd_rst;
wire [23:0] lcd_rgb;

//GSR 全局复位（Gowin专用）
GSR GSR(.GSRI(1'b1));

//生成50MHz系统时钟，周期20ns
always #10 sys_clk = ~sys_clk;

//双向端口模拟：无DE时给固定值，DE有效时高阻交给内部驱动
assign lcd_rgb = lcd_de ? {24{1'bz}} : 24'h80;

//复位初始化
initial begin
    sys_clk = 1'b0;
    sys_rst_n = 1'b0;
    #200
    sys_rst_n = 1'b1;
end

//例化顶层待测模块
lcd_rgb_char u_lcd_rgb_char(
.sys_clk    (sys_clk ),
.sys_rst_n  (sys_rst_n),

.lcd_de     (lcd_de ),
.lcd_hs     (lcd_hs ),
.lcd_vs     (lcd_vs ),
.lcd_bl     (lcd_bl ),
.lcd_clk    (lcd_clk),
.lcd_rst    (lcd_rst),
.lcd_rgb    (lcd_rgb)
);

endmodule