module hs_ad_da(
input sys_clk , //系统时钟
input sys_rst_n , //系统复位，低电平有效
//DA 芯片接口
output da_clk , //DA(AD9708)驱动时钟,最大支持 125Mhz 时钟
output [7:0] da_data , //输出给 DA 的数据
//AD 芯片接口
input [7:0] ad_data , //AD 输入数据
//模拟输入电压超出量程标志(本次试验未用到)
input ad_otr , //0:在量程范围 1:超出量程
output ad_clk //AD(AD9280)驱动时钟,最大支持 32Mhz 时钟
);

//wire define
wire [7:0] rd_addr; //ROM 读地址
wire [7:0] rd_data; //ROM 读出的数据
wire clk_50m; //50MHz 时钟
wire clk_25m; //25MHz 时钟
wire lock; //pll 时钟锁定信号
wire rst_n ; //复位信号，低有效

//*****************************************************
//** main code
//*****************************************************

//通过系统复位信号和 PLL 时钟锁定信号来产生一个新的复位信号
assign rst_n = sys_rst_n & lock ;
assign ad_clk = clk_25m ;

//pll
gowin_rpll gowin_rpll(
    .clkout (clk_50m),
    .lock (lock),
    .clkoutd (clk_25m),
    .reset (~sys_rst_n),
    .clkin (sys_clk)
);

//DA 数据发送
da_wave_send u_da_wave_send(
    .clk (clk_50m),
    .rst_n (rst_n),
    .rd_data (rd_data),
    .rd_addr (rd_addr),
    .da_clk (da_clk),
    .da_data (da_data)
);

//ROM 存储波形
rom_256x8b u_rom_256x8b(
    .dout (rd_data),
    .clk (clk_50m),
    .oce (1'b0),
    .ce (1'b1),
    .reset (~rst_n),
    .ad (rd_addr)
);

endmodule
