module edge_test(
    input a,
    input Clk,
    input Reset_n,

    output a_posedge,
    output a_negedge,
    output a_side
);

reg a_dly;

always@(posedge Clk or negedge Reset_n)begin
if(!Reset_n)
a_dly<=1'b0;
else
    a_dly<=a;

end

assign a_posedge=a&(~a_dly);
assign a_negedge=(~a)&(a_dly);
assign a_side=a^a_dly;





endmodule