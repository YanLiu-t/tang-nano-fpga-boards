module test_data(
input        clk_50m,
input        rst_n,
input        init_calib_complete,  //DDR3 初始化完成
input [15:0] rd_data,

output reg   rd_req,
output reg [15:0] wr_data,
output reg   wr_en,
output reg   error
);

//parameter
parameter TEST_LENGTH = 11'd1024;   //定义写入的数据最大值

//reg define
reg [11:0] rd_cnt;
reg [11:0] rd_cnt_d0;
reg        wr_finish;

reg        init_done_d0;
reg        init_done_d1;
reg        rd_valid;

//同步 ddr3 初始化完成信号（打两拍跨时钟域）
always @(posedge clk_50m or negedge rst_n) begin
    if(!rst_n) begin
        init_done_d0 <= 1'b0;
        init_done_d1 <= 1'b0;
    end
    else begin
        init_done_d0 <= init_calib_complete;
        init_done_d1 <= init_done_d0;
    end
end

//同步读计数
always @(posedge clk_50m or negedge rst_n) begin
    if(!rst_n)
        rd_cnt_d0 <= 1'b0;
    else
        rd_cnt_d0 <= rd_cnt;
end

//写入数据完成后，拉高读请求rd_req
always @(posedge clk_50m or negedge rst_n)begin
    if(!rst_n)
        rd_req <= 1'b0;
    else if(wr_finish)
        rd_req <= 1'b1;
end

//写数据完成标志
always @(posedge clk_50m or negedge rst_n)begin
    if(!rst_n)
        wr_finish <= 1'b0;
    else if(wr_data >= TEST_LENGTH - 1'b1) //写满TEST_LENGTH个数据
        wr_finish <= 1'b1;
    else
        wr_finish <= wr_finish;
end

//产生写FIFO数据与写使能，写入1~1024递增数
always @(posedge clk_50m or negedge rst_n)begin
    if(!rst_n) begin
        wr_data <= 16'd0;
        wr_en   <= 1'b0;
    end
    else if((wr_data <= TEST_LENGTH - 1'b1) && !wr_finish && init_done_d1)begin
        wr_data <= wr_data + 1'b1;
        wr_en   <= 1'b1;
    end
    else begin
        wr_data <= 16'd0;
        wr_en   <= 1'b0;
    end
end

//读操作计数
always @(posedge clk_50m or negedge rst_n) begin
    if(~rst_n)
        rd_cnt <= 1'b1;
    else if(rd_req)begin
        if(rd_cnt >= TEST_LENGTH)
            rd_cnt <= 1'b1;
        else
            rd_cnt <= rd_cnt + 1'b1;
    end
end

//第一次读取数据丢弃，rd_valid有效之后才开始比对
always @(posedge clk_50m or negedge rst_n)begin
    if(!rst_n)
        rd_valid <= 1'b0;
    else if(rd_cnt == TEST_LENGTH)
        rd_valid <= 1'b1;
    else
        rd_valid <= rd_valid;
end

//回读数据比对，不一致置error=1
always @(posedge clk_50m or negedge rst_n) begin
    if(~rst_n)
        error <= 1'b0;
    else if(rd_valid)begin
        if(rd_cnt_d0 != rd_data )
            error <= 1'b1;
        else
            error <= error;
    end
    else
        error <= error;
end

endmodule
