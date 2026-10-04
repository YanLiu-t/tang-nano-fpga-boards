module ram_rd(
input clk , //时钟信号
input rst_n , //复位信号，低电平有效

//RAM 读端口操作 
input rd_flag , //读启动标志
input [7:0] ram_rd_data, //ram 读数据
output rd_rst , //ram 读端口复位（使能）信号
output reg [4:0] ram_rd_addr //ram 读地址 
);

//*****************************************************
//** main code
//*****************************************************

//控制 RAM 使能信号
assign rd_rst = ~rd_flag; 

//读地址信号 范围:0~31 
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) 
        ram_rd_addr <= 5'd0;
    else if((ram_rd_addr < 5'd31) && (!rd_rst))
        ram_rd_addr <= ram_rd_addr + 5'b1;
    else
        ram_rd_addr <= 5'd0;
end

endmodule