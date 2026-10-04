module arp_rx(
input               clk,            //GMII接收时钟 125MHz
input               rst_n,          //复位，低有效

input               gmii_rx_dv,     //GMII接收数据有效
input      [7:0]    gmii_rxd,       //GMII接收数据

output  reg         arp_rx_done,    //ARP接收完成脉冲
output  reg         arp_rx_type,    //0:ARP请求  1:ARP应答
output  reg [47:0]  src_mac,        //ARP源MAC地址
output  reg [31:0]  src_ip          //ARP源IP地址
);

//参数定义
parameter BOARD_MAC = 48'h00_11_22_33_44_55;
parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd10};

//以太网帧头：ARP帧的以太网类型字段 0x0806
localparam ETH_TYPE_ARP = 16'h0806;

//状态定义
localparam st_idle      = 3'b001;
localparam st_eth_head  = 3'b010;
localparam st_arp_data  = 3'b100;
localparam st_rx_end    = 3'b101;
localparam st_error     = 3'b110;

reg [2:0]   curr_state;
reg [2:0]   next_state;

reg [4:0]   cnt;                //字节计数
reg         skip_en;            //状态跳转使能
reg         error_en;           //错误标志

reg [15:0]  eth_type_t;         //以太网类型缓存
reg [15:0]  op_data;            //ARP操作码 1:请求 2:应答
reg [47:0]  src_mac_t;          //ARP源MAC临时缓存
reg [31:0]  src_ip_t;           //ARP源IP临时缓存
reg [47:0]  des_mac_t;          //ARP目的MAC临时缓存
reg [31:0]  des_ip_t;           //ARP目的IP临时缓存

//************************ 第一段：状态机时序逻辑 状态寄存器 ************************
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        curr_state <= st_idle;
    else
        curr_state <= next_state;
end

//************************ 第二段：组合逻辑 状态跳转 ************************
always @(*) begin
    next_state = curr_state;
    case(curr_state)
        st_idle: begin
            if(gmii_rx_dv == 1'b1)
                next_state = st_eth_head;
        end

        st_eth_head: begin
            if(skip_en)
                next_state = st_arp_data;
            else if(error_en)
                next_state = st_error;
        end

        st_arp_data: begin
            if(skip_en)
                next_state = st_rx_end;
            else if(error_en)
                next_state = st_error;
        end

        st_rx_end: begin
            if(skip_en)
                next_state = st_idle;
        end

        st_error: begin
            if(gmii_rx_dv == 1'b0)
                next_state = st_idle;
        end
        default: next_state = st_idle;
    endcase
end

//************************ 第三段：各个状态内部业务逻辑（你提供片段已完整嵌入）************************
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt         <= 5'd0;
        skip_en     <= 1'b0;
        error_en    <= 1'b0;

        eth_type_t  <= 16'd0;
        op_data     <= 16'd0;
        src_mac_t   <= 48'd0;
        src_ip_t    <= 32'd0;
        des_mac_t   <= 48'd0;
        des_ip_t    <= 32'd0;

        arp_rx_done <= 1'b0;
        arp_rx_type <= 1'b0;
        src_mac     <= 48'd0;
        src_ip      <= 32'd0;
    end
    else begin
        skip_en     <= 1'b0;
        error_en    <= 1'b0;
        arp_rx_done <= 1'b0;

        case(curr_state)
            st_idle: begin
                cnt <= 5'd0;
            end

            st_eth_head: begin
                if(gmii_rx_dv) begin
                    cnt <= cnt + 5'd1;
                    //以太网帧头：6字节目的MAC +6字节源MAC +2字节type
                    //cnt:0~5 目的MAC；6~11源MAC；12(高字节),13(低字节) eth_type
                    if(cnt == 5'd12) begin
                        eth_type_t[15:8] <= gmii_rxd;
                    end
                    else if(cnt == 5'd13) begin
                        eth_type_t[7:0] <= gmii_rxd;
                        cnt <= 5'd0;
                        //判断是否为ARP帧 0x0806
                        if(eth_type_t[15:8]==ETH_TYPE_ARP[15:8] && gmii_rxd==ETH_TYPE_ARP[7:0]) begin
                            skip_en <= 1'b1;
                        end
                        else begin
                            error_en <= 1'b1;
                        end
                    end
                end
            end

            st_arp_data : begin
                if(gmii_rx_dv) begin
                    cnt <= cnt + 5'd1;
                    if(cnt == 5'd6)
                        op_data[15:8] <= gmii_rxd; //操作码高字节
                    else if(cnt == 5'd7)
                        op_data[7:0] <= gmii_rxd;  //操作码低字节
                    else if(cnt >= 5'd8 && cnt < 5'd14)      //源 MAC 地址 6字节
                        src_mac_t <= {src_mac_t[39:0],gmii_rxd};
                    else if(cnt >= 5'd14 && cnt < 5'd18)     //源 IP 地址 4字节
                        src_ip_t <= {src_ip_t[23:0],gmii_rxd};
                    else if(cnt >= 5'd24 && cnt < 5'd28)     //目标 IP 地址4字节
                        des_ip_t <= {des_ip_t[23:0],gmii_rxd};
                    else if(cnt == 5'd28) begin
                        cnt <= 5'd0;
                        if(des_ip_t == BOARD_IP) begin //判断目的 IP 地址和操作码
                            if((op_data == 16'd1) || (op_data == 16'd2)) begin
                                skip_en <= 1'b1;
                                arp_rx_done <= 1'b1;
                                src_mac <= src_mac_t;
                                src_ip <= src_ip_t;
                                src_mac_t <= 48'd0;
                                src_ip_t <= 32'd0;
                                des_mac_t <= 48'd0;
                                des_ip_t <= 32'd0;
                                if(op_data == 16'd1)
                                    arp_rx_type <= 1'b0; //ARP 请求
                                else
                                    arp_rx_type <= 1'b1; //ARP 应答
                            end
                            else
                                error_en <= 1'b1;
                        end
                        else
                            error_en <= 1'b1;
                    end
                end
            end

            st_rx_end : begin
                cnt <= 5'd0;
                //单包数据接收完成，dv拉低，回到idle
                if(gmii_rx_dv == 1'b0 && skip_en == 1'b0)
                    skip_en <= 1'b1;
            end

            st_error: begin
                cnt <= 5'd0;
            end
            default: ;
        endcase
    end
end

endmodule