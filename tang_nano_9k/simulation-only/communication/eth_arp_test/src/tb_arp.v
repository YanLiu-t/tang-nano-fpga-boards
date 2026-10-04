`timescale 1ns/1ns //定义仿真时间单位 1ns 和仿真时间精度为 1ns

module tb_arp;

//parameter define
parameter T = 8;         //时钟周期为 8ns
parameter OP_CYCLE = 100;//操作周期

//开发板 MAC 地址 00-11-22-33-44-55
parameter BOARD_MAC = 48'h00_11_22_33_44_55;
//实际开发板 IP 地址 192.168.1.10
//为了返回应答,仿真代码将开发板地址设置与目的 IP 地址相同
parameter BOARD_IP  = {8'd192,8'd168,8'd1,8'd102};
//目的 MAC 地址 ff_ff_ff_ff_ff_ff
parameter DES_MAC   = 48'hff_ff_ff_ff_ff_ff;
//目的 IP 地址 192.168.1.102
parameter DES_IP    = {8'd192,8'd168,8'd1,8'd102};

//reg define
reg         gmii_clk;     //时钟信号
reg         sys_rst_n;    //复位信号
reg         arp_tx_en ;   //ARP 发送使能信号
reg         arp_tx_type;  //ARP 发送类型 0:请求 1:应答
reg [3:0]   flow_cnt ;
reg [13:0]  delay_cnt ;

//wire define
wire        gmii_rx_clk;  //GMII 接收时钟
wire        gmii_rx_dv ;  //GMII 接收数据有效信号
wire [7:0]  gmii_rxd ;    //GMII 接收数据
wire        gmii_tx_clk;  //GMII 发送时钟
wire        gmii_tx_en ;  //GMII 发送数据使能信号
wire [7:0]  gmii_txd ;    //GMII 发送数据
wire        arp_rx_done;  //ARP 接收完成信号
wire        arp_rx_type;  //ARP 接收类型 0:请求 1:应答
wire [47:0] src_mac ;     //接收到源 MAC 地址
wire [31:0] src_ip ;      //接收到源 IP 地址
wire [47:0] des_mac ;     //发送的目标 MAC 地址
wire [31:0] des_ip ;      //发送的目标 IP 地址
wire        tx_done ;     //以太网发送完成信号

//*****************************************************
//** main code
//*****************************************************

assign gmii_rx_clk = gmii_clk ;
assign gmii_tx_clk = gmii_clk ;
assign gmii_rx_dv  = gmii_tx_en ;
assign gmii_rxd    = gmii_txd ;
assign des_mac     = src_mac;
assign des_ip      = src_ip;

//给输入信号初始值
initial begin
    gmii_clk   = 1'b0;
    sys_rst_n  = 1'b0;       //复位
    #(T+1) sys_rst_n = 1'b1; //在第(T+1)ns 的时候复位信号拉高
end

//125Mhz 的时钟，周期则为 1/125Mhz=8ns,所以每 4ns，电平取反一次
always #(T/2) gmii_clk = ~gmii_clk;

always @(posedge gmii_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        arp_tx_en   <= 1'b0;
        arp_tx_type <= 1'b0;
        delay_cnt   <= 1'b0;
        flow_cnt    <= 1'b0;
    end
    else begin
        case(flow_cnt)
            'd0 : flow_cnt <= flow_cnt + 1'b1;
            'd1 : begin
                arp_tx_en   <= 1'b1;
                arp_tx_type <= 1'b0; //发送 ARP 请求
                flow_cnt    <= flow_cnt + 1'b1;
            end
            'd2 : begin
                arp_tx_en <= 1'b0;
                flow_cnt  <= flow_cnt + 1'b1;
            end
            'd3 : begin
                if(tx_done)
                    flow_cnt <= flow_cnt + 1'b1;
            end
            'd4 : begin
                delay_cnt <= delay_cnt + 1'b1;
                if(delay_cnt == OP_CYCLE - 1'b1)
                    flow_cnt <= flow_cnt + 1'b1;
            end
            'd5 : begin
                arp_tx_en   <= 1'b1;
                arp_tx_type <= 1'b1; //发送 ARP 应答
                flow_cnt    <= flow_cnt + 1'b1;
            end
            'd6 : begin
                arp_tx_en <= 1'b0;
                flow_cnt  <= flow_cnt + 1'b1;
            end
            'd7 : begin
                if(tx_done)
                    flow_cnt <= flow_cnt + 1'b1;
            end
            default: ;
        endcase
    end
end

//ARP 模块例化
arp
#(
    .BOARD_MAC (BOARD_MAC),
    .BOARD_IP  (BOARD_IP ),
    .DES_MAC   (DES_MAC ),
    .DES_IP    (DES_IP )
)
u_arp(
    .rst_n       (sys_rst_n ),

    .gmii_rx_clk (gmii_rx_clk),
    .gmii_rx_dv  (gmii_rx_dv ),
    .gmii_rxd    (gmii_rxd ),
    .gmii_tx_clk (gmii_tx_clk),
    .gmii_tx_en  (gmii_tx_en ),
    .gmii_txd    (gmii_txd ),

    .arp_rx_done (arp_rx_done),
    .arp_rx_type (arp_rx_type),
    .src_mac     (src_mac ),
    .src_ip      (src_ip ),
    .arp_tx_en   (arp_tx_en ),
    .arp_tx_type (arp_tx_type),
    .des_mac     (des_mac ),
    .des_ip      (des_ip ),
    .tx_done     (tx_done )
);

endmodule