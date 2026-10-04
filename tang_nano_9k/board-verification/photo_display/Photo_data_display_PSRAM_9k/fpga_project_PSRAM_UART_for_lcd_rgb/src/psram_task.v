//psram存储器的内部封装模块,主要负责对于psram单端口存储器内部的读写业务
module psram_task(
input sys_clock,           //系统的时钟信号 (27mhz)
input sys_reset_n,         //系统的复位信号
input global_reset_n,      //用户的复位信号
input memory_clk,          //psram的时钟信号
input lock,
input [20:0]ex_addr,       //从外部传进来的地址信号
input [255:0]ex_wr_data,    //外部写入的数据
output reg[255:0]ex_rd_data,//读取向外部的数据
output reg[1:0]status,     //状态机当前的状态哦
input ex_cmd,              //外部的读写控制信号(0--读  1--写)
input en_working_command,  //使能指令信号，为一时有效，开始读或者写
output reg task_finished,  //任务完成的信号(单一一次处理完写或者读时触发)
output init_calib,         //初始化完成信号,当初始化完成后其信号置为1
output clk_out,            //存储器ip核输出的（供用户使用）的信号

//这些信号为连接psram存储器内部的信号，只用带着他们引出主模块即可，不用配线
output [CS_WIDTH-1:0] O_psram_ck, 
output [CS_WIDTH-1:0] O_psram_ck_n,
inout [CS_WIDTH-1:0] IO_psram_rwds,
inout [DQ_WIDTH-1:0] IO_psram_dq,
output [CS_WIDTH-1:0] O_psram_reset_n,
output [CS_WIDTH-1:0] O_psram_cs_n 

);

//psram内部的一些参数
parameter CS_WIDTH = 2;
parameter DQ_WIDTH = 16;


  
//写数据时的缓冲容器(由于在定义时的数据宽度为64)
reg [63:0]wr_data;

//读写数据时的地址接口(2的21次方个地址,一个地址64位数据，所以一共8MB(64Mb)的数据)
reg [20:0]addr;

//读写的命令信号(0--读  1--写)
reg cmd;

//读写命令使能信号(高电平有效)
reg cmd_en;

//掩码信号(一个位数对应一个颗粒数，为1时盖住其颗粒，一个数据宽度为64位，一个颗粒为8位，所以其有八(64/8)位)
reg [7:0]data_mask;

//读数据的缓冲信号，根据数据宽度64位
wire [63:0]rd_data;

//读到数据的标志性信号(当读数据缓冲有信号时为高电平)
wire rd_data_valid;

//--------------current status------------------
parameter IDLE = 2'b00;   //标记当前状态为空闲状态
parameter WRITE = 2'b01;  //标记当前状态为写状态
parameter READ = 2'b10;   //标记当前状态为读状态
//--------------------------------------
//the target data width is 256,but the psram ip can only handle 64 in every single span of clock,
//so we mark the data width which was divided by 4  
reg [1:0]data_width_counter;

//the temporary register was tailored at saving the data from the external module when writing 
reg [255:0]tem_wr_data;

//状态机中使用的计数器(用于辅助实现时间的延迟)
reg[5:0]counter;


//---------------------------
//-------main code-----------
//---------------------------





//实例化psram存储器ip核
PSRAM_Memory_Interface_HS_Top psram(
.clk(sys_clock),               //输入系统的时钟信号(27mhz)
.memory_clk(memory_clk),       //psram存储器Ip核内部工作的时钟（144mhz）
.pll_lock(lock),               //从pll引出的时钟锁的信号
.rst_n(sys_reset_n),           //系统复位信号
.wr_data(wr_data),             //写数据时的缓冲容器(由于在定义时的数据宽度为64)
.addr(addr),                   //读写数据时的地址接口(2的21次方个地址,一个地址64位数据，所以一共8MB(64Mb)的数据)
.cmd(cmd),                     //读写的命令信号(0--读  1--写)
.cmd_en(cmd_en),               //读写命令使能信号(高电平有效)
.data_mask(data_mask),         //掩码信号(一个位数对应一个颗粒数，为1时盖住其颗粒，一个数据宽度为64位，一个颗粒为8位，所以其有八(64/8)位)
.rd_data(rd_data),             //读数据的缓冲信号，根据数据宽度64位
.rd_data_valid(rd_data_valid), //读到数据的标志性信号(（当读数据缓冲有信号）时为高电平)
.init_calib(init_calib),       //初始化完成信号,当初始化完成后其信号置为1
.clk_out(clk_out),             //存储器ip核输出的供用户使用的信号（为ip核内部工作时钟的一半,72mhz）

//这些信号为连接psram存储器内部的信号，只用带着他们引出主模块即可，不用配线
.O_psram_ck(O_psram_ck),
.O_psram_ck_n(O_psram_ck_n),
.IO_psram_rwds(IO_psram_rwds),
.IO_psram_dq(IO_psram_dq),
.O_psram_reset_n(O_psram_reset_n),
.O_psram_cs_n(O_psram_cs_n)
);

//---------------------------业务逻辑开始(用状态机实现读写)—----------------



