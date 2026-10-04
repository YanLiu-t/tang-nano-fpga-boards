module data_gen(
input clk ,                 //时钟信号
input rst_n ,               //复位信号,低电平有效
input sd_init_done ,        //SD 卡初始化完成信号
//写 SD 卡接口
input wr_busy ,             //写数据忙信号
input wr_req ,              //写数据请求信号
output reg wr_start_en ,    // SD 卡写数据信号
output reg [31:0] wr_sec_addr , //写数据扇区地址
output [15:0] wr_data ,     //写数据
//读 SD 卡接口
input rd_val_en ,           //读数据有效信号
input [15:0] rd_val_data ,  //读数据
output reg rd_start_en ,    //开始读 SD 卡数据信号
output reg [31:0] rd_sec_addr , //读数据扇区地址

output error_flag           //SD 卡读写错误的标志
);

//reg define
reg sd_init_done_d0 ;       //sd_init_done 信号延时打拍
reg sd_init_done_d1 ;
reg wr_busy_d0 ;            //wr_busy 信号延时打拍
reg wr_busy_d1 ;
reg [15:0] wr_data_t ;
reg [15:0] rd_comp_data ;   //用于对读出数据作比较的正确数据
reg [8:0] rd_right_cnt ;    //读出正确数据的个数

//wire define
wire pos_init_done ;        //sd_init_done 信号的上升沿,用于启动写入信号
wire neg_wr_busy ;          //wr_busy 信号的下降沿,用于判断数据写入完成

//*****************************************************
//** main code
//*****************************************************

assign pos_init_done = (~sd_init_done_d1) & sd_init_done_d0;
assign neg_wr_busy = wr_busy_d1 & (~wr_busy_d0);
//wr_data_t 变化范围 0~256;wr_data 范围:0~255
assign wr_data = (wr_data_t > 16'd0) ? (wr_data_t - 1'b1) : 16'd0;
//读 256 次正确的数据,说明读写测试成功,error_flag = 0
assign error_flag = (rd_right_cnt == (9'd256)) ? 1'b0 : 1'b1;

//sd_init_done 信号延时打拍
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sd_init_done_d0 <= 1'b0;
        sd_init_done_d1 <= 1'b0;
    end
    else begin
        sd_init_done_d0 <= sd_init_done;
        sd_init_done_d1 <= sd_init_done_d0;
    end
end

//SD 卡写入信号控制
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        wr_start_en <= 1'b0;
        wr_sec_addr <= 32'd0;
    end
    else begin
        if(pos_init_done) begin
            wr_start_en <= 1'b1;
            wr_sec_addr <= 32'd2000; //任意指定一块扇区地址
        end
        else
            wr_start_en <= 1'b0;
    end
end

//SD 卡写数据
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        wr_data_t <= 16'b0;
    else if(wr_req)
        wr_data_t <= wr_data_t + 16'b1;
end

//wr_busy 信号延时打拍
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        wr_busy_d0 <= 1'b0;
        wr_busy_d1 <= 1'b0;
    end
    else begin
        wr_busy_d0 <= wr_busy;
        wr_busy_d1 <= wr_busy_d0;
    end
end

//SD 卡读出信号控制
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rd_start_en <= 1'b0;
        rd_sec_addr <= 32'd0;
    end
    else begin
        if(neg_wr_busy) begin
            rd_start_en <= 1'b1;
            rd_sec_addr <= 32'd2000;
        end
        else
            rd_start_en <= 1'b0;
    end
end

//读数据错误时给出标志
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rd_comp_data <= 16'd0;
        rd_right_cnt <= 9'd0;
    end
    else begin
        if(rd_val_en) begin
            rd_comp_data <= rd_comp_data + 16'b1;
            if(rd_val_data == rd_comp_data)
                rd_right_cnt <= rd_right_cnt + 9'd1;
        end
    end
end

endmodule
