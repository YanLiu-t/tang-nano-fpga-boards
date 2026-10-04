//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//Tool Version: V1.9.11.01 Education (64-bit)
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9
//Device Version: C
//Created Time: Tue Aug  4 16:47:46 2026

module blk_mem_gen_0 (dout, clk, oce, ce, reset, ad);

output [23:0] dout;
input clk;
input oce;
input ce;
input reset;
input [13:0] ad;

wire lut_f_0;
wire lut_f_1;
wire lut_f_2;
wire lut_f_3;
wire lut_f_4;
wire lut_f_5;
wire [26:0] promx9_inst_0_dout_w;
wire [8:0] promx9_inst_0_dout;
wire [26:0] promx9_inst_1_dout_w;
wire [8:0] promx9_inst_1_dout;
wire [26:0] promx9_inst_2_dout_w;
wire [8:0] promx9_inst_2_dout;
wire [26:0] promx9_inst_3_dout_w;
wire [8:0] promx9_inst_3_dout;
wire [26:0] promx9_inst_4_dout_w;
wire [17:9] promx9_inst_4_dout;
wire [26:0] promx9_inst_5_dout_w;
wire [17:9] promx9_inst_5_dout;
wire [26:0] promx9_inst_6_dout_w;
wire [17:9] promx9_inst_6_dout;
wire [26:0] promx9_inst_7_dout_w;
wire [17:9] promx9_inst_7_dout;
wire [29:0] prom_inst_8_dout_w;
wire [19:18] prom_inst_8_dout;
wire [29:0] prom_inst_9_dout_w;
wire [21:20] prom_inst_9_dout;
wire [29:0] prom_inst_10_dout_w;
wire [23:22] prom_inst_10_dout;
wire [23:0] prom_inst_11_dout_w;
wire [7:0] prom_inst_11_dout;
wire [23:0] prom_inst_12_dout_w;
wire [15:8] prom_inst_12_dout;
wire [23:0] prom_inst_13_dout_w;
wire [23:16] prom_inst_13_dout;
wire dff_q_0;
wire dff_q_1;
wire dff_q_2;
wire mux_o_0;
wire mux_o_1;
wire mux_o_3;
wire mux_o_6;
wire mux_o_7;
wire mux_o_9;
wire mux_o_12;
wire mux_o_13;
wire mux_o_15;
wire mux_o_18;
wire mux_o_19;
wire mux_o_21;
wire mux_o_24;
wire mux_o_25;
wire mux_o_27;
wire mux_o_30;
wire mux_o_31;
wire mux_o_33;
wire mux_o_36;
wire mux_o_37;
wire mux_o_39;
wire mux_o_42;
wire mux_o_43;
wire mux_o_45;
wire mux_o_48;
wire mux_o_49;
wire mux_o_51;
wire mux_o_54;
wire mux_o_55;
wire mux_o_57;
wire mux_o_60;
wire mux_o_61;
wire mux_o_63;
wire mux_o_66;
wire mux_o_67;
wire mux_o_69;
wire mux_o_72;
wire mux_o_73;
wire mux_o_75;
wire mux_o_78;
wire mux_o_79;
wire mux_o_81;
wire mux_o_84;
wire mux_o_85;
wire mux_o_87;
wire mux_o_90;
wire mux_o_91;
wire mux_o_93;
wire mux_o_96;
wire mux_o_97;
wire mux_o_99;
wire mux_o_102;
wire mux_o_103;
wire mux_o_105;
wire gw_gnd;

assign gw_gnd = 1'b0;

