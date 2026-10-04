module udp_rx
#(
    parameter BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd10}
)(
input               clk,
input               rst_n,

input               gmii_rx_dv,
input       [7:0]   gmii_rxd,

output reg          rec_data,
output reg          rec_en,
output reg          rec_pkt_done,
output reg [15:0]   rec_byte_num
);

//状态定义
localparam st_idle      = 3'd0;
localparam st_preamble  = 3'd1;
localparam st_eth_head = 3'd2;
localparam st_ip_head   = 3'd3;
localparam st_udp_head  = 3'd4;
localparam st_rx_data   = 3'd5;
localparam st_rx_end    = 3'd6;

reg [2:0] curr_state;
reg [2:0] next_state;

reg [15:0] data_cnt;
reg [15:0] data_byte_num;
reg        skip_en;
reg        error_en;

reg [3:0]  pre_cnt;
reg [15:0] eth_cnt;
reg [15:0] ip_cnt;
reg [15:0] udp_cnt;

//第一段：状态寄存器
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        curr_state <= st_idle;
    else
        curr_state <= next_state;
end

//第二段：组合逻辑，状态跳转
always @(*) begin
    next_state = curr_state;
    case(curr_state)
        st_idle: begin
            if(gmii_rx_dv)
                next_state = st_preamble;
        end
        st_preamble: begin
            if(error_en)
                next_state = st_rx_end;
            else if(skip_en)
                next_state = st_eth_head;
        end
        st_eth_head: begin
            if(error_en)
                next_state = st_rx_end;
            else if(skip_en)
                next_state = st_ip_head;
        end
        st_ip_head: begin
            if(error_en)
                next_state = st_rx_end;
            else if(skip_en)
                next_state = st_udp_head;
        end
        st_udp_head: begin
            if(error_en)
                next_state = st_rx_end;
            else if(skip_en)
                next_state = st_rx_data;
        end
        st_rx_data: begin
            if(skip_en)
                next_state = st_rx_end;
        end
        st_rx_end: begin
            if(!gmii_rx_dv && skip_en)
                next_state = st_idle;
        end
        default: next_state = st_idle;
    endcase
end

//第三段：时序逻辑，各状态内部行为
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pre_cnt      <= 4'd0;
        eth_cnt      <= 16'd0;
        ip_cnt       <= 16'd0;
        udp_cnt      <= 16'd0;
        data_cnt     <= 16'd0;
        data_byte_num<= 16'd0;
        skip_en      <= 1'b0;
        error_en     <= 1'b0;

        rec_data     <= 8'd0;
        rec_en       <= 1'b0;
        rec_pkt_done <= 1'b0;
        rec_byte_num <= 16'd0;
    end
    else begin
        skip_en      <= 1'b0;
        error_en     <= 1'b0;
        rec_en       <= 1'b0;
        rec_pkt_done <= 1'b0;
        case(curr_state)
            st_idle: begin
                pre_cnt  <= 4'd0;
                eth_cnt  <= 16'd0;
                ip_cnt   <= 16'd0;
                udp_cnt  <= 16'd0;
                data_cnt <= 16'd0;
            end
            st_preamble: begin
                if(gmii_rx_dv) begin
                    pre_cnt <= pre_cnt + 1'b1;
                    if(pre_cnt < 4'd7) begin
                        if(gmii_rxd != 8'h55)
                            error_en <= 1'b1;
                    end
                    else if(pre_cnt == 4'd7) begin
                        if(gmii_rxd == 8'hd5)
                            skip_en <= 1'b1;
                        else
                            error_en <= 1'b1;
                    end
                end
            end
            st_eth_head: begin
                if(gmii_rx_dv) begin
                    eth_cnt <= eth_cnt + 1'b1;
                    //以太网帧头14字节，接收完14字节跳转
                    if(eth_cnt >= 16'd13) begin
                        skip_en <= 1'b1;
                    end
                end
            end
            st_ip_head: begin
                if(gmii_rx_dv) begin
                    ip_cnt <= ip_cnt + 1'b1;
                    //IP首部20字节
                    if(ip_cnt >= 16'd19) begin
                        skip_en <= 1'b1;
                    end
                end
            end
            st_udp_head: begin
                if(gmii_rx_dv) begin
                    udp_cnt <= udp_cnt + 1'b1;
                    //UDP首部8字节
                    if(udp_cnt >= 16'd7) begin
                        skip_en <= 1'b1;
                    end
                end
            end
            st_rx_data : begin
                //接收数据
                if(gmii_rx_dv) begin
                    data_cnt <= data_cnt + 16'd1;
                    rec_data <= gmii_rxd;
                    rec_en <= 1'b1;
                    if(data_cnt == data_byte_num - 16'd1) begin
                        skip_en <= 1'b1; //有效数据接收完成
                        data_cnt <= 16'd0;
                        rec_pkt_done <= 1'b1;
                        rec_byte_num <= data_byte_num;
                    end
                end
            end
            st_rx_end : begin //单包数据接收完成
                rec_en <= 1'b0;
                if(gmii_rx_dv == 1'b0 && skip_en == 1'b0)
                    skip_en <= 1'b1;
            end
        endcase
    end
end

endmodule
