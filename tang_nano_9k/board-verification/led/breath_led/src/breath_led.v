module breath_led(
    input Clk,
    input Reset_n,
    output reg led

);

parameter MCNT_us=54-1;
parameter MCNT_ms_s=1000-1;

reg [5:0] cnt_us;
reg [9:0] cnt_ms;
reg [9:0] cnt_s;
reg flag;

//us
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        cnt_us<=0;
    else if(cnt_us==MCNT_us)
        cnt_us<=0;
    else
        cnt_us<=cnt_us+6'b1;

//ms
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        cnt_ms<=0;
    else if((cnt_ms==MCNT_ms_s)&&(cnt_us==MCNT_us))
        cnt_ms<=0;
    else if(cnt_us==MCNT_us)
        cnt_ms=cnt_ms+10'b1;
    else
        cnt_ms<=cnt_ms;

//s
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        cnt_s<=0;
    else if((cnt_ms==MCNT_ms_s)&&(cnt_us==MCNT_us)&&(cnt_s==MCNT_ms_s))
        cnt_s<=0;
    else if((cnt_ms==MCNT_ms_s)&&(cnt_us==MCNT_us))
        cnt_s<=cnt_s+10'b1;
    else
        cnt_s<=cnt_s;


//flag
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        flag<=0;
    else if((cnt_ms==MCNT_ms_s)&&(cnt_us==MCNT_us)&&(cnt_s==MCNT_ms_s))
        flag<=~flag;
    else
        flag<=flag;

//led
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        led<=0;
    else if((flag==1'b1&&cnt_ms>=cnt_s)||(flag==0&&cnt_ms<=cnt_s))
        led<=1'b1;
    else
        led<=0;

endmodule