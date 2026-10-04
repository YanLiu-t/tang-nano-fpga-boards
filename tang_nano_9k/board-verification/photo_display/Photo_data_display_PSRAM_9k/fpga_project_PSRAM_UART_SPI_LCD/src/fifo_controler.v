/*
fifo的封装模块简介
可以传进读时钟和写时钟和一个复位信号
可以在外部直接操作fifo的写端口进行每次写128位的写操作
读数据在内部封装可以在外部实现发送一个时钟周期的请求信号有效之后的第三个时钟周期开始
连续32个时钟周期每一位时钟周期通过pixel_data读出24位数据
(具体的请求时序参照说明手册)
*/
module fifo_controler(
input clk_psram,               //psram用户的时钟信号(读时钟)
input pix_clock,               //像素时钟(写时钟)
input reset_n,                 //全局的复位信号
input WrEn,                    //fifo的写使能信号
input [127:0]Data,             //写入fifo的数据
input fifo_read_go,            //从fifo读数据的请求信号
output Almost_Full,            //fifo将要满时的提示信号
output reg[15:0]pixel_data     //lcd屏数据的扫描显示信号(读出的数据)
);

//读数据时的寄存器缓冲
//16 X 24的位宽，用于将从fifo读出的16位数据转化为24位数据，便于spi的扫描
reg [383:0]Data_Read_Buffer;
//lcd_spi读取缓冲的reg变量的位计数器(周期为16)
reg [3:0]counter_spi_bit;
//lcd_spi读取缓冲的reg变量的每位的分频时间间隔的计数器
reg [4:0]counter_spi_div;
//计数器使能信号
reg counter_spi_en;
//spi数据的请求信号
reg spi_req;
//定义一个给fifo读使能延时的计数器(周期为24)
reg [4:0]counter_rden;
//fifo读数据的使能信号
reg RdEn;
//fifo读出的数据
wire [15:0]OutData;


