module led_ctrl0(
  Clk,
  Reset_n,
  Led

);
   input Clk;
   input Reset_n;
   output reg Led;

   reg [25:0] counter;

   //计数器计数进程
   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     counter <=0;
   else if(counter ==50_000_000-1)
     counter<=0;
   else
     counter<=counter +1'd1;

   always@(posedge Clk or negedge Reset_n)
   if(!Reset_n)
     Led <=1'b0;
   else if(counter ==0)
     Led<=1'b1;
   else if(counter ==125_000_00)
     Led<=1'b0;



endmodule