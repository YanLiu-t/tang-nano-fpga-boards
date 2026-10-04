module uart_accept(
input sys_clock,
input sys_reset_n,
input uart_rx,
output reg [7:0]uart_rx_data,
output reg uart_rx_done
);

parameter BT = 921600;        //执行的波特率
parameter sys_freq = 27000000;     //系统时钟的信号

//-------------检测rx_dly下降边沿的信号---------------
reg HRX;

wire Negative;
//-------------消除亚稳态的逻辑变量--------------------
reg RX_dly0;

reg RX_dly1;
//----------------------------------------------


reg [7:0]Data_Internal;    //临时接收的变量

wire W_IsEnding;           //接受一次数据完成的提示内部信号



reg [15:0]CounterBT;             //串行数据实现的位间隔计数器
parameter MAX2 = sys_freq/BT - 1;   


reg [3:0]Counter2;              //串行数据实现的位计数器
parameter MAX3 = 10 - 1; 


reg EnCounterBT;                //串行线性序列机的使能信号

//-----------消除亚稳态的逻辑----------------------
always@(posedge sys_clock)
    RX_dly0 <= uart_rx;

always@(posedge sys_clock)
    RX_dly1 <= RX_dly0;
//---------------------------------------------

//----------------counterbt计数的逻辑-------------------------------
always@(posedge sys_clock , negedge sys_reset_n)begin
    if(sys_reset_n == 1'b0)
        CounterBT <= 16'b0;
    else if(EnCounterBT)begin                 //由EnableCounterBT控制器的计数逻辑
        if(CounterBT == MAX2)
            CounterBT <= 16'b0;
        else 
            CounterBT <= CounterBT + 16'b1;
    end
    else
        CounterBT <= 16'b0;
end
//------------------------------------------------------------------

//----------------Counter2-------------------------------------------
always@(posedge sys_clock , negedge sys_reset_n)begin
    if(sys_reset_n == 1'b0)
        Counter2 <= 4'b0;
    else if((CounterBT == MAX2/2) & (Counter2 == MAX3))       //最后一位数据走到一半就结束
        Counter2 <= 4'b0;
    else if(CounterBT == MAX2)
        Counter2 <= Counter2 + 4'b1;
    else
        Counter2 <= Counter2;
end
//------------------------------------------------------------------

//--------------Encounterbt计数的逻辑---------------------------------
always@(posedge sys_clock , negedge sys_reset_n)begin
    if(sys_reset_n == 1'b0)
        EnCounterBT <= 1'b0;
    else if(Negative)                             //检测到rx信号的下降沿赋值为1
        EnCounterBT <= 1'b1;
    else if((CounterBT == MAX2/2) & (Counter2 == 4'b0) & (uart_rx == 1'b1))        //如果满足此条件说明下降沿是假的，那就取消使能
        EnCounterBT <= 1'b0;
    else if(W_IsEnding)                            //检测到结束信号时关闭使能
        EnCounterBT <= 1'b0;
    else
        EnCounterBT <= EnCounterBT;
end
//------------------------------------------------------------------


//---------------------------Data_Internal采样的逻辑------------------------------
always@(posedge sys_clock , negedge sys_reset_n)begin
    if(sys_reset_n == 1'b0)
        Data_Internal <= 8'b1111_1111;
    else if(EnCounterBT & (CounterBT == MAX2/2))        //中值取样逻辑
        case(Counter2)                                   
            4'd1: Data_Internal[0] <= uart_rx;
            4'd2: Data_Internal[1] <= uart_rx;
            4'd3: Data_Internal[2] <= uart_rx;
            4'd4: Data_Internal[3] <= uart_rx;
            4'd5: Data_Internal[4] <= uart_rx;
            4'd6: Data_Internal[5] <= uart_rx;
            4'd7: Data_Internal[6] <= uart_rx;
            4'd8: Data_Internal[7] <= uart_rx;
            default: Data_Internal <= Data_Internal;
        endcase
    else
        Data_Internal <= Data_Internal;
end
//--------------------------------------------------------------------


//------------RX_dly1的下降沿检测逻辑---------------------
assign Negative = (~RX_dly1) & HRX;

always@(posedge sys_clock )
    HRX <= RX_dly1;
//-------------------------------------------------

always@(posedge sys_clock)            //外部信号与内部信号的联系
    uart_rx_done <= W_IsEnding;

always@(posedge sys_clock)            //接收到内部结束信号时，将当前的数据存入临时存储容器
    if(W_IsEnding)
        uart_rx_data <= Data_Internal;
        

assign W_IsEnding = (Counter2 == MAX3) & (CounterBT == MAX2/2);     //实现接受一次数据完成的提示内部信号

endmodule