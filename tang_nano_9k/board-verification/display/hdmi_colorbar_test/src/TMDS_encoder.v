module TMDS_encoder(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  data_in,
    input  wire [1:0]  ctrl,
    input  wire        de,
    output reg  [9:0]  data_out
);

    function [3:0] count_ones;
        input [7:0] d;
        integer i;
        begin
            count_ones = 0;
            for (i = 0; i < 8; i = i + 1)
                count_ones = count_ones + d[i];
        end
    endfunction

    wire [3:0] n1_d = count_ones(data_in);
    reg [3:0] disparity;
    reg [8:0] q_m;
    wire [3:0] n1_q_m;
    assign n1_q_m = count_ones(q_m[7:0]);

    always @(posedge clk) begin
        if (n1_d > 4 || (n1_d == 4 && data_in[0] == 0)) begin
            q_m[0] <= data_in[0];
            q_m[1] <= q_m[0] ^~ data_in[1];
            q_m[2] <= q_m[1] ^~ data_in[2];
            q_m[3] <= q_m[2] ^~ data_in[3];
            q_m[4] <= q_m[3] ^~ data_in[4];
            q_m[5] <= q_m[4] ^~ data_in[5];
            q_m[6] <= q_m[5] ^~ data_in[6];
            q_m[7] <= q_m[6] ^~ data_in[7];
            q_m[8] <= 0;
        end else begin
            q_m[0] <= data_in[0];
            q_m[1] <= q_m[0] ^ data_in[1];
            q_m[2] <= q_m[1] ^ data_in[2];
            q_m[3] <= q_m[2] ^ data_in[3];
            q_m[4] <= q_m[3] ^ data_in[4];
            q_m[5] <= q_m[4] ^ data_in[5];
            q_m[6] <= q_m[5] ^ data_in[6];
            q_m[7] <= q_m[6] ^ data_in[7];
            q_m[8] <= 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out  <= 10'b1101010100;
            disparity <= 0;
        end else if (!de) begin
            case (ctrl)
                2'b00:   data_out <= 10'b1101010100;
                2'b01:   data_out <= 10'b0010101011;
                2'b10:   data_out <= 10'b0101010100;
                default: data_out <= 10'b1010101011;
            endcase
            disparity <= 0;
        end else begin
            if (disparity == 0 || n1_q_m == 4) begin
                if (q_m[8]) begin
                    data_out <= {~q_m[8], q_m[8], q_m[7:0]};
                    disparity <= disparity + (n1_q_m - 4);
                end else begin
                    data_out <= {q_m[8], q_m[8], ~q_m[7:0]};
                    disparity <= disparity + (4 - n1_q_m);
                end
            end else begin
                if ((disparity > 0 && n1_q_m > 4) || (disparity < 0 && n1_q_m < 4)) begin
                    data_out <= {1'b1, q_m[8], ~q_m[7:0]};
                    disparity <= disparity + (q_m[8] ? (n1_q_m - 4) : (4 - n1_q_m));
                end else begin
                    data_out <= {1'b0, q_m[8], q_m[7:0]};
                    disparity <= disparity + (q_m[8] ? (4 - n1_q_m) : (n1_q_m - 4));
                end
            end
        end
    end

endmodule