/*
fifo的封装模块简介
可以传进读时钟和写时钟和一个复位信号
可以在外部直接操作fifo的写端口进行每次写256位的写操作
读数据在内部封装可以在外部实现发送一个时钟周期的请求信号有效之后的第三个时钟周期开始
连续32个时钟周期每一位时钟周期通过pixel_data读出24位数据
(具体的请求时序参照说明手册)
*/
module fifo_controler(
input clk_psram,               //psram用户的时钟信号(读时钟)
input sys_clock,               //像素时钟(写时钟)
input reset_n,                 //全局的复位信号
input WrEn,                    //fifo的写使能信号
input [255:0]Data,             //写入fifo的数据
input fifo_read_go,            //从fifo读数据的请求信号
output Almost_Full,            //来自fifo内部的将满信号
output reg[23:0]pixel_data     //HDMI数据的扫描显示信号(读出的数据)
);

//读数据时的寄存器缓冲
//32 X 24的位宽，用于将从fifo读出的32位数据转化为24位数据，便于hdmi的扫描
reg [767:0]Data_Read_Buffer;
//hdmi读取缓冲的reg变量的计数器(周期为32)
reg [4:0]counter_hdmi;
//hdmi数据的请求信号
reg hdmi_req;
//定义一个给fifo读使能延时的计数器(周期为24)
reg [4:0]counter_rden;
//fifo读数据的使能信号
reg RdEn;
//fifo读出的数据
wire [31:0]OutData;


