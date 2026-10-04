`timescale 1ns/1ns
module edge_test_tb;

    reg a;
    reg Clk;
    reg Reset_n;
    wire a_posedge;
    wire a_negedge;
    wire a_side;

initial begin 

Clk=1'b1;
Reset_n<=1'b0;
a<=1'b0;
#201
Reset_n<=1'b1;
#20
a<=1'b1;
#100
a<=1'b0;
#200
$finish;
end

always #10 Clk<=~Clk;

edge_test edge_test_tb(
    .Clk(Clk),
    .a(a),
    .Reset_n(Reset_n),
    .a_posedge(a_posedge),
    .a_negedge(a_negedge),
    .a_side(a_side)

);



endmodule