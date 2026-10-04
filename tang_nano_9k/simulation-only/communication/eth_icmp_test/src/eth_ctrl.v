module eth_ctrl(
input clk , //系统时钟
input rst_n , //系统复位信号，低电平有效
//ARP 相关端口信号
input arp_rx_done, //ARP 接收完成信号
input arp_rx_type, //ARP 接收类型 0:请求 1:应答
output reg arp_tx_en, //ARP 发送使能信号
output arp_tx_type, //ARP 发送类型 0:请求 1:应答
input arp_tx_done, //ARP 发送完成信号
input arp_gmii_tx_en, //ARP GMII 输出数据有效信号
input [7:0] arp_gmii_txd, //ARP GMII 输出数据
//UDP 相关端口信号
input icmp_tx_start_en,//ICMP 开始发送信号
input icmp_tx_done, //ICMP 发送完成信号
input icmp_gmii_tx_en, //ICMP GMII 输出数据有效信号
input [7:0] icmp_gmii_txd, //ICMP GMII 输出数据
//GMII 发送引脚
output gmii_tx_en, //GMII 输出数据有效信号
output [7:0] gmii_txd //GMII 输出数据
);

//reg define
reg protocol_sw; //协议切换信号
reg icmp_tx_busy; //ICMP 正在发送数据标志信号
reg arp_rx_flag; //接收到 ARP 请求信号的标志

//*****************************************************
//** main code
//*****************************************************

assign arp_tx_type = 1'b1; //ARP 发送类型固定为 ARP 应答
assign gmii_tx_en = protocol_sw ? icmp_gmii_tx_en : arp_gmii_tx_en;
assign gmii_txd = protocol_sw ? icmp_gmii_txd : arp_gmii_txd;

//控制 ICMP 发送忙信号
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        icmp_tx_busy <= 1'b0;
    else if(icmp_tx_start_en)
        icmp_tx_busy <= 1'b1;
    else if(icmp_tx_done)
        icmp_tx_busy <= 1'b0;
    else;
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
        protocol_sw <= 1'b0;
        arp_tx_en <= 1'b0;
    end
    else begin
        arp_tx_en <= 1'b0;
        if(icmp_tx_start_en)
            protocol_sw <= 1'b1;
        else if(arp_rx_flag && (icmp_tx_busy == 1'b0)) begin
            protocol_sw <= 1'b0;
            arp_tx_en <= 1'b1;
        end
        else;
    end
end

endmodule
