module MAIN_TASK(
input sys_clock,      //系统时钟信号(27mhz)
input sys_reset_n,    //系统的复位信号
//串口的发送端和接收端
input uart_rx,        //串口接收的信号(串行的数据)
output uart_tx,       //串口发送的信号(串行的数据)
//这些信号为连接psram存储器内部的信号，只用带着他们引出主模块即可，不用配线
output [CS_WIDTH-1:0] O_psram_ck, 
output [CS_WIDTH-1:0] O_psram_ck_n,
inout [CS_WIDTH-1:0] IO_psram_rwds,
inout [DQ_WIDTH-1:0] IO_psram_dq,
output [CS_WIDTH-1:0] O_psram_reset_n,
output [CS_WIDTH-1:0] O_psram_cs_n, 
 //RGB LCD 接口
output lcd_de,       //LCD 数据使能信号
output lcd_hs,       //LCD 行同步信号
output lcd_vs,       //LCD 场同步信号
output lcd_clk,      //LCD 像素时钟
output [15:0] lcd_rgb//LCD RGB565 颜色数据
);

//psram接口位宽用到的参数
parameter CS_WIDTH = 2;
parameter DQ_WIDTH = 16;

//--------存储器封装模块的io信号-----------------
//从外部传进来的地址信号
reg [20:0]ex_addr;      
//从外部写入的数据
reg [255:0]ex_wr_data;  
//读取向外部的数据      
wire [255:0]ex_rd_data;   
//外部的读写控制信号(0--读  1--写)
reg ex_cmd;
//使能指令信号，为一时有效，开始读或者写
reg en_working_command;
//任务完成的信号(单一一次处理完写或者读时触发)
wire task_finished;    
//初始化完成信号,当初始化完成后其信号置为1
wire init_calib;         
//存储器ip核输出的（供用户使用）的信号
wire clk_out;    
//存储器内部状态机当前的状态哦       
wire [1:0]in_status;
//---------------------------------------------

//-------串口通信接收模块的io信号------------------
//串口通信接收到的8位并行数据
wire [7:0]uart_rx_data;
//串口通信八位并行数据接收到数据的标志 
wire uart_rx_done;
//---------------------------------------------

//-------串口通信发送模块的io信号------------------
//传入uart_send模块中的即将发送的8位并行数据
reg [7:0]uart_tx_data;
//发送一次数据的标志信号
reg uart_tx_en;
//标识当前繁忙的状态（1时为繁忙）
wire uart_tx_busy;
//---------------------------------------------

//-------用户业务逻辑的变量声明-------------------
//--------------------------
parameter WRITE = 2'b00;    //当前在往psram里写数据
parameter READ = 2'b01;     //当前在往psram外读数据
parameter DISPLAY = 2'b10;  //当前正在hdmi上显示
//--------------------------
//表示当前用户任务状态机当前的状态
reg [1:0]status;
//存储器的一个数据单位64位，串口收发一次8位数据
//所以需要一个8位的计数器，来标记
reg [5:0]BitCounter;
//一共391680字节数据，一批处理256位的数据，所以一共要处理(391680* 8)/256 = 12240 批数据
//处理数据的总批数
parameter HandlingTime = 12240;  
//处理数据的总批数的计数器
reg [17:0]HandlingTimeCounter;
//64位读写数据的缓冲变量
reg [255:0]DataWaitingBuffer;
//用户这边的地址缓冲区
reg [20:0]user_addr;
//在读数据的时候标记当前状态为向串口发送数据
reg IsSending;
//辅助读写的计数器，用于打拍，延迟一个时钟周期
reg [2:0]Counter;
//是否向fifo写数据
reg IsWriting;
//hdmi显示时,当前的行数
reg [9:0]current_roll;
//在屏幕显示时当前的状态
reg [1:0]display_status;
//向psram读数据的辅助规范信号(请求信号的锁)使时序更加清晰
reg psram_read_flag;
//上述信号的打拍信号,用于延后一个时钟周期
reg psram_read_flag_d;
//------显示时标记不同状态的常数---------
parameter DIS_IDLE    = 2'b00;  //空闲,等待写数据的申请信号
parameter DIS_WRITE   = 2'b01;  //正在往fifo写数据
parameter DIS_WAITING = 2'b10;  //fifo已满，等待
//-----------------------------------
//--------------------------------------------

