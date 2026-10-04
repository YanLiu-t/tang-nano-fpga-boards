// 1.14 inch 的spi屏240_135的驱动模块for TANG NANO 9K 
module spi_screen_driver_240_135(
	input clk,                     // 27M的时钟信号
	input resetn,                  //系统的复位信号(低电平有效)
//---------------------
    input   start_display,         //开始显示数据图像的信号(由外部传进来)
    input   [15:0]pixel,           //像素的数据内容采用rgb5,6,5的模式标记色彩的

	output  lcd_resetn,            //spi屏的复位逻辑(低电平有效)
	output  lcd_clk,               //spi屏的时钟信号
	output  lcd_cs,                //低电平有效，低电平时，选中对应的spi屏幕设备,fpga可以对其进行读写操作
	output  lcd_rs,                //命令和数据选择信号,低电平时为读命令，高电平时为读数据
	output  lcd_data,              //spi屏接收的数据或者控制命令
//--------------------
    output  reg fifo_wr_start,         //向fifo写数据的标志信号
    output  reg fifo_read_go           //给fifo封装模块发出的数据申请信号
);

//定义240x135的spi屏的分辨率的大小(水平)
parameter h_disp = 240;    
//定义240x135的spi屏的分辨率的大小(垂直)
parameter v_disp = 135;

//标明Lcd屏的命令或数据的个数
localparam MAX_CMDS = 69;            
//spi接受的命令变量，一共70个，每个有9个位宽
wire [8:0] init_cmd[MAX_CMDS:0];     

//绘制每一帧像素之前要执行的命令，在INIT_WORKING状态时执行
assign init_cmd[ 0] = 9'h036;
assign init_cmd[ 1] = 9'h170;
assign init_cmd[ 2] = 9'h03A;
assign init_cmd[ 3] = 9'h105;
assign init_cmd[ 4] = 9'h0B2;
assign init_cmd[ 5] = 9'h10C;
assign init_cmd[ 6] = 9'h10C;
assign init_cmd[ 7] = 9'h100;
assign init_cmd[ 8] = 9'h133;
assign init_cmd[ 9] = 9'h133;
assign init_cmd[10] = 9'h0B7;
assign init_cmd[11] = 9'h135;
assign init_cmd[12] = 9'h0BB;
assign init_cmd[13] = 9'h119;
assign init_cmd[14] = 9'h0C0;
assign init_cmd[15] = 9'h12C;
assign init_cmd[16] = 9'h0C2;
assign init_cmd[17] = 9'h101;
assign init_cmd[18] = 9'h0C3;
assign init_cmd[19] = 9'h112;
assign init_cmd[20] = 9'h0C4;
assign init_cmd[21] = 9'h120;
assign init_cmd[22] = 9'h0C6;
assign init_cmd[23] = 9'h10F;
assign init_cmd[24] = 9'h0D0;
assign init_cmd[25] = 9'h1A4;
assign init_cmd[26] = 9'h1A1;
assign init_cmd[27] = 9'h0E0;
assign init_cmd[28] = 9'h1D0;
assign init_cmd[29] = 9'h104;
assign init_cmd[30] = 9'h10D;
assign init_cmd[31] = 9'h111;
assign init_cmd[32] = 9'h113;
assign init_cmd[33] = 9'h12B;
assign init_cmd[34] = 9'h13F;
assign init_cmd[35] = 9'h154;
assign init_cmd[36] = 9'h14C;
assign init_cmd[37] = 9'h118;
assign init_cmd[38] = 9'h10D;
assign init_cmd[39] = 9'h10B;
assign init_cmd[40] = 9'h11F;
assign init_cmd[41] = 9'h123;
assign init_cmd[42] = 9'h0E1;
assign init_cmd[43] = 9'h1D0;
assign init_cmd[44] = 9'h104;
assign init_cmd[45] = 9'h10C;
assign init_cmd[46] = 9'h111;
assign init_cmd[47] = 9'h113;
assign init_cmd[48] = 9'h12C;
assign init_cmd[49] = 9'h13F;
assign init_cmd[50] = 9'h144;
assign init_cmd[51] = 9'h151;
assign init_cmd[52] = 9'h12F;
assign init_cmd[53] = 9'h11F;
assign init_cmd[54] = 9'h11F;
assign init_cmd[55] = 9'h120;
assign init_cmd[56] = 9'h123;
assign init_cmd[57] = 9'h021;
assign init_cmd[58] = 9'h029;

