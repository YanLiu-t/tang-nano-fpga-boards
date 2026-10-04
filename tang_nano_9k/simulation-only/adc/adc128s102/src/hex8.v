module hex8(
    Clk,
    Reset_n,
    SEL,
    SEG,
    Disp_Data

);

    input Clk;
    input Reset_n;
    input [31:0]Disp_Data;
    output reg [7:0]SEL;
    output reg [7:0]SEG;

    parameter CLOCK_FREQ=50_000_000;  
    parameter TURN_FREQ=1000;
    parameter MCNT=CLOCK_FREQ/TURN_FREQ -1;

    reg[29:0]div_cnt;
    reg[2:0]cnt_sel;
    reg[3:0] data_temp;

    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        div_cnt<=0;
    else if(div_cnt==MCNT)
        div_cnt<=0;
    else
        div_cnt<=div_cnt+1'd1;


    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        cnt_sel<=0;
    else if(div_cnt==MCNT)
        cnt_sel<=cnt_sel+1'd1;

    always@(posedge Clk)
        case(cnt_sel)
            0:SEL<=8'b0000_0001;
            1:SEL<=8'b0000_0010;
            2:SEL<=8'b0000_0100;
            3:SEL<=8'b0000_1000;
            4:SEL<=8'b0001_0000;
            5:SEL<=8'b0010_0000;
            6:SEL<=8'b0100_0000;
            7:SEL<=8'b1000_0000;
        endcase


    always@(posedge Clk)
    case(data_temp)
        0: SEG <= 8'b1100_0000;//0
        1: SEG <= 8'b1111_1001;//1
        2: SEG <= 8'b1010_0100;//2
        3: SEG <= 8'b1011_0000;//3
        4: SEG <= 8'b1001_1001;//4
        5: SEG <= 8'b1001_0010;//5
        6: SEG <= 8'b1000_0010;//6
        7: SEG <= 8'b1111_1000;//7
        8: SEG <= 8'b1000_0000;//8
        9: SEG <= 8'b1001_0000;//9
        10: SEG <= 8'b1000_1000;//A
        11: SEG <= 8'b1000_0011;//b
        12: SEG <= 8'b1100_0110;//C
        13: SEG <= 8'b1010_0001;//d
        14: SEG <= 8'b1000_0110;//E
        15: SEG <= 8'b1000_1110;//F
    endcase

    always@(*)
    case(cnt_sel)
        0: data_temp <= Disp_Data[3:0];//0
        1: data_temp <= Disp_Data[7:4];//1
        2: data_temp <= Disp_Data[11:8];//2
        3: data_temp <= Disp_Data[15:12];//3
        4: data_temp <= Disp_Data[19:16];//4
        5: data_temp <= Disp_Data[23:20];//5
        6: data_temp <= Disp_Data[27:24];//6
        7: data_temp <= Disp_Data[31:28];//7
    endcase



endmodule