//----------lcd驱动模块的一些参数及信号---------
//外部模块向driver发送的像素信息 
wire [15:0]pixel_data;
//场有效数据开始信号
wire vs_begin;
//一级消除亚稳态
reg vs_begin_d0;
//二级消除亚稳态
reg vs_begin_d1;
//让lcd屏开始显示的信号
reg start_lcd_display;
reg start_lcd_display_d0;
reg start_lcd_display_d1;
//fifo开始读出数据的使能信号
wire fifo_read_go;
//-------------------------------------------

//---------------fifo的控制模块的参数-----------
//fifo内部传来的将满的信号 
wire Almost_Full;
//fifo的写使能
reg WrEn;
//向fifo中直接写入的数据接口
reg [255:0]fifo_Data;
//-------------------------------------------

//-------------全局pll的参数-------------------
//锁相环传出的锁信号
wire lock;
//psram存储器工作的时钟
wire memory_clk;
//全局复位信号
wire global_reset_n;
//-------------------------------------------

//------------时钟分频模块参数------------------
//屏幕的id
parameter lcd_id = 16'h4342;
//屏幕的像素时钟
wire lcd_pclk;
//-------------------------------------------
//---------------------------
//-------main code-----------
//---------------------------

//例化时钟分频模块(由于一个pll无法产生指定频率的像素时钟，故直接手动分频)
clk_div u_clk_div(
.clk(sys_clock),        //系统的时钟频率(27mhz)
.rst_n(sys_reset_n),    //系统的复位信号
.lcd_id(lcd_id),        //屏幕的型号
.lcd_pclk(lcd_pclk)     //传出来的像素时钟
);


//例化pll的ip核模块
Gowin_rPLL u_Gowin_rPLL(
.clkin(sys_clock),         //输入系统的时钟信号(27mhz)
.reset(~sys_reset_n),      //输入系统的复位信号
.lock(lock),               //输出时钟锁信号
.clkout(memory_clk)        //psram存储器Ip核内部工作的时钟（144mhz）
);

//将复位信号经过锁相环过滤，得到更加稳定的复位信号,所有时钟域均用此信号
assign global_reset_n = (lock & sys_reset_n);

//实例化psram存储器封装模块
psram_task u_psram_task(
.sys_clock(sys_clock),                     //输入系统的时钟信号(27mhz)
.sys_reset_n(sys_reset_n),                 //系统的复位信号
.memory_clk(memory_clk),                   //psram自身的时钟信号
.lock(lock),                               //pll的锁信号
.ex_addr(ex_addr),                         //从外部传进来的地址信号
.ex_wr_data(ex_wr_data),                   //外部写入的数据
.ex_rd_data(ex_rd_data),                   //读取向外部的数据
.ex_cmd(ex_cmd),                           //外部的读写控制信号(0--读  1--写)
.en_working_command(en_working_command),   //使能指令信号，为一时有效，开始读或者写
.task_finished(task_finished),             //任务完成的信号(单一一次处理完写或者读时触发)
.init_calib(init_calib),                   //初始化完成信号,当初始化完成后其信号置为1
.clk_out(clk_out),                         //存储器ip核输出的（供用户使用）的信号
.global_reset_n(global_reset_n),           //经过pll之后的复位信号(供用户使用)
.status(in_status),                        //存储器内部状态机当前的状态哦

//这些信号为连接psram存储器内部的信号，只用带着他们引出主模块即可，不用配线
.O_psram_ck(O_psram_ck),
.O_psram_ck_n(O_psram_ck_n),
.IO_psram_rwds(IO_psram_rwds),
.IO_psram_dq(IO_psram_dq),
.O_psram_reset_n(O_psram_reset_n),
.O_psram_cs_n(O_psram_cs_n)
);


