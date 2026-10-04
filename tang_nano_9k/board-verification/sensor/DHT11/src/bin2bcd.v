module bin2bcd(
    input  wire [15:0] bin_in,
    output wire [3:0]  thou,   // 千位
    output wire [3:0]  hund,   // 百位
    output wire [3:0]  tens,   // 十位
    output wire [3:0]  ones    // 个位
);
    
    integer i;
    reg [31:0] bcd;

    always @(*) begin
        bcd = 32'd0;
        for (i = 0; i < 16; i = i + 1) begin
            if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
            if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
            if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 3;
            if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 3;
            bcd = {bcd[30:0], bin_in[15 - i]};
        end
    end

    assign ones = bcd[15:12];
    assign tens = bcd[19:16];
    assign hund = bcd[23:20];
    assign thou = bcd[27:24];

endmodule