//定义一个给fifo读使能延时的计数器的赋值逻辑
always@(posedge sys_clock , negedge reset_n)begin
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
always@(posedge sys_clock , negedge reset_n)begin
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
always@(posedge sys_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //将缓冲容器复位计0
        Data_Read_Buffer <= 768'b0;
    end
    //如果写使能有效就一直将从fifo读出来的一批32位的数据从缓冲区低位到高位存入(读24个时钟周期)
    else if(RdEn)begin
        Data_Read_Buffer[counter_rden * 32     ] <= OutData[0 ];
        Data_Read_Buffer[counter_rden * 32 + 1 ] <= OutData[1 ];
        Data_Read_Buffer[counter_rden * 32 + 2 ] <= OutData[2 ];
        Data_Read_Buffer[counter_rden * 32 + 3 ] <= OutData[3 ];
        Data_Read_Buffer[counter_rden * 32 + 4 ] <= OutData[4 ];
        Data_Read_Buffer[counter_rden * 32 + 5 ] <= OutData[5 ];
        Data_Read_Buffer[counter_rden * 32 + 6 ] <= OutData[6 ];
        Data_Read_Buffer[counter_rden * 32 + 7 ] <= OutData[7 ];
        Data_Read_Buffer[counter_rden * 32 + 8 ] <= OutData[8 ];
        Data_Read_Buffer[counter_rden * 32 + 9 ] <= OutData[9 ];
        Data_Read_Buffer[counter_rden * 32 + 10] <= OutData[10];
        Data_Read_Buffer[counter_rden * 32 + 11] <= OutData[11];
        Data_Read_Buffer[counter_rden * 32 + 12] <= OutData[12];
        Data_Read_Buffer[counter_rden * 32 + 13] <= OutData[13];
        Data_Read_Buffer[counter_rden * 32 + 14] <= OutData[14];
        Data_Read_Buffer[counter_rden * 32 + 15] <= OutData[15];
        Data_Read_Buffer[counter_rden * 32 + 16] <= OutData[16];
        Data_Read_Buffer[counter_rden * 32 + 17] <= OutData[17];
        Data_Read_Buffer[counter_rden * 32 + 18] <= OutData[18];
        Data_Read_Buffer[counter_rden * 32 + 19] <= OutData[19];
        Data_Read_Buffer[counter_rden * 32 + 20] <= OutData[20];
        Data_Read_Buffer[counter_rden * 32 + 21] <= OutData[21];
        Data_Read_Buffer[counter_rden * 32 + 22] <= OutData[22];
        Data_Read_Buffer[counter_rden * 32 + 23] <= OutData[23];
        Data_Read_Buffer[counter_rden * 32 + 24] <= OutData[24];
        Data_Read_Buffer[counter_rden * 32 + 25] <= OutData[25];
        Data_Read_Buffer[counter_rden * 32 + 26] <= OutData[26];
        Data_Read_Buffer[counter_rden * 32 + 27] <= OutData[27];
        Data_Read_Buffer[counter_rden * 32 + 28] <= OutData[28];
        Data_Read_Buffer[counter_rden * 32 + 29] <= OutData[29];
        Data_Read_Buffer[counter_rden * 32 + 30] <= OutData[30];
        Data_Read_Buffer[counter_rden * 32 + 31] <= OutData[31];
    end
    else begin
        //其他情况下将其保持不变
        Data_Read_Buffer <= Data_Read_Buffer;
    end
end


always@(posedge sys_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //开始将读出的数据置为无效
        pixel_data <= 24'bz;
    end
    //当请求数据有效时以一批读取24位数据的标准从缓冲寄存器内自低位到高位读出数据(读32个时钟周期)
    else if(hdmi_req == 1'b1)begin
        pixel_data[0 ] <= Data_Read_Buffer[counter_hdmi * 24 + 0 ];
        pixel_data[1 ] <= Data_Read_Buffer[counter_hdmi * 24 + 1 ];
        pixel_data[2 ] <= Data_Read_Buffer[counter_hdmi * 24 + 2 ];
        pixel_data[3 ] <= Data_Read_Buffer[counter_hdmi * 24 + 3 ];
        pixel_data[4 ] <= Data_Read_Buffer[counter_hdmi * 24 + 4 ];
        pixel_data[5 ] <= Data_Read_Buffer[counter_hdmi * 24 + 5 ];
        pixel_data[6 ] <= Data_Read_Buffer[counter_hdmi * 24 + 6 ];
        pixel_data[7 ] <= Data_Read_Buffer[counter_hdmi * 24 + 7 ];
        pixel_data[8 ] <= Data_Read_Buffer[counter_hdmi * 24 + 8 ];
        pixel_data[9 ] <= Data_Read_Buffer[counter_hdmi * 24 + 9 ];
        pixel_data[10] <= Data_Read_Buffer[counter_hdmi * 24 + 10];
        pixel_data[11] <= Data_Read_Buffer[counter_hdmi * 24 + 11];
        pixel_data[12] <= Data_Read_Buffer[counter_hdmi * 24 + 12];
        pixel_data[13] <= Data_Read_Buffer[counter_hdmi * 24 + 13];
        pixel_data[14] <= Data_Read_Buffer[counter_hdmi * 24 + 14];
        pixel_data[15] <= Data_Read_Buffer[counter_hdmi * 24 + 15];
        pixel_data[16] <= Data_Read_Buffer[counter_hdmi * 24 + 16];
        pixel_data[17] <= Data_Read_Buffer[counter_hdmi * 24 + 17];
        pixel_data[18] <= Data_Read_Buffer[counter_hdmi * 24 + 18];
        pixel_data[19] <= Data_Read_Buffer[counter_hdmi * 24 + 19];
        pixel_data[20] <= Data_Read_Buffer[counter_hdmi * 24 + 20];
        pixel_data[21] <= Data_Read_Buffer[counter_hdmi * 24 + 21];
        pixel_data[22] <= Data_Read_Buffer[counter_hdmi * 24 + 22];
        pixel_data[23] <= Data_Read_Buffer[counter_hdmi * 24 + 23];
    end
    else begin
        //其他情况下，将其置为无效
        pixel_data <= 24'bz;
    end
end

always@(posedge sys_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //将数据请求信号复位
        hdmi_req <= 1'b0;
    end
    //保证在外部请求信号拉高之后的第三个时钟周期拉高数据请求信号
    else if(RdEn & (counter_rden == 1'b0))begin
        hdmi_req <= 1'b1;
    end
    //当计数器计满32位时将其置零
    else if(counter_hdmi == 5'd31)begin
        hdmi_req <= 1'b0;
    end
    //其他情况下，将其保持不变
    else begin
        hdmi_req <= hdmi_req;
    end
end

always@(posedge sys_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //读出数据的计数器复位
        counter_hdmi <= 5'd0;
    end
    //当数据请求信号拉高时就将计数器开始计数当计数到31位时将其清零
    else if(hdmi_req == 1'b1)begin
        if(counter_hdmi == 5'd31)begin
            counter_hdmi <= 5'd0;
        end
        else begin
            counter_hdmi <= counter_hdmi + 5'b1;
        end
    end
    else begin
        //如果请求信号没有拉高时就将其清零
        counter_hdmi <= 5'd0;
    end
end


fifo_top u_fifo_top(
.WrClk(clk_psram),        //psram用户的时钟信号
.RdClk(sys_clock),        //像素时钟信号
.Reset(~reset_n),         //psram存储器处理的相关模块的复位信号(注意，在配置ip核时，一定要考虑复位信号是低电平有效还是高电平有效)
.Full(),                  //fifo以写满的信号
.Empty(),                 //fifo数据已空的信号
.Data(Data),              //写入的数据(256位)
.WrEn(WrEn),              //写使能信号
.Q(OutData),              //读读出的信号
.RdEn(RdEn),              //读使能信号   
.Almost_Full(Almost_Full) //fifo的将满的信号 
);




endmodule