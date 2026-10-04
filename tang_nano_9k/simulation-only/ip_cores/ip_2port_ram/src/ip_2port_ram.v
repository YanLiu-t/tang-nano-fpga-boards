module ip_2port_ram(
input sys_clk , //系统时钟
input sys_rst_n , //系统复位，低电平有效
//不受控制引脚绑定为高组态
output beep ,

//冗余逻辑，仅仅是为了将端口拉出去，否则没有输出信号的话无法在线抓取信号
//无需分配引脚
output ram_wr_en ,
output [4:0] ram_wr_addr ,
output [7:0] ram_wr_data ,
output [4:0] ram_rd_addr ,
output [7:0] ram_rd_data ,
output rd_rst //读端口复位(使能)信号
);

//wire define
wire rd_flag ; //读启动标志

//*****************************************************
//** main code
//*****************************************************

//将 BEEP 设置为高组态
assign beep = 1'hz;

//SDPB IP 核
gowin_sdpb u_gowin_sdpb(
    .dout (ram_rd_data), //output [7:0] dout
    .clka (sys_clk ), //input clka
    .cea (ram_wr_en ), //input cea
    .reseta (~sys_rst_n ), //input reseta
    .clkb (sys_clk ), //input clkb
    .ceb (rd_flag ), //input ceb
    .resetb (rd_rst ), //input resetb
    .oce (1'b1 ), //input oce
    .ada (ram_wr_addr), //input [4:0] ada
    .din (ram_wr_data), //input [7:0] din
    .adb (ram_rd_addr) //input [4:0] adb
);

//RAM 写模块
ram_wr u_ram_wr(
    .clk (sys_clk ),
    .rst_n (sys_rst_n ),
    .rd_flag (rd_flag ),
    .ram_wr_en (ram_wr_en ), //ram 写使能
    .ram_wr_addr (ram_wr_addr),
    .ram_wr_data (ram_wr_data)
);

//RAM 读模块 
ram_rd u_ram_rd(
    .clk (sys_clk ),
    .rst_n (sys_rst_n ),
    .rd_rst (rd_rst ), //ram 读端口复位（使能）信号
    .rd_flag (rd_flag ),
    .ram_rd_addr (ram_rd_addr),
    .ram_rd_data (ram_rd_data)
);

endmodule