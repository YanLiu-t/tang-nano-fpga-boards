//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.11.01 Education (64-bit)
//Part Number: GW1NR-LV9QN88PC6/I5
//Device: GW1NR-9
//Device Version: C
//Created Time: Mon Jul 27 17:43:14 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    gowin_rpll your_instance_name(
        .clkout(clkout), //output clkout
        .lock(lock), //output lock
        .clkoutp(clkoutp), //output clkoutp
        .clkoutd(clkoutd), //output clkoutd
        .clkoutd3(clkoutd3), //output clkoutd3
        .reset(reset), //input reset
        .clkin(clkin), //input clkin
        .clkfb(clkfb) //input clkfb
    );

//--------Copy end-------------------
