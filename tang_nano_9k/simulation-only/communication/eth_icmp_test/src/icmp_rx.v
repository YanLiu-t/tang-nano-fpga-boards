module icmp_rx
#(
    parameter BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd10}
)(
input               clk,
input               rst_n,

input               gmii_rx_dv,
input       [7:0]   gmii_rxd,

output reg          rec_pkt_done,
output reg          rec_en,
output reg  [7:0]   rec_data,
output reg  [15:0]  rec_byte_num,

output reg  [15:0]  icmp_id,
output reg  [15:0]  icmp_seq,
output reg  [31:0]  reply_checksum
);

localparam IDLE = 2'd0;
localparam RECV = 2'd1;
localparam DONE = 2'd2;

reg [1:0] curr_state;
reg [1:0] next_state;
reg [15:0] byte_cnt;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        curr_state <= IDLE;
    else
        curr_state <= next_state;
end

always @(*) begin
    next_state = curr_state;
    case(curr_state)
        IDLE: begin
            if(gmii_rx_dv)
                next_state = RECV;
        end
        RECV: begin
            if(!gmii_rx_dv)
                next_state = DONE;
        end
        DONE: begin
            next_state = IDLE;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        byte_cnt <= 16'd0;
        rec_en <= 1'b0;
        rec_data <= 8'd0;
        rec_byte_num <= 16'd0;
        rec_pkt_done <= 1'b0;
        icmp_id <= 16'd0;
        icmp_seq <= 16'd0;
        reply_checksum <= 32'd0;
    end
    else begin
        case(curr_state)
            IDLE: begin
                byte_cnt <= 16'd0;
                rec_en <= 1'b0;
                rec_pkt_done <= 1'b0;
            end
            RECV: begin
                byte_cnt <= byte_cnt + 1'b1;
                rec_en <= 1'b1;
                rec_data <= gmii_rxd;
            end
            DONE: begin
                rec_en <= 1'b0;
                rec_byte_num <= byte_cnt;
                rec_pkt_done <= 1'b1;
            end
        endcase
    end
end

endmodule
