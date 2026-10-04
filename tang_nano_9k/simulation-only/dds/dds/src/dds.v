module dds(
    input sys_clk ,        //系统时钟
    input sys_rst_n ,      //系统复位，低电平有效
    input key_wave ,       //波形控制按键
    input key_freq ,       //频率控制按键
    //DA 芯片接口
    output da_clk ,        //DAC 驱动时钟
    output [7:0] da_data , //输出给 DA 的数据
    //AD 芯片接口
    input [7:0] ad_data ,  //AD 输入数据
    //模拟输入电压超出量程标志(本次试验未用到)
    input ad_otr ,         //0:在量程范围 1:超出量程
    output ad_clk          //ADC 驱动时钟
);

//parameter define
parameter CNT_MAX = 20'd200_0000; //100MHz 时钟下计数 20ms

//wire define
wire rst_n ;             // 复位，低有效
wire pll_lock ;          //PLL 时钟锁定信号
wire clk_100m ;          //100MHz 时钟
wire clk_25m ;           //25MHz 时钟
wire [8:0] rd_addr ;     //ROM 读地址
wire [7:0] rd_data ;     //ROM 读出的数据
wire key_wave_filter;    //波形控制按键消抖后的按键值
wire key_freq_filter;    //频率控制按键消抖后的按键值

//*****************************************************
//** main code
//*****************************************************

//通过系统复位信号和 PLL 时钟锁定信号来产生一个新的复位信号
assign rst_n = sys_rst_n & pll_lock;
assign ad_clk = clk_25m;

//clk_100m u_clk_100m(
//    .clkout(clk_100m),   //output clkout
//    .lock(pll_lock),      //output lock
//   .clkin(sys_clk)      //input clkin
//);

//clk_25m u_clk_25m(
//    .clkout(clk_25m),    //output clkout
//    .lock(),             //output lock
//    .clkin(sys_clk)      //input clkin
//);

//ROM 存储波形
rom_400x8b u_rom_400x8b(
    .dout(rd_data),      //output [7:0] dout
    .clk(clk_100m),      //input clk
    .oce(1'b0),          //input oce
    .ce(1'b1),           //input ce
    .reset(1'b0),        //input reset
    .ad(rd_addr)         //input [8:0] ad
);

//例化按键消抖模块
key_debounce #(
    .CNT_MAX (CNT_MAX )
)
u_key_wave_debounce(
    .sys_clk    (clk_100m ),
    .sys_rst_n  (rst_n ),
    .key        (key_wave ),
    .key_filter (key_wave_filter)
);

//例化按键消抖模块
key_debounce #(
    .CNT_MAX (CNT_MAX )
)
u_key_freq_debounce(
    .sys_clk    (clk_100m ),
    .sys_rst_n  (rst_n ),
    .key        (key_freq ),
    .key_filter (key_freq_filter)
);

//DA 数据发送
da_wave_send u_da_wave_send(
    .clk             (clk_100m ),
    .rst_n           (rst_n ),
    .key_wave_filter (key_wave_filter),
    .key_freq_filter (key_freq_filter),
    .rd_data         (rd_data ),
    .rd_addr         (rd_addr ),
    .da_clk          (da_clk ),
    .da_data         (da_data )
);

endmodule