//psram收发数据业务逻辑的状态机的实现逻辑
always@(posedge clk_out , negedge global_reset_n)begin
    //复位时将所有在其中改变的信号都赋值初始状态
    if(global_reset_n == 1'b0)begin
        status <= IDLE;
        task_finished <= 1'b0;
        counter <= 6'b0;
        wr_data <= 64'b0;
        addr <= 21'b0;
        cmd_en <= 1'b0;
        cmd <= 1'b0;
        data_width_counter <= 2'b0;
    end
    //ps存储器初始化完成后再执行后续操作
    else if(init_calib)begin
        //状态信号为空闲时执行的操作
        if(status == IDLE)begin  //以后写if时必加上begin end
            //保证在空闲状态时任务完成的信号一直置为低电平
            task_finished <= 1'b0;
            //当外部使能信号有效时，判断是读还是写
            if(en_working_command)begin
                //先把地址数据存进内部的变量(可不能把你给丢了)
                addr <= ex_addr;
                //判断读写的语句
                case(ex_cmd)
                    //如果是读状态，那就将状态转移为读
                    1'b0: begin status <= READ; data_width_counter <= 2'b0; end
                    //如果是写状态，那就把状态转移为写，并将外部的数据存入临时的容器
                    1'b1: begin status <= WRITE; tem_wr_data <= ex_wr_data; end
                endcase
                counter <= 6'b0;
            end
        end
        //状态信号为写数据中时执行的操作
        else if(status == WRITE)begin
            //如果计数器没有达到指标，就一直加一
            if(counter < 6'd16)begin
                counter <= counter + 6'b1;
            end
            //如果计数器达到指标，就将其清零，发起task_finished的信号,并且回到空闲的状态
            else begin
                counter <= 6'b0;
                task_finished <= 1'b1;
                status <= IDLE;
            end 
            //在计数器为0之后的这个时钟周期，打开掩码和命令
            if(counter == 6'b0)begin
                //将掩码都给我打开
                data_mask <= 8'b0000_0000;
                //打开使能信号
                cmd_en <= 1'b1;
                //赋值为写的命令
                cmd <= 1'b1;
                //将从高往低第一个64位数据写入
                wr_data <= tem_wr_data[255:192];
            end      
            else if(counter == 6'd1)begin
                //将掩码依然打开
                data_mask <= 8'b0000_0000;
                cmd_en <= 1'b0;
                //将从高往低第二个64位数据写入
                wr_data <= tem_wr_data[191:128];
            end
            else if(counter == 6'd2)begin
                //将掩码依然打开
                data_mask <= 8'b0000_0000;
                cmd_en <= 1'b0;
                //将从高往低第三个64位数据写入
                wr_data <= tem_wr_data[127:64];
            end
            else if(counter == 6'd3)begin
                //将掩码依然打开
                data_mask <= 8'b0000_0000;
                cmd_en <= 1'b0;
                //将从高往低第四个64位数据写入
                wr_data <= tem_wr_data[63:0];
            end
            //上述信号只能持续一个时钟周期，其他的周期都给我关了,因为我就是想要一次写一个数据单位(64位)
            else begin
                cmd_en <= 1'b0;
                //掩码全部都关闭,其他的数据我不想管
                data_mask <= 8'b1111_1111;
            end
        end
        //状态信号为读数据中时执行的操作
        else if(status == READ)begin
            //如果成功读到数据，那就将计数器清零，回到空闲的状态，然后发起task_finished的信号
            //并将读到的信号存进外部信号的变量
            if((rd_data_valid == 1'b1) & (data_width_counter == 2'b0)) begin
                //存入从高往低第一个的64位数据读出
                ex_rd_data[255:192] <= rd_data;
                //将数据单位计数器加一
                data_width_counter <= data_width_counter + 2'b1;
            end
            if((rd_data_valid == 1'b1) & (data_width_counter == 2'd1)) begin
                //存入低64位的数据
                ex_rd_data[191:128] <= rd_data;
                //将数据单位计数器加一
                data_width_counter <= data_width_counter + 2'b1;
            end
            if((rd_data_valid == 1'b1) & (data_width_counter == 2'd2)) begin
                //存入低64位的数据
                ex_rd_data[127:64] <= rd_data;
                //将数据单位计数器加一
                data_width_counter <= data_width_counter + 2'b1;
            end
            
            else if((rd_data_valid == 1'b1) & (data_width_counter == 2'd3))begin
                //存入高64位的数据
                ex_rd_data[63:0] <= rd_data;
                status <= IDLE;
                task_finished <= 1'b1;
                counter <= 6'b0;
                //将数据单位计数器归位
                data_width_counter <= 2'b0;
            end
            //不然就一直给计数器加一
            else begin
                counter <= counter + 6'b1;
            end
            //在计数器为0之后的这个时钟周期，打开掩码和命令
            if(counter == 6'b0)begin
                //将掩码都给我打开
                data_mask <= 8'b0000_0000;
                //打开使能信号
                cmd_en <= 1'b1;
                //赋值为读的命令
                cmd <= 1'b0;
            end     
            //上述信号只能持续一个时钟周期，其他的周期都给我关了,因为我就是想要一次读一个数据单位(64位)
            else begin
                cmd_en <= 1'b0;
                //掩码全部都关闭,其他的数据我不想要
                data_mask <= 8'b1111_1111;
            end
        end
    end
end

endmodule