LUT4 lut_inst_0 (
  .F(lut_f_0),
  .I0(ce),
  .I1(ad[11]),
  .I2(ad[12]),
  .I3(ad[13])
);
defparam lut_inst_0.INIT = 16'h0002;
LUT4 lut_inst_1 (
  .F(lut_f_1),
  .I0(ce),
  .I1(ad[11]),
  .I2(ad[12]),
  .I3(ad[13])
);
defparam lut_inst_1.INIT = 16'h0008;
LUT4 lut_inst_2 (
  .F(lut_f_2),
  .I0(ce),
  .I1(ad[11]),
  .I2(ad[12]),
  .I3(ad[13])
);
defparam lut_inst_2.INIT = 16'h0020;
LUT4 lut_inst_3 (
  .F(lut_f_3),
  .I0(ce),
  .I1(ad[11]),
  .I2(ad[12]),
  .I3(ad[13])
);
defparam lut_inst_3.INIT = 16'h0080;
LUT2 lut_inst_4 (
  .F(lut_f_4),
  .I0(ce),
  .I1(ad[13])
);
defparam lut_inst_4.INIT = 4'h2;
LUT4 lut_inst_5 (
  .F(lut_f_5),
  .I0(ce),
  .I1(ad[11]),
  .I2(ad[12]),
  .I3(ad[13])
);
defparam lut_inst_5.INIT = 16'h0200;
pROMX9 promx9_inst_0 (
    .DO({promx9_inst_0_dout_w[26:0],promx9_inst_0_dout[8:0]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_0),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_0.READ_MODE = 1'b0;
defparam promx9_inst_0.BIT_WIDTH = 9;
defparam promx9_inst_0.RESET_MODE = "SYNC";

pROMX9 promx9_inst_1 (
    .DO({promx9_inst_1_dout_w[26:0],promx9_inst_1_dout[8:0]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_1),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_1.READ_MODE = 1'b0;
defparam promx9_inst_1.BIT_WIDTH = 9;
defparam promx9_inst_1.RESET_MODE = "SYNC";

pROMX9 promx9_inst_2 (
    .DO({promx9_inst_2_dout_w[26:0],promx9_inst_2_dout[8:0]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_2),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_2.READ_MODE = 1'b0;
defparam promx9_inst_2.BIT_WIDTH = 9;
defparam promx9_inst_2.RESET_MODE = "SYNC";

pROMX9 promx9_inst_3 (
    .DO({promx9_inst_3_dout_w[26:0],promx9_inst_3_dout[8:0]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_3),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_3.READ_MODE = 1'b0;
defparam promx9_inst_3.BIT_WIDTH = 9;
defparam promx9_inst_3.RESET_MODE = "SYNC";

pROMX9 promx9_inst_4 (
    .DO({promx9_inst_4_dout_w[26:0],promx9_inst_4_dout[17:9]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_0),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_4.READ_MODE = 1'b0;
defparam promx9_inst_4.BIT_WIDTH = 9;
defparam promx9_inst_4.RESET_MODE = "SYNC";

pROMX9 promx9_inst_5 (
    .DO({promx9_inst_5_dout_w[26:0],promx9_inst_5_dout[17:9]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_1),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_5.READ_MODE = 1'b0;
defparam promx9_inst_5.BIT_WIDTH = 9;
defparam promx9_inst_5.RESET_MODE = "SYNC";

pROMX9 promx9_inst_6 (
    .DO({promx9_inst_6_dout_w[26:0],promx9_inst_6_dout[17:9]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_2),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_6.READ_MODE = 1'b0;
defparam promx9_inst_6.BIT_WIDTH = 9;
defparam promx9_inst_6.RESET_MODE = "SYNC";

pROMX9 promx9_inst_7 (
    .DO({promx9_inst_7_dout_w[26:0],promx9_inst_7_dout[17:9]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_3),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam promx9_inst_7.READ_MODE = 1'b0;
defparam promx9_inst_7.BIT_WIDTH = 9;
defparam promx9_inst_7.RESET_MODE = "SYNC";

pROM prom_inst_8 (
    .DO({prom_inst_8_dout_w[29:0],prom_inst_8_dout[19:18]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_4),
    .RESET(reset),
    .AD({ad[12:0],gw_gnd})
);

defparam prom_inst_8.READ_MODE = 1'b0;
defparam prom_inst_8.BIT_WIDTH = 2;
defparam prom_inst_8.RESET_MODE = "SYNC";

pROM prom_inst_9 (
    .DO({prom_inst_9_dout_w[29:0],prom_inst_9_dout[21:20]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_4),
    .RESET(reset),
    .AD({ad[12:0],gw_gnd})
);

defparam prom_inst_9.READ_MODE = 1'b0;
defparam prom_inst_9.BIT_WIDTH = 2;
defparam prom_inst_9.RESET_MODE = "SYNC";

pROM prom_inst_10 (
    .DO({prom_inst_10_dout_w[29:0],prom_inst_10_dout[23:22]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_4),
    .RESET(reset),
    .AD({ad[12:0],gw_gnd})
);

defparam prom_inst_10.READ_MODE = 1'b0;
defparam prom_inst_10.BIT_WIDTH = 2;
defparam prom_inst_10.RESET_MODE = "SYNC";

pROM prom_inst_11 (
    .DO({prom_inst_11_dout_w[23:0],prom_inst_11_dout[7:0]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_5),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam prom_inst_11.READ_MODE = 1'b0;
defparam prom_inst_11.BIT_WIDTH = 8;
defparam prom_inst_11.RESET_MODE = "SYNC";

pROM prom_inst_12 (
    .DO({prom_inst_12_dout_w[23:0],prom_inst_12_dout[15:8]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_5),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam prom_inst_12.READ_MODE = 1'b0;
defparam prom_inst_12.BIT_WIDTH = 8;
defparam prom_inst_12.RESET_MODE = "SYNC";

pROM prom_inst_13 (
    .DO({prom_inst_13_dout_w[23:0],prom_inst_13_dout[23:16]}),
    .CLK(clk),
    .OCE(oce),
    .CE(lut_f_5),
    .RESET(reset),
    .AD({ad[10:0],gw_gnd,gw_gnd,gw_gnd})
);

defparam prom_inst_13.READ_MODE = 1'b0;
defparam prom_inst_13.BIT_WIDTH = 8;
defparam prom_inst_13.RESET_MODE = "SYNC";

DFFE dff_inst_0 (
  .Q(dff_q_0),
  .D(ad[13]),
  .CLK(clk),
  .CE(ce)
);
DFFE dff_inst_1 (
  .Q(dff_q_1),
  .D(ad[12]),
  .CLK(clk),
  .CE(ce)
);
DFFE dff_inst_2 (
  .Q(dff_q_2),
  .D(ad[11]),
  .CLK(clk),
  .CE(ce)
);
MUX2 mux_inst_0 (
  .O(mux_o_0),
  .I0(promx9_inst_0_dout[0]),
  .I1(promx9_inst_1_dout[0]),
  .S0(dff_q_2)
);
MUX2 mux_inst_1 (
  .O(mux_o_1),
  .I0(promx9_inst_2_dout[0]),
  .I1(promx9_inst_3_dout[0]),
  .S0(dff_q_2)
);
MUX2 mux_inst_3 (
  .O(mux_o_3),
  .I0(mux_o_0),
  .I1(mux_o_1),
  .S0(dff_q_1)
);
MUX2 mux_inst_5 (
  .O(dout[0]),
  .I0(mux_o_3),
  .I1(prom_inst_11_dout[0]),
  .S0(dff_q_0)
);
MUX2 mux_inst_6 (
  .O(mux_o_6),
  .I0(promx9_inst_0_dout[1]),
  .I1(promx9_inst_1_dout[1]),
  .S0(dff_q_2)
);
MUX2 mux_inst_7 (
  .O(mux_o_7),
  .I0(promx9_inst_2_dout[1]),
  .I1(promx9_inst_3_dout[1]),
  .S0(dff_q_2)
);
MUX2 mux_inst_9 (
  .O(mux_o_9),
  .I0(mux_o_6),
  .I1(mux_o_7),
  .S0(dff_q_1)
);
MUX2 mux_inst_11 (
  .O(dout[1]),
  .I0(mux_o_9),
  .I1(prom_inst_11_dout[1]),
  .S0(dff_q_0)
);
MUX2 mux_inst_12 (
  .O(mux_o_12),
  .I0(promx9_inst_0_dout[2]),
  .I1(promx9_inst_1_dout[2]),
  .S0(dff_q_2)
);
MUX2 mux_inst_13 (
  .O(mux_o_13),
  .I0(promx9_inst_2_dout[2]),
  .I1(promx9_inst_3_dout[2]),
  .S0(dff_q_2)
);
MUX2 mux_inst_15 (
  .O(mux_o_15),
  .I0(mux_o_12),
  .I1(mux_o_13),
  .S0(dff_q_1)
);
MUX2 mux_inst_17 (
  .O(dout[2]),
  .I0(mux_o_15),
  .I1(prom_inst_11_dout[2]),
  .S0(dff_q_0)
);
MUX2 mux_inst_18 (
  .O(mux_o_18),
  .I0(promx9_inst_0_dout[3]),
  .I1(promx9_inst_1_dout[3]),
  .S0(dff_q_2)
);
MUX2 mux_inst_19 (
  .O(mux_o_19),
  .I0(promx9_inst_2_dout[3]),
  .I1(promx9_inst_3_dout[3]),
  .S0(dff_q_2)
);
MUX2 mux_inst_21 (
  .O(mux_o_21),
  .I0(mux_o_18),
  .I1(mux_o_19),
  .S0(dff_q_1)
);
MUX2 mux_inst_23 (
  .O(dout[3]),
  .I0(mux_o_21),
  .I1(prom_inst_11_dout[3]),
  .S0(dff_q_0)
);
MUX2 mux_inst_24 (
  .O(mux_o_24),
  .I0(promx9_inst_0_dout[4]),
  .I1(promx9_inst_1_dout[4]),
  .S0(dff_q_2)
);
MUX2 mux_inst_25 (
  .O(mux_o_25),
  .I0(promx9_inst_2_dout[4]),
  .I1(promx9_inst_3_dout[4]),
  .S0(dff_q_2)
);
MUX2 mux_inst_27 (
  .O(mux_o_27),
  .I0(mux_o_24),
  .I1(mux_o_25),
  .S0(dff_q_1)
);
MUX2 mux_inst_29 (
  .O(dout[4]),
  .I0(mux_o_27),
  .I1(prom_inst_11_dout[4]),
  .S0(dff_q_0)
);
MUX2 mux_inst_30 (
  .O(mux_o_30),
  .I0(promx9_inst_0_dout[5]),
  .I1(promx9_inst_1_dout[5]),
  .S0(dff_q_2)
);
MUX2 mux_inst_31 (
  .O(mux_o_31),
  .I0(promx9_inst_2_dout[5]),
  .I1(promx9_inst_3_dout[5]),
  .S0(dff_q_2)
);
MUX2 mux_inst_33 (
  .O(mux_o_33),
  .I0(mux_o_30),
  .I1(mux_o_31),
  .S0(dff_q_1)
);
MUX2 mux_inst_35 (
  .O(dout[5]),
  .I0(mux_o_33),
  .I1(prom_inst_11_dout[5]),
  .S0(dff_q_0)
);
MUX2 mux_inst_36 (
  .O(mux_o_36),
  .I0(promx9_inst_0_dout[6]),
  .I1(promx9_inst_1_dout[6]),
  .S0(dff_q_2)
);
MUX2 mux_inst_37 (
  .O(mux_o_37),
  .I0(promx9_inst_2_dout[6]),
  .I1(promx9_inst_3_dout[6]),
  .S0(dff_q_2)
);
MUX2 mux_inst_39 (
  .O(mux_o_39),
  .I0(mux_o_36),
  .I1(mux_o_37),
  .S0(dff_q_1)
);
MUX2 mux_inst_41 (
  .O(dout[6]),
  .I0(mux_o_39),
  .I1(prom_inst_11_dout[6]),
  .S0(dff_q_0)
);
MUX2 mux_inst_42 (
  .O(mux_o_42),
  .I0(promx9_inst_0_dout[7]),
  .I1(promx9_inst_1_dout[7]),
  .S0(dff_q_2)
);
MUX2 mux_inst_43 (
  .O(mux_o_43),
  .I0(promx9_inst_2_dout[7]),
  .I1(promx9_inst_3_dout[7]),
  .S0(dff_q_2)
);
MUX2 mux_inst_45 (
  .O(mux_o_45),
  .I0(mux_o_42),
  .I1(mux_o_43),
  .S0(dff_q_1)
);
MUX2 mux_inst_47 (
  .O(dout[7]),
  .I0(mux_o_45),
  .I1(prom_inst_11_dout[7]),
  .S0(dff_q_0)
);
MUX2 mux_inst_48 (
  .O(mux_o_48),
  .I0(promx9_inst_0_dout[8]),
  .I1(promx9_inst_1_dout[8]),
  .S0(dff_q_2)
);
MUX2 mux_inst_49 (
  .O(mux_o_49),
  .I0(promx9_inst_2_dout[8]),
  .I1(promx9_inst_3_dout[8]),
  .S0(dff_q_2)
);
MUX2 mux_inst_51 (
  .O(mux_o_51),
  .I0(mux_o_48),
  .I1(mux_o_49),
  .S0(dff_q_1)
);
MUX2 mux_inst_53 (
  .O(dout[8]),
  .I0(mux_o_51),
  .I1(prom_inst_12_dout[8]),
  .S0(dff_q_0)
);
MUX2 mux_inst_54 (
  .O(mux_o_54),
  .I0(promx9_inst_4_dout[9]),
  .I1(promx9_inst_5_dout[9]),
  .S0(dff_q_2)
);
MUX2 mux_inst_55 (
  .O(mux_o_55),
  .I0(promx9_inst_6_dout[9]),
  .I1(promx9_inst_7_dout[9]),
  .S0(dff_q_2)
);
MUX2 mux_inst_57 (
  .O(mux_o_57),
  .I0(mux_o_54),
  .I1(mux_o_55),
  .S0(dff_q_1)
);
MUX2 mux_inst_59 (
  .O(dout[9]),
  .I0(mux_o_57),
  .I1(prom_inst_12_dout[9]),
  .S0(dff_q_0)
);
MUX2 mux_inst_60 (
  .O(mux_o_60),
  .I0(promx9_inst_4_dout[10]),
  .I1(promx9_inst_5_dout[10]),
  .S0(dff_q_2)
);
MUX2 mux_inst_61 (
  .O(mux_o_61),
  .I0(promx9_inst_6_dout[10]),
  .I1(promx9_inst_7_dout[10]),
  .S0(dff_q_2)
);
MUX2 mux_inst_63 (
  .O(mux_o_63),
  .I0(mux_o_60),
  .I1(mux_o_61),
  .S0(dff_q_1)
);
MUX2 mux_inst_65 (
  .O(dout[10]),
  .I0(mux_o_63),
  .I1(prom_inst_12_dout[10]),
  .S0(dff_q_0)
);
MUX2 mux_inst_66 (
  .O(mux_o_66),
  .I0(promx9_inst_4_dout[11]),
  .I1(promx9_inst_5_dout[11]),
  .S0(dff_q_2)
);
MUX2 mux_inst_67 (
  .O(mux_o_67),
  .I0(promx9_inst_6_dout[11]),
  .I1(promx9_inst_7_dout[11]),
  .S0(dff_q_2)
);
MUX2 mux_inst_69 (
  .O(mux_o_69),
  .I0(mux_o_66),
  .I1(mux_o_67),
  .S0(dff_q_1)
);
MUX2 mux_inst_71 (
  .O(dout[11]),
  .I0(mux_o_69),
  .I1(prom_inst_12_dout[11]),
  .S0(dff_q_0)
);
MUX2 mux_inst_72 (
  .O(mux_o_72),
  .I0(promx9_inst_4_dout[12]),
  .I1(promx9_inst_5_dout[12]),
  .S0(dff_q_2)
);
MUX2 mux_inst_73 (
  .O(mux_o_73),
  .I0(promx9_inst_6_dout[12]),
  .I1(promx9_inst_7_dout[12]),
  .S0(dff_q_2)
);
MUX2 mux_inst_75 (
  .O(mux_o_75),
  .I0(mux_o_72),
  .I1(mux_o_73),
  .S0(dff_q_1)
);
MUX2 mux_inst_77 (
  .O(dout[12]),
  .I0(mux_o_75),
  .I1(prom_inst_12_dout[12]),
  .S0(dff_q_0)
);
MUX2 mux_inst_78 (
  .O(mux_o_78),
  .I0(promx9_inst_4_dout[13]),
  .I1(promx9_inst_5_dout[13]),
  .S0(dff_q_2)
);
MUX2 mux_inst_79 (
  .O(mux_o_79),
  .I0(promx9_inst_6_dout[13]),
  .I1(promx9_inst_7_dout[13]),
  .S0(dff_q_2)
);
MUX2 mux_inst_81 (
  .O(mux_o_81),
  .I0(mux_o_78),
  .I1(mux_o_79),
  .S0(dff_q_1)
);
MUX2 mux_inst_83 (
  .O(dout[13]),
  .I0(mux_o_81),
  .I1(prom_inst_12_dout[13]),
  .S0(dff_q_0)
);
MUX2 mux_inst_84 (
  .O(mux_o_84),
  .I0(promx9_inst_4_dout[14]),
  .I1(promx9_inst_5_dout[14]),
  .S0(dff_q_2)
);
MUX2 mux_inst_85 (
  .O(mux_o_85),
  .I0(promx9_inst_6_dout[14]),
  .I1(promx9_inst_7_dout[14]),
  .S0(dff_q_2)
);
MUX2 mux_inst_87 (
  .O(mux_o_87),
  .I0(mux_o_84),
  .I1(mux_o_85),
  .S0(dff_q_1)
);
MUX2 mux_inst_89 (
  .O(dout[14]),
  .I0(mux_o_87),
  .I1(prom_inst_12_dout[14]),
  .S0(dff_q_0)
);
MUX2 mux_inst_90 (
  .O(mux_o_90),
  .I0(promx9_inst_4_dout[15]),
  .I1(promx9_inst_5_dout[15]),
  .S0(dff_q_2)
);
MUX2 mux_inst_91 (
  .O(mux_o_91),
  .I0(promx9_inst_6_dout[15]),
  .I1(promx9_inst_7_dout[15]),
  .S0(dff_q_2)
);
MUX2 mux_inst_93 (
  .O(mux_o_93),
  .I0(mux_o_90),
  .I1(mux_o_91),
  .S0(dff_q_1)
);
MUX2 mux_inst_95 (
  .O(dout[15]),
  .I0(mux_o_93),
  .I1(prom_inst_12_dout[15]),
  .S0(dff_q_0)
);
MUX2 mux_inst_96 (
  .O(mux_o_96),
  .I0(promx9_inst_4_dout[16]),
  .I1(promx9_inst_5_dout[16]),
  .S0(dff_q_2)
);
MUX2 mux_inst_97 (
  .O(mux_o_97),
  .I0(promx9_inst_6_dout[16]),
  .I1(promx9_inst_7_dout[16]),
  .S0(dff_q_2)
);
MUX2 mux_inst_99 (
  .O(mux_o_99),
  .I0(mux_o_96),
  .I1(mux_o_97),
  .S0(dff_q_1)
);
MUX2 mux_inst_101 (
  .O(dout[16]),
  .I0(mux_o_99),
  .I1(prom_inst_13_dout[16]),
  .S0(dff_q_0)
);
MUX2 mux_inst_102 (
  .O(mux_o_102),
  .I0(promx9_inst_4_dout[17]),
  .I1(promx9_inst_5_dout[17]),
  .S0(dff_q_2)
);
MUX2 mux_inst_103 (
  .O(mux_o_103),
  .I0(promx9_inst_6_dout[17]),
  .I1(promx9_inst_7_dout[17]),
  .S0(dff_q_2)
);
MUX2 mux_inst_105 (
  .O(mux_o_105),
  .I0(mux_o_102),
  .I1(mux_o_103),
  .S0(dff_q_1)
);
MUX2 mux_inst_107 (
  .O(dout[17]),
  .I0(mux_o_105),
  .I1(prom_inst_13_dout[17]),
  .S0(dff_q_0)
);
MUX2 mux_inst_112 (
  .O(dout[18]),
  .I0(prom_inst_8_dout[18]),
  .I1(prom_inst_13_dout[18]),
  .S0(dff_q_0)
);
MUX2 mux_inst_117 (
  .O(dout[19]),
  .I0(prom_inst_8_dout[19]),
  .I1(prom_inst_13_dout[19]),
  .S0(dff_q_0)
);
MUX2 mux_inst_122 (
  .O(dout[20]),
  .I0(prom_inst_9_dout[20]),
  .I1(prom_inst_13_dout[20]),
  .S0(dff_q_0)
);
MUX2 mux_inst_127 (
  .O(dout[21]),
  .I0(prom_inst_9_dout[21]),
  .I1(prom_inst_13_dout[21]),
  .S0(dff_q_0)
);
MUX2 mux_inst_132 (
  .O(dout[22]),
  .I0(prom_inst_10_dout[22]),
  .I1(prom_inst_13_dout[22]),
  .S0(dff_q_0)
);
MUX2 mux_inst_137 (
  .O(dout[23]),
  .I0(prom_inst_10_dout[23]),
  .I1(prom_inst_13_dout[23]),
  .S0(dff_q_0)
);
endmodule //blk_mem_gen_0
