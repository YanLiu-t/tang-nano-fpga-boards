module ram_wr(
input clk , //时钟信号
input rst_n , //复位信号，低电平有效

//RAM 写端口操作
output reg ram_wr_en , //ram 写使能
output reg rd_flag , //读启动信号
output reg [4:0] ram_wr_addr , //ram 写地址 
output reg [7:0] ram_wr_data //ram 写数据
);

//*****************************************************
//** main code
//*****************************************************

//控制 RAM 使能信号
always @(posedge clk or negedge rst_n) begin
if(!rst_n)
ram_wr_en <= 1'b0;
else
ram_wr_en <= 1'b1;
end

//写地址信号 范围:0~31 
always @(posedge clk or negedge rst_n) begin
if(!rst_n) 
ram_wr_addr <= 5'd0;
else if((ram_wr_addr < 5'd31) && ram_wr_en)
ram_wr_addr <= ram_wr_addr + 5'b1;
else
ram_wr_addr <= 5'd0;
end 

//写数据与写地址相同
always @(posedge clk or negedge rst_n) begin
if(!rst_n) 
ram_wr_data <= 8'd0;
else if((ram_wr_addr < 8'd31) && ram_wr_en)
ram_wr_data <= ram_wr_data + 8'b1;
else
ram_wr_data <= 8'd0;
end 

//当写入 16 个数据（0~15）后，拉高读启动信号
always @(posedge clk or negedge rst_n) begin
if(!rst_n)
rd_flag <= 1'b0;
else if(ram_wr_addr == 5'd15) 
rd_flag <= 1'b1;
else
rd_flag <= rd_flag;
end 

endmodule