`timescale 1ns/1ns

module mux2_tb();

  reg s0;
  reg s1;
  reg s2;
  wire mux2_out;
  mux2 mux2(
    .a(s0),
    .b(s1),
    .sel(s2),
    .out(mux2_out)

);
  initial begin
    s2=0;s1=0;s0=0;
    #20;
    s2=0;s1=0;s0=1;
    #20;
    s2=0;s1=1;s0=0;
    #20;
    s2=0;s1=1;s0=1;
    #20;
    s2=1;s1=0;s0=0;
    #20;
    s2=1;s1=0;s0=1;
    #20;
    s2=1;s1=1;s0=0;
    #20;
    s2=1;s1=1;s0=1;
    #20;
     end
endmodule