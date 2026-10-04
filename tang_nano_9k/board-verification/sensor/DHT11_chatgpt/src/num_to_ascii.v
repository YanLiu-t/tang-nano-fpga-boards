module num_to_ascii(

    input  wire [7:0] num,

    output wire [7:0] hundred,
    output wire [7:0] ten,
    output wire [7:0] one

);



assign hundred = num / 100 + 8'h30;

assign ten = (num % 100) / 10 + 8'h30;

assign one = num % 10 + 8'h30;



endmodule