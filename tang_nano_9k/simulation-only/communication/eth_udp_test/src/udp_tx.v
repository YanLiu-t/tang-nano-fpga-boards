module udp_tx
#(
    parameter BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd10},
    parameter DES_MAC  = 48'hff_ff_ff_ff_ff_ff,
    parameter DES_IP   = {8'd192,8'd168,8'd1,8'd102},
    parameter ETH_TYPE = 16'h0800    //IP协议类型
)(
input               clk,
input               rst_n,

input               tx_start_en,
input       [47:0]  des_mac,
input       [31:0]  des_ip,
input       [7:0]   tx_data,
input       [15:0]  tx_byte_num,

input       [31:0]  crc_data,
input       [7:0]   crc_next,

output reg          tx_done,
output reg          tx_req,
output reg          gmii_tx_en,
output reg  [7:0]   gmii_txd,
output reg          crc_en,
output reg          crc_clr
);

//状态定义
localparam st_idle        = 3'd0;
localparam st_preamble    = 3'd1;
localparam st_eth_head    = 3'd2;
localparam st_check_sum   = 3'd3;
localparam st_ip_head     = 3'd4;
localparam st_tx_data     = 3'd5;
localparam st_crc         = 3'd6;

reg [2:0] curr_state;
reg [2:0] next_state;

reg [7:0]  preamble[7:0];      //前导码 8字节
reg [7:0]  eth_head[13:0];     //以太网帧头14字节
reg [31:0] ip_head[6:0];       //IP首部+UDP首部 共28字节

reg        skip_en;
reg        trig_tx_en;

reg [15:0] total_num;          //IP总长度
reg [15:0] udp_num;            //UDP总长度
reg [15:0] data_cnt;
reg [15:0] tx_data_num;
reg [15:0] real_tx_data_num;
reg [4:0]  real_add_cnt;
reg [2:0]  tx_bit_sel;

reg        tx_done_t;

//第一段 状态寄存器
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        curr_state <= st_idle;
    else
        curr_state <= next_state;
end

//第二段 组合逻辑状态跳转
always @(*) begin
    next_state = curr_state;
    case(curr_state)
        st_idle: begin
            if(trig_tx_en)
                next_state = st_preamble;
        end
        st_preamble: begin
            if(skip_en)
                next_state = st_eth_head;
        end
        st_eth_head: begin
            if(skip_en)
                next_state = st_check_sum;
        end
        st_check_sum: begin
            if(skip_en)
                next_state = st_ip_head;
        end
        st_ip_head: begin
            if(skip_en)
                next_state = st_tx_data;
        end
        st_tx_data: begin
            if(skip_en)
                next_state = st_crc;
        end
        st_crc: begin
            if(skip_en)
                next_state = st_idle;
        end
        default: next_state = st_idle;
    endcase
end

