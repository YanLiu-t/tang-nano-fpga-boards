module arp_tx(
input               clk,            //GMII发送时钟 125MHz
input               rst_n,          //复位低有效

input               arp_tx_en,      //ARP发送使能
input               arp_tx_type,    //0:ARP请求  1:ARP应答
input      [47:0]   des_mac,        //目标MAC地址
input      [31:0]   des_ip,         //目标IP地址

input      [31:0]   crc_data,       //CRC当前计算值
input      [7:0]    crc_next,       //CRC下一级输出(取crc_next[31:24])

output  reg         tx_done,        //发送完成标志
output  reg         gmii_tx_en,     //GMII数据有效
output  reg [7:0]   gmii_txd,       //GMII发送数据
output  reg         crc_en,         //CRC计算使能
output  reg         crc_clr         //CRC复位清除
);

//参数定义
parameter BOARD_MAC = 48'h00_11_22_33_44_55;
parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd10};
parameter DES_MAC   = 48'hff_ff_ff_ff_ff_ff;
parameter DES_IP    = {8'd192,8'd168,8'd1,8'd102};

localparam ETH_TYPE      = 16'h0806;    //ARP以太网类型
localparam HD_TYPE       = 16'h0001;    //硬件类型以太网
localparam PROTOCOL_TYPE = 16'h0800;    //协议类型IP
localparam MIN_DATA_NUM  = 6'd46;       //以太网载荷最小46字节
localparam PREAMBLE_NUM  = 3'd8;        //前导码8字节
localparam ETH_HEAD_NUM  = 5'd14;       //以太网帧头14字节
localparam ARP_DATA_NUM  = 6'd28;       //ARP报文28字节

//状态定义
localparam st_idle        = 3'b001;
localparam st_preamble    = 3'b010;
localparam st_eth_head    = 3'b011;
localparam st_arp_data    = 3'b100;
localparam st_crc         = 3'b101;
localparam st_tx_end      = 3'b110;

reg [2:0]   curr_state;
reg [2:0]   next_state;

reg         pos_tx_en;      //发送使能上升沿检测
reg         arp_tx_en_r1;

reg [7:0]   preamble[7:0];  //前导码+SFD 8字节
reg [7:0]   eth_head[13:0]; //以太网首部14字节
reg [7:0]   arp_data[27:0]; //ARP数据28字节

reg [5:0]   cnt;            //字节计数器
reg [5:0]   data_cnt;       //数组索引计数器
reg         skip_en;        //状态跳转使能

//发送使能上升沿检测
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        arp_tx_en_r1 <= 1'b0;
        pos_tx_en    <= 1'b0;
    end
    else begin
        arp_tx_en_r1 <= arp_tx_en;
        pos_tx_en    <= arp_tx_en && (~arp_tx_en_r1);
    end
end

//状态机时序：状态寄存器
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        curr_state <= st_idle;
    else
        curr_state <= next_state;
end

//状态机组合逻辑：状态跳转
always @(*) begin
    next_state = curr_state;
    case(curr_state)
        st_idle: begin
            if(skip_en)
                next_state = st_preamble;
        end
        st_preamble: begin
            if(skip_en)
                next_state = st_eth_head;
        end
        st_eth_head: begin
            if(skip_en)
                next_state = st_arp_data;
        end
        st_arp_data: begin
            if(skip_en)
                next_state = st_crc;
        end
        st_crc: begin
            if(skip_en)
                next_state = st_tx_end;
        end
        st_tx_end: begin
            if(skip_en)
                next_state = st_idle;
        end
        default: next_state = st_idle;
    endcase
end

