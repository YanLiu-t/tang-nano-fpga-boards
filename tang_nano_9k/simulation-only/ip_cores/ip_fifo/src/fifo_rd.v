module fifo_rd(
input rd_clk ,                 // 读侧时钟信号
input rst_n ,                  // 全局低电平复位

input [8:0] fifo_rd_data_count,// 读时钟域：FIFO内部现存数据个数
input [7:0] fifo_rd_data,      // 从FIFO读出的8bit数据
input fifo_full ,              // FIFO满标志（源自写时钟域，跨时钟域信号）
output reg fifo_rd_en          // FIFO读使能信号，高电平有效
);

// 两级同步寄存器，消除跨时钟域亚稳态
reg full_d0;
reg full_d1;

// 将写域的full满信号，同步到读时钟rd_clk（打两拍，两级触发器同步）
always @(posedge rd_clk or negedge rst_n) begin
    if(!rst_n) begin
        full_d0 <= 1'b0;
        full_d1 <= 1'b0;
    end
    else begin
        full_d0 <= fifo_full;
        full_d1 <= full_d0;
    end
end 

// 读使能生成逻辑：FIFO写满才开始读，仅剩1个数据时停止读取，防止读空报错
always @(posedge rd_clk or negedge rst_n) begin
    if(!rst_n)
        fifo_rd_en <= 1'b0;
    else if(full_d1)               // 同步后的满标志到来，开启读使能
        fifo_rd_en <= 1'b1;
    else if(fifo_rd_data_count == 9'd1) // 只剩最后1个数据，关闭读使能
        fifo_rd_en <= 1'b0;
    else
        fifo_rd_en <= fifo_rd_en; // 保持原有读使能状态
end

endmodule