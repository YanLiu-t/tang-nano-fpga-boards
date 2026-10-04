module uart_byte_tx(
    Clk,
    Reset_n,
    Data,
    Send_Go,
    uart_tx,
//    Led,
    TX_done
);
    input  Clk;
    input Send_Go;
    input Reset_n;
    input [7:0]Data;
//    output reg Led;
    output reg uart_tx;
    output reg TX_done;

    parameter CLOCK_FREQ=50_000_000;
    parameter BAUD=9600;

    parameter MCNT_BAUD=CLOCK_FREQ/BAUD -1;
    parameter MCNT_BIT=10-1;
//    parameter MCNT_DLY=50000000-1;

    reg [29:0]baud_div_cnt; 
    reg en_baud_div_cnt;   

    reg [3:0]bit_cnt;
    reg [7:0]r_Data;
//    reg [25:0]delay_cnt;
    wire w_TX_done;

    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        en_baud_div_cnt<=0;
    else if(Send_Go)
        en_baud_div_cnt<=1;
    else if(w_TX_done)
        en_baud_div_cnt<=0;

    //波特率计数器
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        baud_div_cnt<=0;
    else if(en_baud_div_cnt) begin
        if(en_baud_div_cnt==MCNT_BAUD)
            baud_div_cnt<=13'd0;
        else
            baud_div_cnt<=baud_div_cnt+1'd1;
        end
    else
        baud_div_cnt<=13'd0;

  //  位计数器
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        bit_cnt<=4'd0;
        else if(baud_div_cnt==MCNT_BAUD) begin
        if(bit_cnt==MCNT_BIT)
            bit_cnt<=4'd0;
        else
            bit_cnt<=bit_cnt+1'd1;
        end
    else
        bit_cnt<=bit_cnt;


 //延时计数器
//  always@(posedge Clk or negedge Reset_n)
 //   if(!Reset_n)
 //       delay_cnt<=0;
 //   else if(delay_cnt==MCNT_DLY)
 //       delay_cnt<=0;
//    else
//        delay_cnt<=delay_cnt+1'd1;

   always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        r_Data<=0;
    else if(Send_Go)
        r_Data<=Data;
    else
        r_Data<=r_Data;



  //位发送逻辑
   always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        uart_tx<=0;
    else if(!en_baud_div_cnt)
        uart_tx<=1;
    else begin 
        case(bit_cnt)
            0:uart_tx<=1'd0;
            1:uart_tx<=r_Data[0];
            2:uart_tx<=r_Data[1];
            3:uart_tx<=r_Data[2];
            4:uart_tx<=r_Data[3];
            5:uart_tx<=r_Data[4];
            6:uart_tx<=r_Data[5];
            7:uart_tx<=r_Data[6];
            8:uart_tx<=r_Data[7];
            9:uart_tx<=1'd1;
            default:uart_tx<=uart_tx;
        endcase
    end
  //LED翻转逻辑
//  always@(posedge Clk or negedge Reset_n)
//    if(!Reset_n)
//        Led<=0;
//    else if((baud_div_cnt==MCNT_BAUD)&&(bit_cnt==MCNT_BIT))
//        Led<=~Led;

    assign w_TX_done=(baud_div_cnt==MCNT_BAUD)&&(bit_cnt==MCNT_BIT);
     always@(posedge Clk )
        TX_done<=w_TX_done;


endmodule