assign init_cmd[59] = 9'h02A; // column
assign init_cmd[60] = 9'h100;
assign init_cmd[61] = 9'h128;
assign init_cmd[62] = 9'h101;
assign init_cmd[63] = 9'h117;
assign init_cmd[64] = 9'h02B; // row
assign init_cmd[65] = 9'h100;
assign init_cmd[66] = 9'h135;
assign init_cmd[67] = 9'h100;
assign init_cmd[68] = 9'h1BB;
assign init_cmd[69] = 9'h02C; // start

//此驱动模块使用了一个状态机来处理，对于spi屏幕的初始化，以及画面的绘制
//以下是通过常量定义了不同的状态

//复位时一共延迟100ms，此时的状态
localparam INIT_RESET   = 4'b0000; // delay 100ms while resetn   
//复位后等待200ms的状态
localparam INIT_PREPARE = 4'b0001; // delay 200ms after reset   
//书写发出唤醒spi的命令的状态，此状态后spi屏被唤醒  
localparam INIT_WAKEUP  = 4'b0010; // write cmd 0x11 MIPI_DCS_EXIT_SLEEP_MODE   
//当收到外部开始信号，则开始工作
localparam WAITINGTOWORK= 4'b0011; // wait to work when receiving the external start signal
//spi屏被唤醒之后再等待120ms的状态
localparam INIT_SNOOZE  = 4'b0100; // delay 120ms after wakeup    
//对spi屏书写init_cmd中的固有的命令和数据的状态(再绘制每一帧画面之前执行)
localparam INIT_WORKING = 4'b0101; // write command & data      
//就绪的状态（此时用于再spi屏上绘制(pixel有效的计数位0 -- 32399)的所有像素）
localparam INIT_DONE    = 4'b0110; // all done          

//此处用于区分对待仿真时和不仿真时的情况
`ifdef MODELTECH   

//分别定义100ms,120ms和200ms得计数间隔
localparam CNT_100MS = 32'd2700000 - 32'b1;
localparam CNT_120MS = 32'd3240000 - 32'b1;
localparam CNT_200MS = 32'd5400000 - 32'b1;

`else         

//此时的时间计数器计数时长缩短了，可以便于仿真用
// speedup for simulation
localparam CNT_100MS = 32'd27;
localparam CNT_120MS = 32'd32;
localparam CNT_200MS = 32'd54;

