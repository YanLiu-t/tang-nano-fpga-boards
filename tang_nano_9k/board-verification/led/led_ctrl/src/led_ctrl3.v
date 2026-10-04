module led_ctrl3(
  Clk,
  Reset_n,
  SW,
  Led

);
   input Clk;
   input Reset_n;
   input [7:0]SW;
   output reg Led;

   reg [26:0] counter0;
   reg [2:0] counter1;
    reg [26:0] counter2;
   reg en_counter0;
   reg en_counter2;
    parameter MCNT0=12500000-1;
    parameter MCNT2=50000000-1;
   //计数器计数进程
   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     counter0 <=0;
   else if(en_counter0) begin 
        if(counter0 ==MCNT0)
            counter0<=0;
        else
            counter0<=counter0 +1'd1;
            end
        else
            counter0<=0;

    always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
        counter1<=0;
   else if(counter0==MCNT0)
    begin 
      if(counter1==7)
        counter1<=0;
      else
        counter1<=counter1+1'd1;
    end 
    else 
        counter1<=counter1;
   
   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     counter2 <=0;
   else if(en_counter2) begin 
        if(counter2 ==MCNT2)
            counter2<=0;
        else
            counter2<=counter2 +1'd1;
            end
        else 
            counter2<=0;
   
   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
    en_counter2<=1;
    else if((counter1==7)&&(counter0==MCNT0))
        en_counter2<=1;
    else if(counter2==MCNT2)
        en_counter2<=0;


    always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
        en_counter0<=0;
    else if(counter2==MCNT2)
        en_counter0<=1;
    else if((counter1==7)&&(counter0==MCNT0))
        en_counter0<=0;



   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     Led<=0;
    else if(en_counter0==0)
        Led<=0;
    else begin
        case(counter1)
            0:Led<=SW[0];
            1:Led<=SW[1];
            2:Led<=SW[2];
            3:Led<=SW[3];
            4:Led<=SW[4];
            5:Led<=SW[5];
            6:Led<=SW[6];
            7:Led<=SW[7];
            default:Led<=Led;
        endcase
        end


endmodule