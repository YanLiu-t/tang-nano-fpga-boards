module uart_send(  
input sys_clock,
input sys_reset_n,

input [7:0]uart_tx_data,   //传入发送的数据
input uart_tx_en,           //发送一次数据的标志信号

output reg send_almost_end,    //发送将要结束,用来告知psram存储器

output wire uart_tx_busy,      //当前状态繁忙的信号
output reg uart_tx                //处理后的串行数据
);

     //一定要记住晶振频率        
parameter sys_fre = 27000000;    //系统时钟信号(Hz)       
parameter baudrate = 921600;       //执行的波特率



wire w_Isending;      //发送一次数据完成的提示内部信号

reg [7:0]SavedData;     //临时存储数据的容器


reg [3:0]Counter2;      //串行数据实现的位计数器
parameter MAX2 = 4'd9;


reg [29:0]CounterBT;       //串行数据实现的位间隔计数器
parameter MAX3 = sys_fre/baudrate - 30'd1;


reg EnableCounterBT;     //串行线性序列机的使能信号


assign uart_tx_busy = EnableCounterBT;      //标识繁忙的数据赋值


always@(posedge sys_clock,negedge sys_reset_n)begin
    if(sys_reset_n == 1'b0)begin
        send_almost_end <= 1'b0;
    end
    else if((Counter2 == MAX2) & (CounterBT == MAX3 - 3))begin
        send_almost_end <= 1'b1;
    end
    else begin
        send_almost_end <= 1'b0;
    end
end
//--------------------EnableCounterBT-----------------------------------------
always@(posedge sys_clock,negedge sys_reset_n)begin
if(sys_reset_n == 1'b0)
    EnableCounterBT <= 1'b0;
else if(w_Isending)
    EnableCounterBT <= 1'b0;             //收到结束信号时赋值0,收到外部使能信号时赋值1
else if(uart_tx_en)
    EnableCounterBT <= 1'b1;
else
    EnableCounterBT <= EnableCounterBT;
end
//---------------------------------------------------------------------------

//---------------------CounterBT计数器逻辑--------------------------
always@(posedge sys_clock,negedge sys_reset_n)begin
if(sys_reset_n == 1'b0)
    CounterBT <= 30'b0;
else if(EnableCounterBT)begin                  //由EnableCounterBT控制器的计数逻辑
    if(CounterBT == MAX3)
        CounterBT <= 30'b0;
    else
        CounterBT <= CounterBT + 30'b1;
end

else
    CounterBT <= 30'b0;
end
//------------------------------------------------------------

//---------------------Counter2计数器逻辑--------------------------
always@(posedge sys_clock or negedge sys_reset_n)begin
if(sys_reset_n == 1'b0)
    Counter2 <= 4'b0;
else if(CounterBT == MAX3)begin
    if(Counter2 == MAX2)
        Counter2 <= 4'b0;
    else
        Counter2 <= Counter2 + 4'b1;
end
else
    Counter2 <= Counter2;
end
//------------------------------------------------------------


//--------------------处理数据存储的逻辑-----------------------------
always@(posedge sys_clock,negedge sys_reset_n)begin
if(sys_reset_n == 1'b0)
    SavedData <= 8'b0000_0000;                              //接收到使能信号时，将当前的数据存入临时存储容器
else if(uart_tx_en)                                           
    SavedData <= uart_tx_data;
else
    SavedData <= SavedData;
end
//----------------------------------------------------------------


//--------------------------发送串口逻辑-----------------------------------
always@(posedge sys_clock or negedge sys_reset_n)begin          //线性序列机的判断逻辑      
    if(sys_reset_n == 1'b0)
        uart_tx <= 1'b1;   
    else if((Counter2 == 4'd0) & !EnableCounterBT)         //保证在不发数据的状态下Tx位1
        uart_tx <= 1'b1;
    else
        case(Counter2)    
            4'd0:        uart_tx <= 1'b0;        // 起始位
            4'd1:     uart_tx <= SavedData[0];
            4'd2:     uart_tx <= SavedData[1];
            4'd3:     uart_tx <= SavedData[2];
            4'd4:     uart_tx <= SavedData[3];
            4'd5:     uart_tx <= SavedData[4];
            4'd6:     uart_tx <= SavedData[5];
            4'd7:     uart_tx <= SavedData[6];
            4'd8:     uart_tx <= SavedData[7];
            4'd9:     uart_tx <= 1'b1;        // 停止位
            default:      uart_tx <= 1'b1;
        endcase
end
//-----------------------------------------------------------------------



//发送一次数据完成的提示内部信号的判断
assign w_Isending = (Counter2 == MAX2) & (CounterBT == MAX3);


endmodule