module led_ctrl1(
  Clk,
  Reset_n,
  Led

);
   input Clk;
   input Reset_n;
   output reg Led;

   reg [26:0] counter;

   //计数器计数进程
   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     counter <=0;
   else if(counter ==125000000-1)
     counter<=0;
   else
     counter<=counter +1'd1;

   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     Led <=1'b0;
   else if(counter ==0)
     Led<=1'b1;
   else if(counter ==12500000)
     Led<=1'b0;   
   else if(counter ==37500000)
     Led<=1'b1;
   else if(counter ==75000000)
     Led<=1'b0;



endmodule