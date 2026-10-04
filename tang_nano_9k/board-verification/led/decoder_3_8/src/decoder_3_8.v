module decoder_3_8(
    A0,
    A1,
    A2,
    Y0,
    Y1,
    Y2,
    Y3,
    Y4,
    Y5,
    Y6,
    Y7
);

input A0;
input A1;
input A2;
output reg Y0;
output reg Y1;
output reg Y2;
output reg Y3;
output reg Y4;
output reg Y5;
output reg Y6;
output reg Y7;

always@(*)
case({A2,A1,A0})
    3'b000: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0000_0001;
    3'b001: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0000_0010;
    3'b010: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0000_0100;
    3'b011: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0000_1000;
    3'b100: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0001_0000;
    3'b101: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0010_0000;
    3'b110: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0100_0000;
    3'b111: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b1000_0000;
    default: {Y7,Y6,Y5,Y4,Y3,Y2,Y1,Y0} = 8'b0000_0000;
endcase

endmodule