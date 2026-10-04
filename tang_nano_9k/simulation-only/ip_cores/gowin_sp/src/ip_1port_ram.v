module ip_1port_ram(

input sys_clk ,        //系统时钟
input sys_rst_n ,      //系统复位，低电平有效

//冗余逻辑，仅仅是为了将端口拉出去，否则没有输出信号的话无法在线抓取信号
//无需分配引脚
output [7:0] ram_wr_data ,  //ram 写数据
output [7:0] ram_rd_data ,  //ram 读数据
output [4:0] ram_addr ,      //ram 读写地址
output ram_rw_en               //ram 读写使能，0：读数据 1：写数据

);

//*****************************************************
//** main code
//*****************************************************

//例化单端口 RAM IP 核
gowin_sp u_gowin_sp(
    .dout(ram_rd_data),    //output [7:0] dout
    .clk(sys_clk),           //input clk
    .oce( 1'b1),             //input oce
    .ce( 1'b1 ),              //input ce
    .reset(~sys_rst_n),      //input reset
    .wre(ram_rw_en),         //input wre
    .ad(ram_addr),            //input [4:0] ad
    .din(ram_wr_data)         //input [7:0] din
);

//RAM 读写模块
ram_rw u_ram_rw (
    .clk (sys_clk ),
    .rst_n (sys_rst_n ),
    .ram_rw_en (ram_rw_en ),
    .ram_addr (ram_addr ),
    .ram_wr_data (ram_wr_data )
);

endmodule