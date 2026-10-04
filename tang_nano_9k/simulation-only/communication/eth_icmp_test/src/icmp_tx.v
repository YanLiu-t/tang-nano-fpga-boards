module icmp_tx
#(
    parameter BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd10},
    parameter DES_MAC   = 48'hff_ff_ff_ff_ff_ff,
    parameter DES_IP    = {8'd192,8'd168,8'd1,8'd102},
    parameter ECHO_REPLY = 8'h00   //仿真tb会defparam修改此参数
)(
input               clk,
input               rst_n,

input               tx_start_en,
input       [7:0]   tx_data,
input       [15:0]  tx_byte_num,
input       [47:0]  des_mac,
input       [31:0]  des_ip,

input       [31:0]  crc_data,
input       [7:0]   crc_next,   //顶层送入 crc_next[31:24]

output reg          tx_done,
output reg          tx_req,      //读数据请求，给外部RAM

output reg          gmii_tx_en,
output reg  [7:0]   gmii_txd,

output reg          crc_en,
output reg          crc_clr,

input       [15:0]  icmp_id,
input       [15:0]  icmp_seq,
input       [31:0]  reply_checksum
);

//状态机定义
localparam IDLE     = 4'd0;
localparam SEND_PKT = 4'd1;
localparam SEND_CRC = 4'd2;
localparam DONE     = 4'd3;

reg [3:0] curr_state;
reg [3:0] next_state;

reg [15:0] cnt;
reg [31:0] crc_reg;

//状态机第一段
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        curr_state <= IDLE;
    else
        curr_state <= next_state;
end

//状态机第二段
always @(*) begin
    next_state = curr_state;
    case(curr_state)
        IDLE: begin
            if(tx_start_en)
                next_state = SEND_PKT;
        end
        SEND_PKT: begin
            if(cnt >= tx_byte_num - 1'b1)
                next_state = SEND_CRC;
        end
        SEND_CRC: begin
            if(cnt >= 16'd3)
                next_state = DONE;
        end
        DONE: begin
            next_state = IDLE;
        end
    endcase
end

//计数器、tx_req、crc_clr
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt <= 16'd0;
        tx_req <= 1'b0;
        crc_clr <= 1'b0;
    end
    else begin
        case(curr_state)
            IDLE: begin
                cnt <= 16'd0;
                tx_req <= 1'b0;
                crc_clr <= 1'b1;
            end
            SEND_PKT: begin
                crc_clr <= 1'b0;
                cnt <= cnt + 1'b1;
                tx_req <= 1'b1;
            end
            SEND_CRC: begin
                cnt <= cnt + 1'b1;
                tx_req <= 1'b0;
            end
            DONE: begin
                cnt <= 16'd0;
                tx_req <= 1'b0;
            end
        endcase
    end
end

//crc_en
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        crc_en <= 1'b0;
    else begin
        if(curr_state == SEND_PKT)
            crc_en <= 1'b1;
        else
            crc_en <= 1'b0;
    end
end

//发送数据 + 输出CRC
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        gmii_tx_en <= 1'b0;
        gmii_txd   <= 8'd0;
        crc_reg    <= 32'd0;
    end
    else begin
        case(curr_state)
            IDLE: begin
                gmii_tx_en <= 1'b0;
                gmii_txd   <= 8'd0;
            end
            SEND_PKT: begin
                gmii_tx_en <= 1'b1;
                gmii_txd   <= tx_data;
                crc_reg    <= crc_data;
            end
            SEND_CRC: begin
                gmii_tx_en <= 1'b1;
                case(cnt[1:0])
                    2'd0: gmii_txd <= crc_reg[7:0];
                    2'd1: gmii_txd <= crc_reg[15:8];
                    2'd2: gmii_txd <= crc_reg[23:16];
                    2'd3: gmii_txd <= crc_reg[31:24];
                endcase
            end
            DONE: begin
                gmii_tx_en <= 1'b0;
                gmii_txd   <= 8'd0;
            end
        endcase
    end
end

//tx_done脉冲
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        tx_done <= 1'b0;
    else begin
        if(curr_state == DONE)
            tx_done <= 1'b1;
        else
            tx_done <= 1'b0;
    end
end

endmodule
