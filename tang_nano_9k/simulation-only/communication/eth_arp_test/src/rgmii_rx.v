module rgmii_rx(
//以太网 RGMII 接口
input rgmii_rxc ,        //RGMII 接收时钟
input rgmii_rx_ctl ,     //RGMII 接收数据控制信号
input [3:0] rgmii_rxd ,  //RGMII 接收数据

//以太网 GMII 接口
output gmii_rx_clk ,     //GMII 接收时钟
output gmii_rx_dv ,      //GMII 接收数据有效信号
output [7:0] gmii_rxd    //GMII 接收数据
);

//define wire
wire rgmii_rx_ctl_delay; //rgmii_rx_ctl 输入延时
wire [3:0] rgmii_rxd_delay; //rgmii_rxd 输入延时
wire [1:0] gmii_rxdv_t;  //两位 GMII 接收有效信号

//*****************************************************
//** main code
//*****************************************************

assign gmii_rx_clk = rgmii_rxc;
assign gmii_rx_dv = gmii_rxdv_t[0] & gmii_rxdv_t[1];

genvar i;
generate for(i = 0;i<4;i=i+1)
begin: iodelay_rxd
IODELAY iodelay_rxd(
.DO (rgmii_rxd_delay[i]),
.DF (),
.DI (rgmii_rxd[i]),
.SDTAP (0),
.SETN (0),
.VALUE (16)
);
defparam iodelay_rxd.C_STATIC_DLY=0;

IDDR iddr_rxd(
.Q0 (gmii_rxd[i]),
.Q1 (gmii_rxd[i+4]),
.D (rgmii_rxd_delay[i]),
.CLK (rgmii_rxc)
);
defparam iddr_rxd.Q0_INIT = 1'b0;
defparam iddr_rxd.Q1_INIT = 1'b0;

end
endgenerate

IODELAY delay_rx_ctrl(
.DO (rgmii_rx_ctl_delay),
.DF (),
.DI (rgmii_rx_ctl),
.SDTAP (0),
.SETN (0),
.VALUE (16)
);
defparam iodelay_rxd.C_STATIC_DLY=0;

IDDR iddr_rx_ctrl(
.Q0 (gmii_rxdv_t[0]),
.Q1 (gmii_rxdv_t[1]),
.D (rgmii_rx_ctl_delay),
.CLK (rgmii_rxc)
);
defparam iddr_rx_ctrl.Q0_INIT = 1'b0;
defparam iddr_rx_ctrl.Q1_INIT = 1'b0;

endmodule