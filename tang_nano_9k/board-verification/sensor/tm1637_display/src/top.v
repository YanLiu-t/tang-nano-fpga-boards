module top (
    input  wire clk,
    output wire tm1637_clk,
    inout  wire tm1637_dio
);

    tm1637_display_8 display (
        .clk        (clk),
        .tm1637_clk (tm1637_clk),
        .tm1637_dio (tm1637_dio)
    );

endmodule