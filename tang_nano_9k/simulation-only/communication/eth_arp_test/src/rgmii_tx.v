module rgmii_tx(
//GMII 发送端口
input        gmii_tx_clk,    //GMII 发送时钟
input        gmii_tx_en,     //GMII 发送数据使能信号
input [7:0]  gmii_txd,       //GMII 输出数据

//RGMII 发送端口
output       rgmii_txc,      //RGMII 发送数据时钟
output       rgmii_tx_ctl,   //RGMII 输出数据有效信号
output [3:0] rgmii_txd       //RGMII 输出数据
);

//*****************************************************
//** main code
//*****************************************************

assign rgmii_txc = gmii_tx_clk;

genvar i;
generate for(i=0;i<4;i=i+1)
begin: ODDRo41
ODDR ODDRo41(
.Q0  (rgmii_txd[i]),
.Q1  (),
.D0  (gmii_txd[i]),
.D1  (gmii_txd[4+i]),
.TX  (1'b0),
.CLK (gmii_tx_clk)
);
end
endgenerate

defparam ODDRo41.INIT      = 1'b0;
defparam ODDRo41.TXCLK_POL = 1'b0;

ODDR ODDRo42(
.Q0  (rgmii_tx_ctl),
.Q1  (),
.D0  (gmii_tx_en),
.D1  (gmii_tx_en),
.TX  (1'b0),
.CLK (gmii_tx_clk)
);
defparam ODDRo42.INIT      = 1'b0;
defparam ODDRo42.TXCLK_POL = 1'b0;

endmodule