//实例化串口通信的接收模块
uart_accept 
#(
.sys_freq(72_000_000),
.BT(921600)
)u_uart_accept(
.sys_clock(clk_out),               //存储器ip核输出的（供用户使用）的信号
.sys_reset_n(global_reset_n),        //经过pll之后的复位信号(供用户使用)
.uart_rx(uart_rx),                 //串口接收的信号(串行的数据)
.uart_rx_data(uart_rx_data),       //串口通信接收到的8位并行数据
.uart_rx_done(uart_rx_done)        //串口通信八位并行数据接收到数据的标志 
);

//实例化串口通信的发送模块
uart_send 
#(
.sys_fre(72_000_000),
.baudrate(921600)
)u_uart_send(
.sys_clock(clk_out),               //存储器ip核输出的（供用户使用）的信号
.sys_reset_n(global_reset_n),      //经过pll之后的复位信号(供用户使用)
.uart_tx(uart_tx),                 //串口发送的信号(串行的数据)
.uart_tx_data(uart_tx_data),       //传入此模块中的即将发送的8位并行数据
.uart_tx_busy(uart_tx_busy),       //标识当前繁忙的状态（1时为繁忙）
.uart_tx_en(uart_tx_en)            //发送一次数据的标志信号
);


//实例化fifo的控制模块
fifo_controler u_fifo_controler(
.reset_n(global_reset_n),          //全局的复位信号
//psram存储器时钟域的信号
.clk_psram(clk_out),               //psram用户的时钟信号(读时钟)
.WrEn(WrEn),                       //fifo的写使能信号
.Data(fifo_Data),                  //写入fifo的数据
.Almost_Full(Almost_Full),         //fifo内部传来的将满的信号 
//像素时钟域的信号
.pix_clock(lcd_pclk),              //像素时钟(写时钟)
.fifo_read_go(fifo_read_go),       //从fifo读数据的请求信号
.pixel_data(pixel_data)            //lcd屏数据的扫描显示信号(读出的数据)
);

//LCD 驱动模块
 lcd_driver u_lcd_driver(
.pixel_clock (lcd_pclk ),          //像素的时钟
.reset_n (global_reset_n ),        //全局复位的信号
.en_cnt(start_lcd_display_d1),     //h_cnt 和 v_cnt 计数器使能信号
.lcd_id ( lcd_id ),                //指示lcd屏的型号(分辨率)的信号
.pixel_data (pixel_data),          //外部输入的rgb565的数据用于lcd的显示
.lcd_de (lcd_de ),                 //LCD 数据使能信号
.lcd_hs (lcd_hs ),                 //LCD 行同步信号
.lcd_vs (lcd_vs ),                 //LCD 场同步信号
.lcd_bl ( ),                       //LCD 背光控制信号 
.lcd_clk (lcd_clk ),               //LCD 像素时钟
.lcd_rst ( ),                      //LCD 复位
.lcd_rgb (lcd_rgb ),               //输出的RGB565 颜色数据
.vs_begin(vs_begin),               //场有效结束的信号
.fifo_read_go(fifo_read_go)        //从fifo申请32个24位宽的数据的信号
);