//定义一个给fifo读使能延时的计数器的赋值逻辑
always@(posedge pix_clock , negedge reset_n)begin
    //给计数器复位为）
    if(reset_n == 1'b0)begin
        counter_rden <= 5'd0;
    end
    //当读使能有效时一直给计数器计数，当计满23位时就给其清零
    else if(RdEn)begin
        if(counter_rden == 5'd23)begin
            counter_rden <= 5'd0;
        end
        else begin
            counter_rden <= counter_rden + 5'b1;
        end
    end
    //如果读使能无效时就将其一直计为0
    else begin  
        counter_rden <= 5'd0;
    end
end

//对于fifo读使能信号的赋值逻辑
always@(posedge pix_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //将其复位为0
        RdEn <= 1'b0;
    end
    //当检测到请求信号有效时,将写使能置为1
    else if(fifo_read_go)begin
        RdEn <= 1'b1;
    end
    //当计数器计满时就将其拉低
    else if(counter_rden == 5'd23)begin
        RdEn <= 1'b0;
    end
    else begin
        //其他情况下不变
        RdEn <= RdEn;
    end
end

//对于临时存储的寄存器的赋值逻辑
always@(posedge pix_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //将缓冲容器复位计0
        Data_Read_Buffer <= 384'b0;
    end
    //如果写使能有效就一直将从fifo读出来的一批16位的数据从缓冲区低位到高位存入(读24个时钟周期)
    else if(RdEn)begin
        Data_Read_Buffer[counter_rden * 16     ] <= OutData[0 ];
        Data_Read_Buffer[counter_rden * 16 + 1 ] <= OutData[1 ];
        Data_Read_Buffer[counter_rden * 16 + 2 ] <= OutData[2 ];
        Data_Read_Buffer[counter_rden * 16 + 3 ] <= OutData[3 ];
        Data_Read_Buffer[counter_rden * 16 + 4 ] <= OutData[4 ];
        Data_Read_Buffer[counter_rden * 16 + 5 ] <= OutData[5 ];
        Data_Read_Buffer[counter_rden * 16 + 6 ] <= OutData[6 ];
        Data_Read_Buffer[counter_rden * 16 + 7 ] <= OutData[7 ];
        Data_Read_Buffer[counter_rden * 16 + 8 ] <= OutData[8 ];
        Data_Read_Buffer[counter_rden * 16 + 9 ] <= OutData[9 ];
        Data_Read_Buffer[counter_rden * 16 + 10] <= OutData[10];
        Data_Read_Buffer[counter_rden * 16 + 11] <= OutData[11];
        Data_Read_Buffer[counter_rden * 16 + 12] <= OutData[12];
        Data_Read_Buffer[counter_rden * 16 + 13] <= OutData[13];
        Data_Read_Buffer[counter_rden * 16 + 14] <= OutData[14];
        Data_Read_Buffer[counter_rden * 16 + 15] <= OutData[15];
    end
    else begin
        //其他情况下将其保持不变
        Data_Read_Buffer <= Data_Read_Buffer;
    end
end

//-------------以下为根据spi_lcd屏扫描数据的时序设计好的读数据的时序,如果看不懂,可以参考时序图--------------------------

always@(posedge pix_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //开始将读出的数据置为无效
        pixel_data <= 16'bz;
    end
    //当请求数据有效时以一批读16位数据的标准从缓冲寄存器内自低位到高位读出数据(读32个时钟周期)
    else if(spi_req == 1'b1)begin
//        pixel_data[0 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 0 ];
//        pixel_data[1 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 1 ];
//        pixel_data[2 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 2 ];
        pixel_data[0 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 3 ];
        pixel_data[1 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 4 ];
        pixel_data[2 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 5 ];
        pixel_data[3 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 6 ];
        pixel_data[4 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 7 ];
//        pixel_data[8 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 8 ];
//        pixel_data[9 ] <= Data_Read_Buffer[counter_spi_bit * 24 + 9 ];
        pixel_data[5] <= Data_Read_Buffer[counter_spi_bit * 24 + 10];
        pixel_data[6] <= Data_Read_Buffer[counter_spi_bit * 24 + 11];
        pixel_data[7] <= Data_Read_Buffer[counter_spi_bit * 24 + 12];
        pixel_data[8] <= Data_Read_Buffer[counter_spi_bit * 24 + 13];
        pixel_data[9] <= Data_Read_Buffer[counter_spi_bit * 24 + 14];
        pixel_data[10] <= Data_Read_Buffer[counter_spi_bit * 24 + 15];
//        pixel_data[16] <= Data_Read_Buffer[counter_spi_bit * 24 + 16];
//        pixel_data[17] <= Data_Read_Buffer[counter_spi_bit * 24 + 17];
//        pixel_data[18] <= Data_Read_Buffer[counter_spi_bit * 24 + 18];
        pixel_data[11] <= Data_Read_Buffer[counter_spi_bit * 24 + 19];
        pixel_data[12] <= Data_Read_Buffer[counter_spi_bit * 24 + 20];
        pixel_data[13] <= Data_Read_Buffer[counter_spi_bit * 24 + 21];
        pixel_data[14] <= Data_Read_Buffer[counter_spi_bit * 24 + 22];
        pixel_data[15] <= Data_Read_Buffer[counter_spi_bit * 24 + 23];
    end
    else begin
        //其他情况下，保持原来的值不变
        pixel_data <= pixel_data;
    end
end

always@(posedge pix_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //将数据请求信号复位
        spi_req <= 1'b0;
    end
    //保证在外部请求信号拉高之后的第三个时钟周期拉高数据请求信号
    else if((counter_spi_div == 5'b0) & (counter_spi_en))begin
        spi_req <= 1'b1;
    end
    //其他情况下，将其置零
    else begin
        spi_req <= 1'b0;
    end
end

always@(posedge pix_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //将计数器使能复位为0
        counter_spi_en <= 1'b0;
    end
    //当fifo读数据到一定程度就打开计数器使能,开始产生lcd扫描匹配的数据时序
    else if(RdEn & (counter_rden == 1'd0))begin
        counter_spi_en <= 1'b1;
    end
    //当计数器计满时将其关闭,证明与lcd匹配的数据时序结束
    else if((counter_spi_bit == 4'd15) & (counter_spi_div == 5'd16))begin
        counter_spi_en <= 1'b0;
    end
    else begin
        //否则就保持原来的状态不变
        counter_spi_en <= counter_spi_en;
    end
end


always@(posedge pix_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //读出数据的计数器复位
        counter_spi_bit <= 4'd0;
    end
    //当间隔计数器计满时就将位计数器执行一次操作
    else if(counter_spi_div == 5'd16)begin
        //当为计数器计满就将其清零,标志着16个像素点的数据执行完毕
        if(counter_spi_bit == 4'd15)begin
            counter_spi_bit <= 4'd0;
        end
        //否则让其一直加一
        else begin
            counter_spi_bit <= counter_spi_bit + 4'b1;
        end
    end
    else begin
        //如果请求信号没有拉高时就将其保持原样
        counter_spi_bit <= counter_spi_bit;
    end
end

always@(posedge pix_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //读出数据的计数器复位
        counter_spi_div <= 5'd0;
    end
    //当数据使能信号拉高时，就开始位计数器和延时计数器的计数
    else if(counter_spi_en)begin
        //当时间间隔记到最大值时,将其清零,与lcd扫描数据的时序一致
        if(counter_spi_div == 5'd16)begin
            counter_spi_div <= 5'd0;
        end
        //否则一直将其加一
        else begin
            counter_spi_div <= counter_spi_div + 5'b1;
        end
    end
    else begin
        //如果请求信号没有拉高时就将其清零
        counter_spi_div <= 5'd0;
    end
end
//--------------------------------------------------------------------------------------------


fifo_top u_fifo_top(
.WrClk(clk_psram),        //psram用户的时钟信号
.RdClk(pix_clock),        //像素时钟信号
.Reset(~reset_n),         //psram存储器处理的相关模块的复位信号(注意，在配置ip核时，一定要考虑复位信号是低电平有效还是高电平有效)
.Full(),                  //fifo以写满的信号
.Empty(),                 //fifo数据已空的信号
.Almost_Full(Almost_Full),//fifo将要满时的提示信号
.Data(Data),              //写入的数据(128位)
.WrEn(WrEn),              //写使能信号
.Q(OutData),              //读读出的信号
.RdEn(RdEn)               //读使能信号    
);




endmodule