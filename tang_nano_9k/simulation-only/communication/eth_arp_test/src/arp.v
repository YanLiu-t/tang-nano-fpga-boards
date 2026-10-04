module arp(
input               rst_n,         //复位信号，低电平有效
//GMII 接口
input               gmii_rx_clk,   //GMII 接收数据时钟
input               gmii_rx_dv,    //GMII 输入数据有效信号
input      [7:0]    gmii_rxd,      //GMII 输入数据
input               gmii_tx_clk,   //GMII 发送数据时钟
output              gmii_tx_en,    //GMII 输出数据有效信号
output     [7:0]    gmii_txd,      //GMII 输出数据

//用户接口
output              arp_rx_done,   //ARP 接收完成信号
output              arp_rx_type,   //ARP 接收类型 0:请求 1:应答
output     [47:0]   src_mac,       //接收到源 MAC 地址
output     [31:0]   src_ip,        //接收到源 IP 地址
input               arp_tx_en,     //ARP 发送使能信号
input               arp_tx_type,   //ARP 发送类型 0:请求 1:应答
input      [47:0]   des_mac,       //发送的目标 MAC 地址
input      [31:0]   des_ip,        //发送的目标 IP 地址
output              tx_done        //以太网发送完成信号
);

//parameter define
//开发板 MAC 地址 00‑11‑22‑33‑44‑55
parameter BOARD_MAC = 48'h00_11_22_33_44_55;
//开发板 IP 地址 192.168.1.10
parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd10};
//目的 MAC 地址 ff_ff_ff_ff_ff_ff
parameter DES_MAC   = 48'hff_ff_ff_ff_ff_ff;
//目的 IP 地址 192.168.1.102
parameter DES_IP    = {8'd192,8'd168,8'd1,8'd102};

//wire define
wire        crc_en;     //CRC 开始校验使能
wire        crc_clr;    //CRC 数据复位信号
wire [7:0]  crc_d8;     //输入待校验 8 位数据
wire [31:0] crc_data;   //CRC 校验数据
wire [31:0] crc_next;   //CRC 下次校验完成数据

//*****************************************************
//** main code
//*****************************************************

assign crc_d8 = gmii_txd;

//ARP 接收模块
arp_rx
#(
    .BOARD_MAC (BOARD_MAC),
    .BOARD_IP  (BOARD_IP )
)
u_arp_rx(
    .clk        (gmii_rx_clk),
    .rst_n      (rst_n),

    .gmii_rx_dv (gmii_rx_dv),
    .gmii_rxd   (gmii_rxd ),
    .arp_rx_done(arp_rx_done),
    .arp_rx_type(arp_rx_type),
    .src_mac    (src_mac ),
    .src_ip     (src_ip )
);

//ARP 发送模块
arp_tx
#(
    .BOARD_MAC (BOARD_MAC),
    .BOARD_IP  (BOARD_IP ),
    .DES_MAC   (DES_MAC ),
    .DES_IP    (DES_IP )
)
u_arp_tx(
    .clk        (gmii_tx_clk),
    .rst_n      (rst_n),

    .arp_tx_en  (arp_tx_en ),
    .arp_tx_type(arp_tx_type),
    .des_mac    (des_mac ),
    .des_ip     (des_ip ),
    .crc_data   (crc_data ),
    .crc_next   (crc_next[31:24]),
    .tx_done    (tx_done ),
    .gmii_tx_en (gmii_tx_en),
    .gmii_txd   (gmii_txd ),
    .crc_en     (crc_en ),
    .crc_clr    (crc_clr )
);

//以太网发送 CRC 校验模块
crc32_d8 u_crc32_d8(
    .clk      (gmii_tx_clk),
    .rst_n    (rst_n ),
    .data     (crc_d8 ),
    .crc_en   (crc_en ),
    .crc_clr  (crc_clr ),
    .crc_data (crc_data ),
    .crc_next (crc_next )
);

endmodule