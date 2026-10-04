module led_ctrl2(
  Clk,
  Reset_n,
  SW,
  Led

);
   input Clk;
   input Reset_n;
   input [7:0]SW;
   output reg Led;

   reg [26:0] counter;
   reg [2:0] counter1;
    parameter MCNT=12500000-1;
   //计数器计数进程
   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     counter <=0;
   else if(counter ==MCNT)
     counter<=0;
   else
     counter<=counter +1'd1;

   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
        counter1<=0;
   else if(counter==MCNT)
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