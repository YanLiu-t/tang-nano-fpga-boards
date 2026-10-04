module ddr3_fifo_ctrl(
input               rst_n ,         //复位信号
input               wr_clk ,        //wfifo 时钟
input               rd_clk ,        //rfifo 时钟
input               ui_clk ,        //用户时钟
input               wr_en ,         //数据有效使能信号
input      [15:0]   wrdata ,        //有效数据
input      [127:0]  rfifo_din ,     //用户读数据
input               rdata_req ,     //请求像素点颜色数据输入
input               rfifo_wren ,    //从 ddr3 读出数据的有效使能
input               wfifo_rden ,    //wfifo 读使能
input               rd_load ,       //输出源场信号
input               wr_load ,       //输入源场信号

output     [127:0]  wfifo_dout ,    //用户写数据
output     [9:0]    rfifo_wcount ,  //rfifo 剩余数据计数
output     [9:0]    wfifo_rcount ,  //wfifo 写进数据计数
output reg [15:0]   rddata          //读有效数据
);

//reg define
reg [127:0] wrdata_t;       //由 16bit 输入源数据移位拼接得到
reg [15:0]  rd_load_d;      //由输出源场信号移位拼接得到
reg [3:0]   byte_cnt;       //写数据移位计数器
reg [127:0] data;           //rfifo 输出数据打拍得到
reg [3:0]   i;              //读数据移位计数器
reg [15:0]  wr_load_d;      //由输入源场信号移位拼接得到
reg         wr_load_d0;
reg         rd_load_d0;
reg         rdfifo_rst_h;   //rfifo 复位信号，高有效
reg         wfifo_rst_h;    //wfifo 复位信号，高有效
reg         wfifo_wren;     //wfifo 写使能信号

//wire define
wire [127:0] rfifo_dout;    //rfifo 输出数据
wire [127:0] wfifo_din;     //wfifo 写数据
wire [15:0]  dataout[0:7];  //定义输出数据的二维数组
wire         rfifo_rden;    //rfifo 的读使能

//*****************************************************
//** main code
//*****************************************************

//rfifo 输出的数据存到二维数组
assign dataout[0] = rfifo_dout[127:112];
assign dataout[1] = rfifo_dout[111:96];
assign dataout[2] = rfifo_dout[95:80];
assign dataout[3] = rfifo_dout[79:64];
assign dataout[4] = rfifo_dout[63:48];
assign dataout[5] = rfifo_dout[47:32];
assign dataout[6] = rfifo_dout[31:16];
assign dataout[7] = rfifo_dout[15:0];

assign wfifo_din = wrdata_t ;

//移位寄存器计满时，从 rfifo 读出一个数据
assign rfifo_rden = (rdata_req && (i==7)) ? 1'b1 : 1'b0;

//16 位数据转 128 位 RGB565 数据
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n) begin
        wrdata_t <= 0;
        byte_cnt <= 0;
    end
    else if(wr_en) begin
        if(byte_cnt == 7)begin
            byte_cnt <= 0;
            wrdata_t <= {wrdata_t[111:0],wrdata};
        end
        else begin
            byte_cnt <= byte_cnt + 1;
            wrdata_t <= {wrdata_t[111:0],wrdata};
        end
    end
    else begin
        byte_cnt <= byte_cnt;
        wrdata_t <= wrdata_t;
    end
end

//wfifo 写使能产生
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n)
        wfifo_wren <= 0;
    else if(wfifo_wren == 1)
        wfifo_wren <= 0;
    else if(byte_cnt == 7 && wr_en) //输入源数据传输 8 次，写使能拉高一次
        wfifo_wren <= 1;
    else
        wfifo_wren <= 0;
end

//对 rfifo 出来的 128bit 数据拆解成 8 个 16bit 数据
always @(posedge rd_clk or negedge rst_n) begin
    if(!rst_n) begin
        rddata <= 16'b0;
        i <=0;
    end
    else if(rdata_req) begin
        if(i == 7)begin
            rddata <= dataout[i];
            i <= 0;
        end
        else begin
            rddata <= dataout[i];
            i <= i + 1;
        end
    end
    else begin
        rddata <= rddata;
        i <=0;
    end
end

always @(posedge ui_clk or negedge rst_n) begin
    if(!rst_n)
        rd_load_d0 <= 1'b0;
    else
        rd_load_d0 <= rd_load;
end

//对输出源场信号进行移位寄存
always @(posedge ui_clk or negedge rst_n) begin
    if(!rst_n)
        rd_load_d <= 1'b0;
    else
        rd_load_d <= {rd_load_d[14:0],rd_load_d0};
end

//产生一段复位电平，满足 fifo 复位时序
always @(posedge ui_clk or negedge rst_n) begin
    if(!rst_n)
        rdfifo_rst_h <= 1'b0;
    else if(rd_load_d[0] && !rd_load_d[14])
        rdfifo_rst_h <= 1'b1;
    else
        rdfifo_rst_h <= 1'b0;
end

//对输入源场信号进行移位寄存
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n)begin
        wr_load_d0 <= 1'b0;
        wr_load_d <= 16'b0;
    end
    else begin
        wr_load_d0 <= wr_load;
        wr_load_d <= {wr_load_d[14:0],wr_load_d0};
    end
end

//产生一段复位电平，满足 fifo 复位时序
always @(posedge wr_clk or negedge rst_n) begin
    if(!rst_n)
        wfifo_rst_h <= 1'b0;
    else if(wr_load_d[0] && !wr_load_d[15])
        wfifo_rst_h <= 1'b1;
    else
        wfifo_rst_h <= 1'b0;
end

rd_fifo u_rd_fifo(
    .Data(rfifo_din),          //input [127:0] Data
    .Reset(~rst_n|rdfifo_rst_h),//input Reset
    .WrClk(ui_clk),            //input WrClk
    .RdClk(rd_clk),            //input RdClk
    .WrEn(rfifo_wren),         //input WrEn
    .RdEn(rfifo_rden),         //input RdEn
    .Wnum(rfifo_wcount),       //output [10:0] Wnum
    .Rnum(),                   //output [10:0] Rnum
    .Q(rfifo_dout),            //output [127:0] Q
    .Empty(),                  //output Empty
    .Full()                    //output Full
);

wr_fifo u_wr_fifo(
    .Data(wfifo_din),          //input [127:0] Data
    .Reset(~rst_n|wfifo_rst_h),//input Reset
    .WrClk(wr_clk),            //input WrClk
    .RdClk(ui_clk),            //input RdClk
    .WrEn(wfifo_wren),         //input WrEn
    .RdEn(wfifo_rden),         //input RdEn
    .Wnum(),                   //output [10:0] Wnum
    .Rnum(wfifo_rcount),       //output [10:0] Rnum
    .Q(wfifo_dout),            //output [127:0] Q
    .Empty(),                  //output Empty
    .Full()                    //output Full
);

endmodule
