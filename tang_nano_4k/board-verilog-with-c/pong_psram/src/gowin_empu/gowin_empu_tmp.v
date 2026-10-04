//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.11.01 Education (64-bit)
//Part Number: GW1NSR-LV4CQN48PC6/I5
//Device: GW1NSR-4C
//Created Time: Fri Sep 25 21:25:17 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	Gowin_EMPU_Top your_instance_name(
		.sys_clk(sys_clk), //input sys_clk
		.uart0_rxd(uart0_rxd), //input uart0_rxd
		.uart0_txd(uart0_txd), //output uart0_txd
		.master_pclk(master_pclk), //output master_pclk
		.master_prst(master_prst), //output master_prst
		.master_penable(master_penable), //output master_penable
		.master_paddr(master_paddr), //output [7:0] master_paddr
		.master_pwrite(master_pwrite), //output master_pwrite
		.master_pwdata(master_pwdata), //output [31:0] master_pwdata
		.master_pstrb(master_pstrb), //output [3:0] master_pstrb
		.master_pprot(master_pprot), //output [2:0] master_pprot
		.master_psel1(master_psel1), //output master_psel1
		.master_prdata1(master_prdata1), //input [31:0] master_prdata1
		.master_pready1(master_pready1), //input master_pready1
		.master_pslverr1(master_pslverr1), //input master_pslverr1
		.master_hclk(master_hclk), //output master_hclk
		.master_hrst(master_hrst), //output master_hrst
		.master_hsel(master_hsel), //output master_hsel
		.master_haddr(master_haddr), //output [31:0] master_haddr
		.master_htrans(master_htrans), //output [1:0] master_htrans
		.master_hwrite(master_hwrite), //output master_hwrite
		.master_hsize(master_hsize), //output [2:0] master_hsize
		.master_hburst(master_hburst), //output [2:0] master_hburst
		.master_hprot(master_hprot), //output [3:0] master_hprot
		.master_hmemattr(master_hmemattr), //output [1:0] master_hmemattr
		.master_hexreq(master_hexreq), //output master_hexreq
		.master_hmaster(master_hmaster), //output [3:0] master_hmaster
		.master_hwdata(master_hwdata), //output [31:0] master_hwdata
		.master_hmastlock(master_hmastlock), //output master_hmastlock
		.master_hreadymux(master_hreadymux), //output master_hreadymux
		.master_hauser(master_hauser), //output master_hauser
		.master_hwuser(master_hwuser), //output [3:0] master_hwuser
		.master_hrdata(master_hrdata), //input [31:0] master_hrdata
		.master_hreadyout(master_hreadyout), //input master_hreadyout
		.master_hresp(master_hresp), //input master_hresp
		.master_hexresp(master_hexresp), //input master_hexresp
		.master_hruser(master_hruser), //input [2:0] master_hruser
		.reset_n(reset_n) //input reset_n
	);

//--------Copy end-------------------
