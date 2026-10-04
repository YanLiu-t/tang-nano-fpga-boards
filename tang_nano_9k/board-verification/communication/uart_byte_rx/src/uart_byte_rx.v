module uart_byte_rx(
    Clk,
    Reset_n,
    uart_rx,
    Rx_Done,
    Rx_Data
);
    
    input Clk;
    input Reset_n;
    input uart_rx;
    output reg Rx_Done;
    output reg [7:0]Rx_Data;

    reg [29:0] baud_div_cnt;

    parameter CLOCK_FREQ=50_000_000;
    parameter BAUD=9600;

    parameter MCNT_BAUD=CLOCK_FREQ/BAUD -1;


    reg [3:0]bit_cnt;
    wire w_Rx_Done;
    wire nedge_uart_rx;
    reg en_baud_cnt;
    reg r_uart_rx;

    reg dff0_uart_rx;
    reg dff1_uart_rx;

    reg [7:0] r_Rx_Data;
    //波特率计数器
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        baud_div_cnt<=0;
    else if(en_baud_cnt)begin
        if(baud_div_cnt==MCNT_BAUD)
            baud_div_cnt<=0;
        else
            baud_div_cnt<=baud_div_cnt+1'd1;
        end
    else
        baud_div_cnt<=0;


    //波特率计数使能
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        en_baud_cnt<=0;
    else if(nedge_uart_rx)
        en_baud_cnt<=1;
    else if((baud_div_cnt==MCNT_BAUD/2)&&(bit_cnt==0)&&(dff1_uart_rx==1))
        en_baud_cnt<=0;
    else if((baud_div_cnt==MCNT_BAUD/2)&&(bit_cnt==9))
        en_baud_cnt<=0;


    //位计数器
//    always@(posedge Clk or negedge Reset_n)
//    if(!Reset_n)
//        bit_cnt<=0;
//    else if(baud_div_cnt==MCNT_BAUD) begin
//        if(bit_cnt==9)
//            bit_cnt<=0;
//        else
//            bit_cnt<=bit_cnt+1'd1;
//        end

        always@(posedge Clk or negedge Reset_n)
        if(!Reset_n)
            bit_cnt<=0;
        else if((baud_div_cnt==MCNT_BAUD/2)&&(bit_cnt==9))
            bit_cnt<=0;
        else if(baud_div_cnt==MCNT_BAUD)
            bit_cnt<=bit_cnt+1'd1;

    //位接收
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        r_Rx_Data<=8'd0;
    else if(baud_div_cnt==MCNT_BAUD/2) begin
        case(bit_cnt)
            1:r_Rx_Data[0]<=dff1_uart_rx;
            2:r_Rx_Data[1]<=dff1_uart_rx;
            3:r_Rx_Data[2]<=dff1_uart_rx;
            4:r_Rx_Data[3]<=dff1_uart_rx;
            5:r_Rx_Data[4]<=dff1_uart_rx;
            66:r_Rx_Data[5]<=dff1_uart_rx;
            7:r_Rx_Data[6]<=dff1_uart_rx;
            8:r_Rx_Data[7]<=dff1_uart_rx;
            default:r_Rx_Data<=r_Rx_Data;
        endcase
        end

    assign w_Rx_Done=(baud_div_cnt==MCNT_BAUD/2)&&(bit_cnt==9);

    always@(posedge Clk)
        Rx_Done<=w_Rx_Done;

     always@(posedge Clk)
        r_uart_rx<=dff1_uart_rx;

    assign nedge_uart_rx=(!dff1_uart_rx)&&r_uart_rx;


        dff0_uart_rx<=uart_rx;
        dff1_uart_rx<=dff0_uart_rx;
    end


    always@(posedge Clk) 
    if(w_Rx_Done)t 
        Rx_Data<=r_Rx_Data;

endmodule