//状态机时序逻辑，数组初始化+运行时更新+各状态输出
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt         <= 6'd0;
        data_cnt    <= 6'd0;
        skip_en     <= 1'b0;

        gmii_tx_en  <= 1'b0;
        gmii_txd    <= 8'd0;
        crc_en      <= 1'b0;
        crc_clr     <= 1'b1;
        tx_done     <= 1'b0;

        //初始化数组
        //前导码 7个0x55 + 1个0xd5
        preamble[0] <= 8'h55;
        preamble[1] <= 8'h55;
        preamble[2] <= 8'h55;
        preamble[3] <= 8'h55;
        preamble[4] <= 8'h55;
        preamble[5] <= 8'h55;
        preamble[6] <= 8'h55;
        preamble[7] <= 8'hd5;

        //以太网帧头
        eth_head[0] <= DES_MAC[47:40]; //目的 MAC 地址
        eth_head[1] <= DES_MAC[39:32];
        eth_head[2] <= DES_MAC[31:24];
        eth_head[3] <= DES_MAC[23:16];
        eth_head[4] <= DES_MAC[15:8];
        eth_head[5] <= DES_MAC[7:0];
        eth_head[6] <= BOARD_MAC[47:40]; //源 MAC 地址
        eth_head[7] <= BOARD_MAC[39:32];
        eth_head[8] <= BOARD_MAC[31:24];
        eth_head[9] <= BOARD_MAC[23:16];
        eth_head[10] <= BOARD_MAC[15:8];
        eth_head[11] <= BOARD_MAC[7:0];
        eth_head[12] <= ETH_TYPE[15:8]; //以太网帧类型
        eth_head[13] <= ETH_TYPE[7:0];

        //ARP 数据
        arp_data[0] <= HD_TYPE[15:8];     //硬件类型
        arp_data[1] <= HD_TYPE[7:0];
        arp_data[2] <= PROTOCOL_TYPE[15:8];//上层协议类型
        arp_data[3] <= PROTOCOL_TYPE[7:0];
        arp_data[4] <= 8'h06;              //硬件地址长度,6
        arp_data[5] <= 8'h04;              //协议地址长度,4
        arp_data[6] <= 8'h00;              //OP高字节
        arp_data[7] <= 8'h01;              //OP低字节，默认ARP请求
        arp_data[8] <= BOARD_MAC[47:40];   //发送端(源)MAC 地址
        arp_data[9] <= BOARD_MAC[39:32];
        arp_data[10] <= BOARD_MAC[31:24];
        arp_data[11] <= BOARD_MAC[23:16];
        arp_data[12] <= BOARD_MAC[15:8];
        arp_data[13] <= BOARD_MAC[7:0];
        arp_data[14] <= BOARD_IP[31:24];   //发送端(源)IP 地址
        arp_data[15] <= BOARD_IP[23:16];
        arp_data[16] <= BOARD_IP[15:8];
        arp_data[17] <= BOARD_IP[7:0];
        arp_data[18] <= DES_MAC[47:40];    //接收端(目的)MAC 地址
        arp_data[19] <= DES_MAC[39:32];
        arp_data[20] <= DES_MAC[31:24];
        arp_data[21] <= DES_MAC[23:16];
        arp_data[22] <= DES_MAC[15:8];
        arp_data[23] <= DES_MAC[7:0];
        arp_data[24] <= DES_IP[31:24];     //接收端(目的)IP 地址
        arp_data[25] <= DES_IP[23:16];
        arp_data[26] <= DES_IP[15:8];
        arp_data[27] <= DES_IP[7:0];
    end
    else begin
        skip_en     <= 1'b0;
        tx_done     <= 1'b0;
        crc_clr     <= 1'b0;

        case(curr_state)
            st_idle : begin
                cnt <= 6'd0;
                data_cnt <= 6'd0;
                gmii_tx_en <= 1'b0;
                gmii_txd <= 8'd0;
                crc_en <= 1'b0;
                if(pos_tx_en) begin
                    skip_en <= 1'b1;
                    //如果目标 MAC 地址和 IP 地址已经更新,则发送正确的地址
                    if((des_mac != 48'b0) || (des_ip != 32'd0)) begin
                        eth_head[0] <= des_mac[47:40];
                        eth_head[1] <= des_mac[39:32];
                        eth_head[2] <= des_mac[31:24];
                        eth_head[3] <= des_mac[23:16];
                        eth_head[4] <= des_mac[15:8];
                        eth_head[5] <= des_mac[7:0];

                        arp_data[18] <= des_mac[47:40];
                        arp_data[19] <= des_mac[39:32];
                        arp_data[20] <= des_mac[31:24];
                        arp_data[21] <= des_mac[23:16];
                        arp_data[22] <= des_mac[15:8];
                        arp_data[23] <= des_mac[7:0];

                        arp_data[24] <= des_ip[31:24];
                        arp_data[25] <= des_ip[23:16];
                        arp_data[26] <= des_ip[15:8];
                        arp_data[27] <= des_ip[7:0];
                    end
                    if(arp_tx_type == 1'b0)
                        arp_data[7] <= 8'h01; //ARP 请求
                    else
                        arp_data[7] <= 8'h02; //ARP 应答
                end
            end

            st_preamble: begin
                gmii_tx_en <= 1'b1;
                gmii_txd <= preamble[cnt];
                if(cnt == PREAMBLE_NUM - 1'b1) begin
                    skip_en <= 1'b1;
                    cnt <= 6'd0;
                end
                else begin
                    cnt <= cnt + 1'b1;
                end
            end

            st_eth_head: begin
                crc_en <= 1'b1;
                gmii_tx_en <= 1'b1;
                gmii_txd <= eth_head[cnt];
                if(cnt == ETH_HEAD_NUM - 1'b1) begin
                    skip_en <= 1'b1;
                    cnt <= 6'd0;
                end
                else begin
                    cnt <= cnt + 1'b1;
                end
            end

            st_arp_data : begin //发送 ARP 数据
                crc_en <= 1'b1;
                gmii_tx_en <= 1'b1;
                //至少发送 46 个字节
                if (cnt == MIN_DATA_NUM - 1'b1) begin
                    skip_en <= 1'b1;
                    cnt <= 6'd0;
                    data_cnt <= 6'd0;
                end
                else begin
                    cnt <= cnt + 1'b1;
                end

                if(data_cnt <= 6'd27) begin
                    data_cnt <= data_cnt + 1'b1;
                    gmii_txd <= arp_data[data_cnt];
                end
                else begin
                    gmii_txd <= 8'd0; //Padding,填充 0
                end
            end

            st_crc: begin //发送CRC32校验值，注意以太网CRC需要位反转
                crc_en <= 1'b0;
                gmii_tx_en <= 1'b1;
                case(cnt)
                    6'd0: gmii_txd <= ~crc_data[7:0];
                    6'd1: gmii_txd <= ~crc_data[15:8];
                    6'd2: gmii_txd <= ~crc_data[23:16];
                    6'd3: gmii_txd <= ~crc_data[31:24];
                endcase
                if(cnt == 6'd3) begin
                    skip_en <= 1'b1;
                    cnt <= 6'd0;
                end
                else begin
                    cnt <= cnt + 1'b1;
                end
            end

            st_tx_end: begin
                gmii_tx_en <= 1'b0;
                gmii_txd   <= 8'd0;
                crc_clr    <= 1'b1; //清除CRC
                tx_done    <= 1'b1;
                skip_en    <= 1'b1;
            end
            default: ;
        endcase
    end
end

endmodule