//给开始进行显示的信号消除亚稳态(同步到像素时钟域内)
always@(posedge lcd_pclk , negedge global_reset_n)begin
    if(global_reset_n == 1'b0)begin
        //第一级消除亚稳态的信号
        start_lcd_display_d0 <= 1'b0;
        //第一级消除亚稳态的信号
        start_lcd_display_d1 <= 1'b0;
    end 
    else begin
        //第一级消除亚稳态的操作
        start_lcd_display_d0 <= start_lcd_display;
        //第二级消除亚稳态的操作
        start_lcd_display_d1 <= start_lcd_display_d0;
    end
end

//解决用户的业务逻辑的状态机
always@(posedge clk_out , negedge global_reset_n)begin
    //将在状态机中改变的变量全部赋值为初始值
    if(global_reset_n == 1'b0)begin
        psram_read_flag <= 1'b0;
        psram_read_flag_d <= 1'b0;
        display_status <= DIS_IDLE;
        status <= WRITE;
        BitCounter <= 6'b0;
        ex_addr <= 21'b0;
        user_addr <= 21'b0;
        HandlingTimeCounter <= 18'b0;
        DataWaitingBuffer <= 256'b0;
        ex_cmd <= 1'b1;
        IsSending <= 1'b0;
        uart_tx_en <= 1'b0;
        Counter <= 3'b0;
        en_working_command <= 1'b0;
        WrEn <= 1'b0;
        fifo_Data <= 256'b0;
        start_lcd_display <= 1'b0;
    end
    //等待状态机初始化完成在进入状态机
    else if(init_calib)begin
        //当前的任务为写时执行的操作
        if(status == WRITE)begin
            //如果接收信号标志有效时就将八位串口接收的数据存入256位缓冲变量
            if(uart_rx_done)begin
                DataWaitingBuffer[BitCounter * 8 + 0] <= uart_rx_data[0];
                DataWaitingBuffer[BitCounter * 8 + 1] <= uart_rx_data[1];
                DataWaitingBuffer[BitCounter * 8 + 2] <= uart_rx_data[2];
                DataWaitingBuffer[BitCounter * 8 + 3] <= uart_rx_data[3];
                DataWaitingBuffer[BitCounter * 8 + 4] <= uart_rx_data[4];
                DataWaitingBuffer[BitCounter * 8 + 5] <= uart_rx_data[5];
                DataWaitingBuffer[BitCounter * 8 + 6] <= uart_rx_data[6];
                DataWaitingBuffer[BitCounter * 8 + 7] <= uart_rx_data[7];
                //此时并将位计数器加一，选中缓冲区的下一个位置
                BitCounter <= BitCounter + 6'b1;
            end
            //如果计数器变为32时,说明缓冲区已被计满,将其清零
            if(BitCounter == 6'd32)begin
                BitCounter <= 6'b0;  
                //将批数的计数器加一
                HandlingTimeCounter <= HandlingTimeCounter + 18'b1;
            end
            //如果计数器变为32时,说明缓冲区已被计满,并且当前存储器空闲时，启动存储器
            if((BitCounter == 6'd32) & (in_status == 2'b00))begin
                //将缓冲区里的数据传入存储器内部引出的信号
                ex_wr_data <= DataWaitingBuffer;
                //给存储器传递使能命令
                en_working_command <= 1'b1;
                //将地址赋值进存储器封装模块内部引出来的地址
                ex_addr <= user_addr;
                //将用户的地址加8,因为每个地址对应的是4个字节，而读写数据每次都要整32个字节
                //故读写一次占两个地址,所以每次加二
                user_addr <= user_addr + 21'd8;
                //将当前的读写指令调成写的状态
                ex_cmd <= 1'b1;
            end 
            //否则将en_working_command置备为0
            else begin
                en_working_command <= 1'b0; 
            end
            //如果批次达到目标批次,并且末尾的批次给存储器写数据的任务完成时，转移到读状态，并将一些数据归位
            if((HandlingTimeCounter == HandlingTime) & task_finished)begin
                user_addr <= 21'b0;
                HandlingTimeCounter <= 18'b0;
                BitCounter <= 6'b0;
                status <= READ;
            end
                
        end
        //当前的任务为读时执行的操作
        else if(status == READ)begin
            //打拍的计数器
            //Counter：你知道我为什莫打拍吗，嘿嘿，我可是团队里的骨干，当启动存储器和串口发送模块时，他的工作信号总是要隔一个时钟周期才被唤醒
            //如果是这样的话，下面的一些条件判断就会在两个相邻的时钟沿被激活两次，这可是很危险，很头疼的，
            //那怎末办呢，我就来了,条件判断只要是带上我，那么在两个相邻的周期就别想连续触发了！
            if(Counter == 3'b1)begin
                Counter <= 3'b0;
            end
            else begin
                Counter <= Counter + 3'b1;
            end

            if(task_finished)begin
                //将读到的信息存入临时的缓冲容器
                DataWaitingBuffer <= ex_rd_data;
                //并进入发送的状态
                IsSending <= 1'b1;
            end
            //当当前的存储器状态在空闲且IsSending无效即在非发送的状态时
            else if((Counter == 3'b1) & (in_status == 2'b00) & (IsSending == 1'b0))begin
                //给存储器传递使能命令
                en_working_command <= 1'b1;
                //将当前的读写指令调成读的状态
                ex_cmd <= 1'b0;
                //将地址赋值进存储器封装模块内部引出来的地址
                ex_addr <= user_addr;
                //将用户的地址加8,因为每个地址对应的是4个字节，而读写数据每次都要整32个字节
                //故读写一次占两个地址,所以每次加8
                user_addr <= user_addr + 21'd8;
            end
            //当存储器当前的任务完成时执行的操作 
            else begin
                en_working_command <= 1'b0;
            end
            //当位计数器置为32时，批次的计数器置为预定的数据，即最后一批数据以都发送完成，
            if((BitCounter == 6'd32) & (HandlingTimeCounter == (HandlingTime - 18'b1)))begin
                status <= DISPLAY;
                HandlingTimeCounter <= 18'b0;
                BitCounter <= 6'b0;
                IsSending <= 1'b0;
                user_addr <= 21'b0;
            end
            //如果当前在发送状态并且发送的模块处于非繁忙的状态时,就将读取到的256位数据统统让串口发送出去
            if((Counter == 3'b1) & IsSending & (!uart_tx_busy))begin
                //将串口发送的使能端置为1
                uart_tx_en <= 1'b1;
                uart_tx_data[0] <=  DataWaitingBuffer[BitCounter * 8 + 0];
                uart_tx_data[1] <=  DataWaitingBuffer[BitCounter * 8 + 1];
                uart_tx_data[2] <=  DataWaitingBuffer[BitCounter * 8 + 2];
                uart_tx_data[3] <=  DataWaitingBuffer[BitCounter * 8 + 3];
                uart_tx_data[4] <=  DataWaitingBuffer[BitCounter * 8 + 4];
                uart_tx_data[5] <=  DataWaitingBuffer[BitCounter * 8 + 5];
                uart_tx_data[6] <=  DataWaitingBuffer[BitCounter * 8 + 6];
                uart_tx_data[7] <=  DataWaitingBuffer[BitCounter * 8 + 7];
                //此时并将位计数器加一，选中缓冲区的下一个位置
                BitCounter <= BitCounter + 6'b1;
            end
            //拉高一个时钟周期之后将串口发送的使能信号置为0
            else begin
                uart_tx_en <= 1'b0;
            end
            //当八位计数器为32时，证明一个从存储器读到的256为数据发送操作以全部完成，
            if((BitCounter == 6'd32) & (HandlingTimeCounter != (HandlingTime - 18'b1)))begin
                //将8位的计数器清零
                BitCounter <= 6'b0;
                //将issending拜到0，开始申请下一波数据
                IsSending <= 1'b0;
                //将数据批次的计数器加一
                HandlingTimeCounter <= HandlingTimeCounter + 18'b1;
            end
        end
        //当前正在hdmi上显示
        else if(status == DISPLAY)begin
            //打开hdmi显示的使能
            start_lcd_display <= 1'b1;
            //判断当前的显示状态
            case(display_status)
                //空闲时执行的操作(等待像素模块发来的场扫描开始信号)
                DIS_IDLE:begin
                    //当接收到场扫描开始信号时,将状态跳转到写状态,
                    //psram_read_flag申请数据锁有效,地址数据批次计数器清零。
                    if(vs_begin_d1)begin
                        display_status <= DIS_WRITE;
                        psram_read_flag <= 1'b1;
                        psram_read_flag_d <= 1'b0;
                        HandlingTimeCounter <= 18'b0;
                        user_addr <= 21'b0;
                    end
                end
                DIS_WRITE:begin
                    //当存储器空闲，申请数据锁有效，且fifo没有将要满,数据批次没有计满,就开始申请128位数据
                    if((in_status == 2'b00) & psram_read_flag & !Almost_Full & (HandlingTimeCounter != HandlingTime))begin
                        //触发一次就将其失效
                        psram_read_flag <= 1'b0;
                        //给存储器传递使能命令
                        en_working_command <= 1'b1;
                        //将当前的读写指令调成读的状态
                        ex_cmd <= 1'b0;
                        //将地址赋值进存储器封装模块内部引出来的地址
                        ex_addr <= user_addr;
                        //将用户的地址加4,因为每个地址对应的是4个字节，而读写数据每次都要整32个字节
                        //故读写一次占8个地址,所以每次加8
                        user_addr <= user_addr + 21'd8;
                        //每次将批数加一
                        HandlingTimeCounter <= HandlingTimeCounter + 18'b1;
                    end
                    else begin
                        //其他条件下，将申请数据使能信号拉低
                        en_working_command <= 1'b0;
                    end
                    //当此标志拉高时说明申请到了数据
                    if(task_finished)begin
                        //将读到的数据存入fifo写的缓冲区
                        fifo_Data <= ex_rd_data;
                        //打开fifo的写使能
                        WrEn <= 1'b1;
                        //当一批数据完成时将其打拍信号激活
                        psram_read_flag_d <= 1'b1;
                    end
                    else begin
                        //打开一个时钟周期后关闭
                        WrEn <= 1'b0;
                    end
                    //监测打拍信号是否激活
                    if(psram_read_flag_d)begin
                        //如果识别到打开就将其关闭
                        psram_read_flag_d <= 1'b0;
                        //释放申请数据锁
                        psram_read_flag <= 1'b1;
                    end
                    //当写数据使能拉高时,做出跳转判断
                    if(psram_read_flag)begin
                        //如果批次写够标准，就回到空闲状态，等待下一帧的开始信号,同时将一些计数器归位
                        if(HandlingTimeCounter == HandlingTime)begin
                            display_status <= DIS_IDLE;
                            HandlingTimeCounter <= 18'b0;
                            user_addr <= 21'b0;
                        end
                        //如果此时触发将满的阈值，及说明本批数据写完，如果fifo不读出数据的话，就不能再写一批数据了,
                        //所以跳转到等待状态，等fifo有足够空间后再进行写
                        else if(Almost_Full)begin
                            display_status <= DIS_WAITING;
                        end
                    end
                end
                //fifo已经满时等待的状态
                DIS_WAITING:begin
                    //当将满标志消除时,说明fifo一定有足够的空间了,这时回到写状态,并将申请数据锁置为有效
                    if(!Almost_Full)begin
                        display_status <= DIS_WRITE;
                        psram_read_flag <= 1'b1;
                        psram_read_flag_d <= 1'b0;
                    end
                end
            endcase
        end
    end
end





//注意：还要将vs_end等一系列在lcd模块中的写标志信号消除亚稳态
always@(posedge clk_out , negedge global_reset_n)begin
    //将在状态机中改变的变量全部赋值为初始值
    if(global_reset_n == 1'b0)begin
        //第一级消除亚稳态的信号
        vs_begin_d0 <= 1'b0;
        //第二级消除亚稳态的信号
        vs_begin_d1 <= 1'b0;
    end
    else begin
        //第一级消除亚稳态
        vs_begin_d0 <= vs_begin;
        //第二级消除亚稳态
        vs_begin_d1 <= vs_begin_d0;
    end
end

endmodule