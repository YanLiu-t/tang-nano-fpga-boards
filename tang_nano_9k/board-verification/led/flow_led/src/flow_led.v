module flow_led(
    input Clk,
    input Reset_n,
    output reg [3:0]led

);

reg [24:0]cnt;

parameter MCNT=25'd25_000_000-1;

always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        cnt<=0;
    else if(cnt==MCNT)
        cnt<=0;
    else
        cnt<=cnt+1'b1;


always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        led<=4'b0001;
    else if(cnt==MCNT)
        led<={led[2],led[1],led[0],led[3]};
    else
        led<=led;


endmodule