`endif

//用于标明状态机当前的状态
reg [ 3:0] init_state;     
//init_cmd的命令的索引，便于后续在INIT_WORKING状态时将其都传给spi屏
reg [ 6:0] cmd_index;      
//在时钟下的时钟计数器(便于在一些状态中实现 100ms , 120ms , 200ms 的延迟)
reg [31:0] clk_cnt;
       
//传以8位为单位的数据或指令时等待8个时钟周期的计数器
//(与后续的传数据的代码结合，实现从高位到低位，
//将八位数据,从并行数据，转为以时钟周期为单位，八个时钟周期的串行数据)
reg [ 4:0] bit_loop;      

//像素计数器(pixel有效的计数位0 -- 32399)来组成像240x135的spi屏，用于判断当前绘制
reg [15:0]pixel_cnt;



//-----------------对于外部输出的变量定义一个内部变量，直接连到外部-------------
//低电平有效，低电平时，选中对应的spi屏幕设备,fpga可以对其进行读写操作
reg lcd_cs_r;     
//命令和数据选择信号,低电平时为命令，高电平时为数据
reg lcd_rs_r;      
//spi屏的复位逻辑（低电平有效）
reg lcd_reset_r;    

//spi屏接收的数据或者控制命令（其为并行数据容器）
reg [7:0] spi_data;    
//------------------------------------------------------------------

//---------------------------------------------
//--------------main code----------------------
//---------------------------------------------

//对于外部输出的变量定义一个内部变量，直接连到外部

//spi屏的复位逻辑（低电平有效），用系统的复位信号赋值
assign lcd_resetn = lcd_reset_r;    
//spi屏的时钟信号，用系统时钟取反再赋值
assign lcd_clk    = ~clk;       
//低电平有效，低电平时，选中对应的spi屏幕设备,fpga可以对其进行读写操作
assign lcd_cs     = lcd_cs_r;  
//命令和数据选择信号,低电平时为读命令，高电平时为读数据      
assign lcd_rs     = lcd_rs_r;         
//spi屏接收的数据或者控制命令（一位串行数据）
//(与后续的传数据的代码结合，实现从高位到低位，
//将八位数据,从并行数据，转为以时钟周期为单位，八个时钟周期的串行数据)
assign lcd_data   = spi_data[7]; // MSB     


  
/*
//根据像素计数器(pixel有效的计数位0 -- 32399)来计算当前像素在x轴的坐标（注意：整个像素坐标系，我是让他从1开始的,所以最左上角的像素为(1,1)）
assign pixel_xpos = (pixel_cnt % h_disp) + 11'b1; 

 
// 11位目标位宽（用于防止警告）
wire [10:0] div_result; 
 
// 临时变量存储除法结果pixel_cnt / h_disp（用于防止警告）
wire [15:0] temp_div; 
   
//存储除法结果pixel_cnt / h_disp
assign temp_div = pixel_cnt / h_disp;

//转化为目标的11位宽
assign div_result = temp_div[10:0];

//根据像素计数器(pixel有效的计数位0 -- 32399)来计算当前像素在y轴的坐标（注意：整个像素坐标系，我是让他从1开始的,所以最左上角的像素为(1,1)）
assign pixel_ypos =  div_result + 11'b1;  
*/

//状态机的主体过程快
always@(posedge clk or negedge resetn) begin
    //复位的判断
	if (~resetn) begin
        //往fifo写数据的标志信号的复位
        fifo_wr_start <= 1'b0;
        //给fifo封装模块发出的数据申请信号的复位
        fifo_read_go <= 1'b0;
        //在时钟下的时钟计数器(便于在一些状态中实现 100ms , 120ms , 200ms 的延迟)赋值0
		clk_cnt <= 0;     
        //init_cmd的命令的索引，便于后续在INIT_WORKING状态时将其都传给spi屏，赋值0
		cmd_index <= 0;    
        //用于标明状态机当前的状态，赋值为复位状态
		init_state <= INIT_RESET;   
        //低电平有效，低电平时，选中对应的spi屏幕设备,fpga可以对其进行读写操作，赋值为无效
		lcd_cs_r <= 1;
        //命令和数据选择信号,低电平时为读命令，高电平时为读数据，赋值为读数据
		lcd_rs_r <= 1;
        //spi屏的复位逻辑（低电平有效），用系统的复位信号赋值，赋值为0，及复位保留状态，
		lcd_reset_r <= 0;
        //spi屏接收的并行数据容器赋值为全一
		spi_data <= 8'hFF;
        //传以8位为单位的数据或指令时等待8个时钟周期的计数器，初态时肯定为0，毕竟是计数八位，辅助串并转化的
		bit_loop <= 0;
        //像素计数器(pixel有效的计数位0 -- 32399)来组成像240x135的spi屏，用于判断当前绘制，初态赋值为0
		pixel_cnt <= 0;
        //如果开始显示的信号为一时就开始显示
	end else begin
        //状态机当前状态的选择
		case (init_state)
            //为spi屏执行复位的状态，计数器计数满100ms后松开复位转到下一状态
			INIT_RESET : begin
                //计数器计满时，松开复位，将clk_cnt时钟计数器清零，并转换到下一状态
				if (clk_cnt == CNT_100MS) begin        
					clk_cnt <= 0;
					init_state <= INIT_PREPARE;
					lcd_reset_r <= 1;
                //如果没计满时继续计数
				end else begin
					clk_cnt <= clk_cnt + 1;
				end
			end
            //复位之后等待200ms间隔时的状态
			INIT_PREPARE : begin     
                //计数器计满时,将clk_cnt时钟计数器清零，并转换到唤醒的状态
				if (clk_cnt == CNT_200MS) begin
					clk_cnt <= 0;
					init_state <= WAITINGTOWORK;
                //如果没计满时继续计数
				end else begin
					clk_cnt <= clk_cnt + 1;
				end
			end
            //唤醒后等待外部信号允许在开始工作
            WAITINGTOWORK:begin
                if(start_display)begin
                    init_state <= INIT_WAKEUP;
                end
            end
            //spi设备唤醒的状态
			INIT_WAKEUP : begin          
                //发送八位唤醒指令，以串行的方式
                //---------8位并行数据的串行转化逻辑--------------
				if (bit_loop == 0) begin
					// start
                    //选中对应的spi屏幕设备
					lcd_cs_r <= 0;
                    //赋值为0，说明是命令
					lcd_rs_r <= 0;
                    //此为八位的并行的唤醒指令
					spi_data <= 8'h11; // exit sleep 
                    //传以8位为单位的数据或指令时等待8个时钟周期的计数器
                    //将八位数据,从并行数据，转为以时钟周期为单位，八个时钟周期的串行数据)
					bit_loop <= bit_loop + 1;
				end else if (bit_loop == 8) begin    
                              // end
                    //此时关闭选中
					lcd_cs_r <= 1;       //关闭
                    //改为读数据
					lcd_rs_r <= 1;
                    //清零，便于下一次使用
					bit_loop <= 0;
					init_state <= INIT_SNOOZE;
				end else begin
					// loop
                    //并行数据转化为串行数据的核心逻辑(每更新一次bit_loop,就把低七位向高移动一位在将最低为赋值1，
                    //与前面对应assign lcd_data   = spi_data[7];)
					spi_data <= { spi_data[6:0], 1'b1 };
					bit_loop <= bit_loop + 5'b1;
				end
                //---------------------------------------
			end
            //唤醒完，用计数器等待120ms的状态
			INIT_SNOOZE : begin
                //计数器计满时，将clk_cnt时钟计数器清零，并转换到工作的状态
				if (clk_cnt == CNT_120MS) begin    
					clk_cnt <= 0;
					init_state <= INIT_WORKING;
                //如果没计满时继续计数
				end else begin
					clk_cnt <= clk_cnt + 1;
				end
			end

            //工作状态用于写一帧画面前将init_cmd的指令或数据传入spi
			INIT_WORKING : begin
                //此时通过cmd_index，判断init_cmd已经都发完了，都发完之后转到下一状态，开启传入像素数据信息
                if (cmd_index == MAX_CMDS + 1) begin    
                    bit_loop <= 0;
					init_state <= INIT_DONE;
                    cmd_index <= 0;
				end 
                else begin
                    //按照索引，把init_cmd的数据或命令依次发送
                    //(bit_loop, spi_data的范式与唤醒状态介绍的一样，此处不重点介绍)
                    //---------8位并行数据的串行转化逻辑--------------
                    if (bit_loop == 0) begin     
						// start                  
                        lcd_cs_r <= 0;
                        //init_cmd最高位标记是否为数据或指令
						lcd_rs_r <= init_cmd[cmd_index][8];    
                        //init_cmd其余为标记内容
                        spi_data <= init_cmd[cmd_index][7:0];   
						bit_loop <= bit_loop + 1;
                    end 
                    else if (bit_loop == 8) begin
						// end
                        //此时关闭选中
						lcd_cs_r <= 1;    //关闭
                        //改为读数据
						lcd_rs_r <= 1;     
						bit_loop <= 0;
                        //init_cmd索引加一，切换到init_cmd的下一个数据
						cmd_index <= cmd_index + 7'b1; // next command
					end 
                    else begin
						// loop
                        //传以8位为单位的数据或指令时等待8个时钟周期的计数器
                        //将八位数据,从并行数据，转为以时钟周期为单位，八个时钟周期的串行数据)
						spi_data <= { spi_data[6:0], 1'b1 };
						bit_loop <= bit_loop + 5'b1;
					end
                    //当工作状态刚开始时,发出开始写fifo的标志,(再场扫描之前就打开写fifo的操作,防止写扫描向fifo读数据时读空)
                    if((bit_loop == 0) & (cmd_index == 0))begin
                        fifo_wr_start <= 1'b1;
                    end
                    //拉高一个时钟周期后就将其拉低
                    else begin
                        fifo_wr_start <= 1'b0;
                    end
                    //根据设计的时序,提前将申请数据的信号拉高一个时钟周期
                    //一次申请16个16位的像素点数据,并在fifo_controler中产生与此模块对应的pixel变化时序
                    if((bit_loop == 5) & (cmd_index == MAX_CMDS))begin
                        fifo_read_go <= 1'b1;
                    end
                    //拉高一个时钟周期之后就将其拉低
                    else begin
                        fifo_read_go <= 1'b0;
                    end
                    //----------------------------------------------
				end
			end
            //正常绘图的状态，重点看（将每个像素的信息传给spi的状态）
			INIT_DONE : begin          
                //（pixel有效的计数位0 -- 32399）当为32400是停止逻辑触发
				if (pixel_cnt == 32400) begin     
                    //转到working模块，继续绘制下一帧
                    init_state <= INIT_WORKING;    
                    //像素计数器清零，便于后续的帧绘制使用 
                    pixel_cnt <= 0;       
					 // stop
				end 
                else begin
                    //每一次的bit_loop计数都会传输16位的像素数据(也就是rgb(5,6,5)的像素格式
                    //----------------16位(pixel)并行数据转化为串行数据的实现——---------------
                    //(bit_loop, spi_data的范式与唤醒状态介绍的一样，此处不重点介绍)
					if (bit_loop == 0) begin      
						// start                   
                        //0开启，1关闭，此为开启
						lcd_cs_r <= 0;    
                        //1证明是传数据
						lcd_rs_r <= 1;    
                        //将高八位像素数据赋给spi_data容器，便于后续并串转化
						spi_data <= pixel[15:8];            
						bit_loop <= bit_loop + 1;
					end 
                    else if (bit_loop == 8) begin
						// next byte
                        //将低八位像素数据赋给spi_data容器，便于后续并串转化
						spi_data <= pixel[7:0];             
						bit_loop <= bit_loop + 1;
					end 
                    else if (bit_loop == 16) begin
						// end
                        //此时关闭spi选中
						lcd_cs_r <= 1;     
                        //改为读数据
						lcd_rs_r <= 1;
						bit_loop <= 0;
                        //结束一个像素，切换到下一个像素，像素计数器加一
						pixel_cnt <= pixel_cnt + 16'b1; // next pixel     
					end 
                    else begin
						// loop
                        //传以8位为单位的数据或指令时等待8个时钟周期的计数器
                        //将八位数据,从并行数据，转为以时钟周期为单位，八个时钟周期的串行数据)
						spi_data <= { spi_data[6:0], 1'b1 };
						bit_loop <= bit_loop + 5'b1;
					end
                    //当到达一定阶段时,就打开申请信号,从fifo申请数据
                    //一次申请16个16位的像素点数据,并在fifo_controler中产生与此模块对应的pixel变化时序
                    if((((pixel_cnt + 16'b1) % 16) == 0) & (pixel_cnt < 32399) & (bit_loop == 12))begin
                        fifo_read_go <= 1'b1;
                    end
                    //拉高一个时钟沿就拉低,
                    else begin
                        fifo_read_go <= 1'b0;
                    end
                    //-----------------------------------------------------
				end
			end
		endcase
	end
end

endmodule