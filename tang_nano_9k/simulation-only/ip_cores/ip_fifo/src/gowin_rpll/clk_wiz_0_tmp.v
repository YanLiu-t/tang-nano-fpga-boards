//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.11.01 Education (64-bit)
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9
//Device Version: C
//Created Time: Thu Jul 30 18:07:31 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    clk_wiz_0 your_instance_name(
        .clkout(clkout), //output clkout
        .lock(lock), //output lock
        .clkoutp(clkoutp), //output clkoutp
        .clkoutd(clkoutd), //output clkoutd
        .reset(reset), //input reset
        .clkin(clkin), //input clkin
        .psda(psda), //input [3:0] psda
        .dutyda(dutyda), //input [3:0] dutyda
        .fdly(fdly) //input [3:0] fdly
    );

//--------Copy end-------------------