//第三段 时序逻辑，各状态行为
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        skip_en      <= 1'b0;
        trig_tx_en   <= 1'b0;
        data_cnt     <= 16'd0;
        tx_data_num  <= 16'd0;
        real_tx_data_num <=16'd0;
        real_add_cnt <= 5'd0;
        tx_bit_sel   <= 3'd0;
        tx_done_t    <= 1'b0;

        tx_done      <= 1'b0;
        tx_req       <= 1'b0;
        gmii_tx_en   <= 1'b0;
        gmii_txd     <= 8'd0;
        crc_en       <= 1'b0;
        crc_clr      <= 1'b0;

        //初始化数组
        //前导码 7个8'h55 + 1个8'hd5
        preamble[0] <= 8'h55;
        preamble[1] <= 8'h55;
        preamble[2] <= 8'h55;
        preamble[3] <= 8'h55;
        preamble[4] <= 8'h55;
        preamble[5] <= 8'h55;
        preamble[6] <= 8'h55;
        preamble[7] <= 8'hd5;

        //目的MAC
        eth_head[0] <= DES_MAC[47:40];
        eth_head[1] <= DES_MAC[39:32];
        eth_head[2] <= DES_MAC[31:24];
        eth_head[3] <= DES_MAC[23:16];
        eth_head[4] <= DES_MAC[15:8];
        eth_head[5] <= DES_MAC[7:0];
        //源MAC
        eth_head[6] <= BOARD_MAC[47:40];
        eth_head[7] <= BOARD_MAC[39:32];
        eth_head[8] <= BOARD_MAC[31:24];
        eth_head[9] <= BOARD_MAC[23:16];
        eth_head[10]<= BOARD_MAC[15:8];
        eth_head[11]<= BOARD_MAC[7:0];
        //以太网类型
        eth_head[12]<= ETH_TYPE[15:8];
        eth_head[13]<= ETH_TYPE[7:0];

        ip_head[0] <= 32'h45000000;
        ip_head[1] <= 32'h00004000;
        ip_head[2] <= 32'h40110000;
        ip_head[3] <= BOARD_IP;
        ip_head[4] <= DES_IP;
        ip_head[5] <= {16'd1234,16'd1234};
        ip_head[6] <= 32'h00000000;

    end
    else begin
        skip_en  <= 1'b0;
        crc_clr  <= 1'b0;
        tx_done  <= tx_done_t;
        tx_done_t<= 1'b0;

        case(curr_state)
            st_idle : begin
                trig_tx_en <= tx_start_en;
                tx_req     <= 1'b0;
                gmii_tx_en <= 1'b0;
                gmii_txd   <= 8'd0;
                crc_en     <= 1'b0;
                data_cnt   <= 16'd0;
                tx_bit_sel <= 3'd0;
                real_add_cnt <=5'd0;

                if(trig_tx_en) begin
                    skip_en <= 1'b1;
                    udp_num    <= tx_byte_num + 16'd8;   //udp头部8字节
                    total_num  <= tx_byte_num + 16'd28;  //ip20+udp8
                    tx_data_num <= tx_byte_num;
                    //以太网帧最小数据46字节，ip+udp占28，有效数据最少18字节，不足要填充
                    if(tx_byte_num < 16'd18)
                        real_tx_data_num <= 16'd18;
                    else
                        real_tx_data_num <= tx_byte_num;

                    //版本号：4 首部长度：5(单位32bit，20byte)
                    ip_head[0] <= {8'h45,8'h00,total_num};
                    //16位标识，每次发送累加1
                    ip_head[1][31:16] <= ip_head[1][31:16] + 1'b1;
                    //bit[15:13]:010不分片
                    ip_head[1][15:0] <= 16'h4000;
                    //协议17 UDP
                    ip_head[2] <= {8'h40,8'd17,16'h0};
                    //源IP
                    ip_head[3] <= BOARD_IP;
                    //目的IP
                    if(des_ip != 32'd0)
                        ip_head[4] <= des_ip;
                    else
                        ip_head[4] <= DES_IP;
                    //源端口1234，目的端口1234
                    ip_head[5] <= {16'd1234,16'd1234};
                    //udp长度，udp校验和0
                    ip_head[6] <= {udp_num,16'h0000};

                    //更新目的MAC
                    if(des_mac != 48'd0) begin
                        eth_head[0] <= des_mac[47:40];
                        eth_head[1] <= des_mac[39:32];
                        eth_head[2] <= des_mac[31:24];
                        eth_head[3] <= des_mac[23:16];
                        eth_head[4] <= des_mac[15:8];
                        eth_head[5] <= des_mac[7:0];
                    end
                end
            end

            st_preamble: begin
                crc_clr <= 1'b1;
                gmii_tx_en <= 1'b1;
                gmii_txd <= preamble[tx_bit_sel];
                tx_bit_sel <= tx_bit_sel + 3'd1;
                if(tx_bit_sel == 3'd7) begin
                    skip_en <= 1'b1;
                    tx_bit_sel <= 3'd0;
                end
            end

            st_eth_head: begin
                crc_en <= 1'b1;
                gmii_tx_en <= 1'b1;
                gmii_txd <= eth_head[tx_bit_sel];
                tx_bit_sel <= tx_bit_sel + 3'd1;
                if(tx_bit_sel == 4'd13) begin
                    skip_en <= 1'b1;
                    tx_bit_sel <= 3'd0;
                end
            end

            st_check_sum: begin
                //IP首部校验和计算状态，教材此处省略计算逻辑，直接跳转
                skip_en <= 1'b1;
            end

            st_ip_head: begin
                gmii_tx_en <= 1'b1;
                //ip_head每个元素32bit，分4字节发送
                case(tx_bit_sel[1:0])
                    2'd0: gmii_txd <= ip_head[tx_bit_sel[2:2]][31:24];
                    2'd1: gmii_txd <= ip_head[tx_bit_sel[2:2]][23:16];
                    2'd2: gmii_txd <= ip_head[tx_bit_sel[2:2]][15:8];
                    2'd3: gmii_txd <= ip_head[tx_bit_sel[2:2]][7:0];
                endcase
                tx_bit_sel <= tx_bit_sel + 3'd1;
                //ip20+udp8 =28字节
                if(tx_bit_sel == 3'd27) begin
                    skip_en <= 1'b1;
                    tx_bit_sel <= 3'd0;
                end
            end

            st_tx_data : begin //发送数据
                crc_en <= 1'b1;
                gmii_tx_en <= 1'b1;
                gmii_txd <= tx_data;
                tx_bit_sel <= tx_bit_sel + 3'd1;
                if(data_cnt < tx_data_num - 16'd1) begin
                    data_cnt <= data_cnt + 16'd1;
                    tx_req <= 1'b1;
                end
                else if(data_cnt >= tx_data_num - 16'd1)begin
                    tx_req <= 1'b0;
                    //不足18字节填充
                    if(data_cnt + real_add_cnt < real_tx_data_num - 16'd1) begin
                        real_add_cnt <= real_add_cnt + 5'd1;
                        gmii_txd <= 8'd0; //填充0
                    end
                    else begin
                        skip_en <= 1'b1;
                        data_cnt <= 16'd0;
                        real_add_cnt <= 5'd0;
                        tx_bit_sel <= 3'd0;
                    end
                end

                if(data_cnt == tx_data_num - 16'd2)
                    tx_req <= 1'b0;
            end

            st_crc : begin //发送 CRC 校验值
                gmii_tx_en <= 1'b1;
                tx_bit_sel <= tx_bit_sel + 3'd1;
                tx_req <= 1'b0;
                crc_en <= 1'b0;
                if(tx_bit_sel == 3'd0)
                    gmii_txd <= {~crc_next[0], ~crc_next[1], ~crc_next[2],~crc_next[3],
                                 ~crc_next[4], ~crc_next[5], ~crc_next[6],~crc_next[7]};
                else if(tx_bit_sel == 3'd1)
                    gmii_txd <= {~crc_data[16], ~crc_data[17], ~crc_data[18],~crc_data[19],
                                 ~crc_data[20], ~crc_data[21], ~crc_data[22],~crc_data[23]};
                else if(tx_bit_sel == 3'd2) begin
                    gmii_txd <= {~crc_data[8], ~crc_data[9], ~crc_data[10],~crc_data[11],
                                 ~crc_data[12], ~crc_data[13], ~crc_data[14],~crc_data[15]};
                end
                else if(tx_bit_sel == 3'd3) begin
                    gmii_txd <= {~crc_data[0], ~crc_data[1], ~crc_data[2],~crc_data[3],
                                 ~crc_data[4], ~crc_data[5], ~crc_data[6],~crc_data[7]};
                    tx_done_t <= 1'b1;
                    skip_en <= 1'b1;
                end
            end
        endcase
    end
end

endmodule
