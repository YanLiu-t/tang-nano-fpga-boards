module ip_pll(
    input sys_clk ,                    //系统时钟
    input sys_rst_n ,                  //系统复位，低电平有效
    //输出时钟
    output clk_100m ,                  //100Mhz 时钟频率
    output clk_100m_180deg,           //100Mhz 时钟频率,相位偏移 180 度
    output clk_33m ,                   //33Mhz 时钟频率
    output clk_25m                     //25Mhz 时钟频率
);

//wire define
wire pll_lock;

//*****************************************************
//** main code
//*****************************************************

//锁相环
gowin_rpll u_gowin_rpll (
    .clkout    (clk_100m),            //output clkout
    .lock      (pll_lock ),            //output lock
    .clkoutp   (clk_100m_180deg),     //output clkoutp
    .clkoutd   (clk_25m),              //output clkoutd
    .clkoutd3  (clk_33m),              //output clkoutd3
    .reset     (~sys_rst_n),           //input reset
    .clkin     (sys_clk)                //input clkin
);

endmodule