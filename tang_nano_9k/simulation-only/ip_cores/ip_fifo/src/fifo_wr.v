module fifo_wr(
input wr_clk ,                // 写时钟信号
input rst_n ,                 // 复位信号，低电平有效

input [8:0] fifo_wr_data_count,// FIFO写时钟域内已写入数据个数
input fifo_empty ,            // FIFO空标志（来自读时钟域，需要同步）
output reg fifo_wr_en ,       // FIFO写使能信号
output reg [7:0] fifo_wr_data // 写入FIFO的8位数据
);

// 寄存器定义：两级同步寄存器，解决跨时钟域亚稳态
reg empty_d0;
reg empty_d1;

// 将读域的empty信号打两拍，同步到写时钟wr_clk域
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n) begin
        empty_d0 <= 1'b0;
        empty_d1 <= 1'b0;
    end
    else begin
        empty_d0 <= fifo_empty;
        empty_d1 <= empty_d0;
    end
end

// 生成FIFO写使能：FIFO为空开始写，写到255个数据停止写入
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n)
        fifo_wr_en <= 1'b0;
    else if(empty_d1)
        fifo_wr_en <= 1'b1;
    else if(fifo_wr_data_count == 9'd255)
        fifo_wr_en <= 1'b0; 
    else
        fifo_wr_en <= fifo_wr_en;
end 

// 生成递增测试数据：0~255循环累加
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n)
        fifo_wr_data <= 8'b0;
    else if(fifo_wr_en && fifo_wr_data < 8'd255)
        fifo_wr_data <= fifo_wr_data + 8'b1;
    else
        fifo_wr_data <= 8'b0;
end

endmodule