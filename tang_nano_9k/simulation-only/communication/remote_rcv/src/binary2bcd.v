module binary2bcd(
input wire sys_clk,
input wire sys_rst_n,
input wire [7:0] data,

output reg [7:0] bcd_data //十进制数的值
);
//parameter define
parameter CNT_SHIFT_NUM = 7'd8; //由 data 的位宽决定
//reg define
reg [6:0] cnt_shift; //移位判断计数器该值由 data 的位宽
reg [15:0] data_shift; //移位判断数据寄存器，由 data 和 bcddata 的位宽之和决定。
reg shift_flag; //移位判断标志信号

//*****************************************************
//** main code 
//*****************************************************

//cnt_shift 计数
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        cnt_shift <= 7'd0;
    else if((cnt_shift == CNT_SHIFT_NUM + 1) && (shift_flag))
        cnt_shift <= 7'd0;
    else if(shift_flag)
        cnt_shift <= cnt_shift + 1'b1;
    else
        cnt_shift <= cnt_shift;
end

//data_shift 计数器为 0 时赋初值，计数器为 1~CNT_SHIFT_NUM 时进行移位操作
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        data_shift <= 16'd0;
    else if(cnt_shift == 7'd0)
        data_shift <= {8'b0,data};
    else if((cnt_shift <= CNT_SHIFT_NUM)&&(!shift_flag))begin
        data_shift[11:8] <= (data_shift[11:8] > 4) ?
        (data_shift[11:8] + 2'd3):(data_shift[11:8]);
        data_shift[15:12] <= (data_shift[15:12] > 4) ?
        (data_shift[15:12] + 2'd3):(data_shift[15:12]);
    end
    else if((cnt_shift <= CNT_SHIFT_NUM)&&(shift_flag))
        data_shift <= data_shift << 1;
    else
        data_shift <= data_shift;
end

//shift_flag 移位判断标志信号，用于控制移位判断的先后顺序
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        shift_flag <= 1'b0;
    else
        shift_flag <= ~shift_flag;
end

//当计数器等于 CNT_SHIFT_NUM 时，移位判断操作完成，整体输出
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        bcd_data <= 16'd0;
    else if(cnt_shift == CNT_SHIFT_NUM + 1)
        bcd_data <= data_shift[15:8];
    else
        bcd_data <= bcd_data;
end

endmodule