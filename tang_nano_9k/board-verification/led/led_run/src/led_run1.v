module led_run1(
    Clk,
    Reset_n,
    Led
);
    input Clk;
    input Reset_n;
    output reg [5:0] Led;
    reg [24:0] counter;

    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        counter<=0;
    else if(counter==25000000-1)
        counter<=0;
    else
        counter<=counter+1'd1;

    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        Led<=8'b0000_0001;
    else if(counter==25000000-1)
        begin
            Led<={Led[4:0],Led[5]};
        end
endmodule