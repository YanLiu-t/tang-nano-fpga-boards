module eth_ctrl(
input clk , //时钟
input rst_n , //系统复位信号，低电平有效
//ARP 相关端口信号 
input arp_rx_done , //ARP 接收完成信号
input arp_rx_type , //ARP 接收类型 0:请求 1:应答
output reg arp_tx_en , //ARP 发送使能信号
output arp_tx_type , //ARP 发送类型 0:请求 1:应答
input arp_tx_done , //ARP 发送完成信号
input arp_gmii_tx_en , //ARP GMII 输出数据有效信号
input [7:0] arp_gmii_txd , //ARP GMII 输出数据
//ICMP 相关端口信号
input icmp_tx_start_en , //ICMP 开始发送信号
input icmp_tx_done , //ICMP 发送完成信号
input icmp_gmii_tx_en , //ICMP GMII 输出数据有效信号 
input [7:0] icmp_gmii_txd , //ICMP GMII 输出数据
//ICMP fifo 接口信号
input icmp_rec_en , //ICMP 接收的数据使能信号
input [7:0] icmp_rec_data , //ICMP 接收的数据
input icmp_tx_req , //ICMP 读数据请求信号
output [7:0] icmp_tx_data , //ICMP 待发送数据
//UDP 相关端口信号
input udp_tx_start_en , //UDP 开始发送信号
input udp_tx_done , //UDP 发送完成信号
input udp_gmii_tx_en , //UDP GMII 输出数据有效信号 
input [7:0] udp_gmii_txd , //UDP GMII 输出数据 
//UDP fifo 接口信号
input [7:0] udp_rec_data , //UDP 接收的数据
input udp_rec_en , //UDP 接收的数据使能信号
input udp_tx_req , //UDP 读数据请求信号
output [7:0] udp_tx_data , //UDP 待发送数据
//fifo 接口信号
input [7:0] tx_data , //待发送的数据
output tx_req , //读数据请求信号
output reg rec_en , //接收的数据使能信号
output reg [7:0] rec_data , //接收的数据
//GMII 发送引脚 
output reg gmii_tx_en , //GMII 输出数据有效信号
output reg [7:0] gmii_txd //GMII 输出数据
);

//reg define
reg [1:0] protocol_sw; //协议切换信号
reg icmp_tx_busy; //ICMP 正在发送数据标志信号
reg udp_tx_busy; //UDP 正在发送数据标志信号
reg arp_rx_flag; //接收到 ARP 请求信号的标志
reg icmp_tx_req_d0; //ICMP 读数据请求信号寄存器
reg udp_tx_req_d0; //UDP 读数据请求信号寄存器

//*****************************************************
//** main code
//*****************************************************

assign arp_tx_type = 1'b1; //ARP 发送类型固定为 ARP 应答 
assign tx_req = udp_tx_req ? 1'b1 : icmp_tx_req; //读数据请求信号选择
assign icmp_tx_data = icmp_tx_req_d0 ? tx_data : 8'd0; //ICMP 待发送数据选择
assign udp_tx_data = udp_tx_req_d0 ? tx_data : 8'd0; //UDP 待发送数据选择

//ICMP 读数据请求信号和 UDP 读数据请求信号寄存一拍
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        icmp_tx_req_d0 <= 1'd0;
        udp_tx_req_d0 <= 1'd0;
    end
    else begin
        icmp_tx_req_d0 <= icmp_tx_req;
        udp_tx_req_d0 <= udp_tx_req;
    end
end

//接收数据使能信号与接收数据的判断
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rec_en <= 1'd0;
        rec_data <= 1'd0;
    end
    else if (icmp_rec_en) begin
        rec_en <= icmp_rec_en;
        rec_data <= icmp_rec_data;
    end
    else if(udp_rec_en) begin
        rec_en <= udp_rec_en;
        rec_data <= udp_rec_data;
    end
    else begin
        rec_en <= 1'd0;
        rec_data <= rec_data;
    end
end

//协议的切换
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        gmii_tx_en <= 1'd0;
        gmii_txd <= 8'd0;
    end
    else begin
        case(protocol_sw)
            2'b00: begin
                gmii_tx_en <= arp_gmii_tx_en;
                gmii_txd <= arp_gmii_txd;
            end
            2'b01: begin
                gmii_tx_en <= udp_gmii_tx_en;
                gmii_txd <= udp_gmii_txd ; 
            end
            2'b10: begin
                gmii_tx_en <= icmp_gmii_tx_en;
                gmii_txd <= icmp_gmii_txd;
            end
            default:;
        endcase
    end
end

//控制 ICMP 发送忙信号
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        icmp_tx_busy <= 1'b0;
    end
    else if(icmp_tx_start_en)
        icmp_tx_busy <= 1'b1;
    else if(icmp_tx_done)
        icmp_tx_busy <= 1'b0;
    else ; 
end

//控制 UDP 发送忙信号
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        udp_tx_busy <= 1'b0;
    else if(udp_tx_start_en)
        udp_tx_busy <= 1'b1;
    else if(udp_tx_done)
        udp_tx_busy <= 1'b0;
    else ;
end

//控制接收到 ARP 请求信号的标志
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        arp_rx_flag <= 1'b0;
    else if(arp_rx_done && (arp_rx_type == 1'b0)) 
        arp_rx_flag <= 1'b1;
    else
        arp_rx_flag <= 1'b0;
end

//控制 protocol_sw 和 arp_tx_en 信号
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        protocol_sw <= 2'b0;
        arp_tx_en <= 1'b0;
    end
    else begin
        arp_tx_en <= 1'b0;
        if (udp_tx_start_en) begin
            protocol_sw <= 2'b01;
        end
        else if(icmp_tx_start_en) begin
            protocol_sw <= 2'b10;
        end
        else if((arp_rx_flag && (udp_tx_busy == 1'b0)) || (arp_rx_flag && (icmp_tx_busy == 1'b0))) begin
            protocol_sw <= 2'b0;
            arp_tx_en <= 1'b1;
        end 
        else ;
    end 
end

endmodule
