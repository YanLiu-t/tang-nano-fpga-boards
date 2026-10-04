module eth_icmp_test(
input sys_clk , //系统时钟
input sys_rst_n , //系统复位信号，低电平有效
//以太网 RGMII 接口
input eth_rxc , //RGMII 接收数据时钟
input eth_rx_ctl, //RGMII 输入数据有效信号
input [3:0] eth_rxd , //RGMII 输入数据
output eth_txc , //RGMII 发送数据时钟
output eth_tx_ctl, //RGMII 输出数据有效信号
output [3:0] eth_txd , //RGMII 输出数据
output eth_rst_n //以太网芯片复位信号，低电平有效
);

//parameter define
//开发板 MAC 地址 00-11-22-33-44-55
parameter BOARD_MAC = 48'h00_11_22_33_44_55;
//开发板 IP 地址 192.168.1.10
parameter BOARD_IP = {8'd192,8'd168,8'd1,8'd10};
//目的 MAC 地址 ff_ff_ff_ff_ff_ff
parameter DES_MAC = 48'hff_ff_ff_ff_ff_ff;
//目的 IP 地址 192.168.1.102
parameter DES_IP = {8'd192,8'd168,8'd1,8'd102};
//输入数据 IO 延时,此处为 0,即不延时(如果为 n,表示延时 n*78ps)
parameter IDELAY_VALUE = 0;

//wire define
wire gmii_rx_clk; //GMII 接收时钟
wire gmii_rx_dv ; //GMII 接收数据有效信号
wire [7:0] gmii_rxd ; //GMII 接收数据
wire gmii_tx_clk; //GMII 发送时钟
wire gmii_tx_en ; //GMII 发送数据使能信号
wire [7:0] gmii_txd ; //GMII 发送数据

wire arp_gmii_tx_en; //ARP GMII 输出数据有效信号
wire [7:0] arp_gmii_txd ; //ARP GMII 输出数据
wire arp_rx_done ; //ARP 接收完成信号
wire arp_rx_type ; //ARP 接收类型 0:请求 1:应答
wire [47:0] src_mac ; //接收到目的 MAC 地址
wire [31:0] src_ip ; //接收到目的 IP 地址
wire arp_tx_en ; //ARP 发送使能信号
wire arp_tx_type ; //ARP 发送类型 0:请求 1:应答
wire [47:0] des_mac ; //发送的目标 MAC 地址
wire [31:0] des_ip ; //发送的目标 IP 地址
wire arp_tx_done ; //ARP 发送完成信号

wire icmp_gmii_tx_en; //ICMP GMII 输出数据有效信号
wire [7:0] icmp_gmii_txd ; //ICMP GMII 输出数据
wire rec_pkt_done ; //ICMP 单包数据接收完成信号
wire rec_en ; //ICMP 接收的数据使能信号
wire [ 7:0] rec_data ; //ICMP 接收的数据
wire [15:0] rec_byte_num ; //ICMP 接收的有效字节数 单位:byte
wire [15:0] tx_byte_num ; //ICMP 发送的有效字节数 单位:byte
wire icmp_tx_done ; //ICMP 发送完成信号
wire tx_req ; //ICMP 读数据请求信号
wire [ 7:0] tx_data ; //ICMP 待发送数据
wire tx_start_en ; //ICMP 发送开始使能信号

//*****************************************************
//** main code
//*****************************************************

assign tx_start_en = rec_pkt_done;
assign tx_byte_num = rec_byte_num;
assign des_mac = src_mac;
assign des_ip = src_ip;
assign eth_rst_n = sys_rst_n;

//GMII 接口转 RGMII 接口
gmii_to_rgmii u_gmii_to_rgmii(
.gmii_rx_clk (gmii_rx_clk ),
.gmii_rx_dv (gmii_rx_dv ),
.gmii_rxd (gmii_rxd ),
.gmii_tx_clk (gmii_tx_clk ),
.gmii_tx_en (gmii_tx_en ),
.gmii_txd (gmii_txd ),

.rgmii_rxc (~eth_rxc ),
.rgmii_rx_ctl (eth_rx_ctl ),
.rgmii_rxd (eth_rxd ),
.rgmii_txc (eth_txc ),
.rgmii_tx_ctl (eth_tx_ctl ),
.rgmii_txd (eth_txd )
);

//ARP 通信
arp
#(
.BOARD_MAC (BOARD_MAC), //参数例化
.BOARD_IP (BOARD_IP ),
.DES_MAC (DES_MAC ),
.DES_IP (DES_IP )
)
u_arp(
.rst_n (sys_rst_n ),

.gmii_rx_clk (gmii_rx_clk),
.gmii_rx_dv (gmii_rx_dv ),
.gmii_rxd (gmii_rxd ),
.gmii_tx_clk (gmii_tx_clk),
.gmii_tx_en (arp_gmii_tx_en ),
.gmii_txd (arp_gmii_txd),

.arp_rx_done (arp_rx_done),
.arp_rx_type (arp_rx_type),
.src_mac (src_mac ),
.src_ip (src_ip ),
.arp_tx_en (arp_tx_en ),
.arp_tx_type (arp_tx_type),
.des_mac (des_mac ),
.des_ip (des_ip ),
.tx_done (arp_tx_done)
);

//ICMP 通信
icmp
#(
.BOARD_MAC (BOARD_MAC), //参数例化
.BOARD_IP (BOARD_IP ),
.DES_MAC (DES_MAC ),
.DES_IP (DES_IP )
)
u_icmp(
.rst_n (sys_rst_n ),

.gmii_rx_clk (gmii_rx_clk ),
.gmii_rx_dv (gmii_rx_dv ),
.gmii_rxd (gmii_rxd ),
.gmii_tx_clk (gmii_tx_clk ),
.gmii_tx_en (icmp_gmii_tx_en),
.gmii_txd (icmp_gmii_txd),

.rec_pkt_done (rec_pkt_done),
.rec_en (rec_en ),
.rec_data (rec_data ),
.rec_byte_num (rec_byte_num),
.tx_start_en (tx_start_en ),
.tx_data (tx_data ),
.tx_byte_num (tx_byte_num ),
.des_mac (des_mac ),
.des_ip (des_ip ),
.tx_done (icmp_tx_done),
.tx_req (tx_req )
);

//同步 FIFO
sync_fifo_2048x8b sync_fifo_2048x8b(
.Data (rec_data ),
.Clk (gmii_rx_clk),
.WrEn (rec_en ),
.RdEn (tx_req ),
.Reset (~sys_rst_n ),
.Q (tx_data ),
.Empty ( ),
.Full ( )
);

eth_ctrl u_eth_ctrl(
.clk (gmii_rx_clk),
.rst_n (sys_rst_n),

.arp_rx_done (arp_rx_done ),
.arp_rx_type (arp_rx_type ),
.arp_tx_en (arp_tx_en ),
.arp_tx_type (arp_tx_type ),
.arp_tx_done (arp_tx_done ),
.arp_gmii_tx_en (arp_gmii_tx_en),
.arp_gmii_txd (arp_gmii_txd ),

.icmp_tx_start_en(tx_start_en ),
.icmp_tx_done (icmp_tx_done ),
.icmp_gmii_tx_en (icmp_gmii_tx_en),
.icmp_gmii_txd (icmp_gmii_txd ),

.gmii_tx_en (gmii_tx_en ),
.gmii_txd (gmii_txd )
);

endmodule
