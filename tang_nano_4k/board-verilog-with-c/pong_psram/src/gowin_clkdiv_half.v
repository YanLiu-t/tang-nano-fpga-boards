//============================================================================
// GOWIN CLKDIV /2 - HyperRAM controller clock (memory_clk / 2)
//============================================================================
//
// 63 MHz (PLL CLKOUTD) -> 31.5 MHz
// HyperRAM IP 的 CLK Ratio = 1:2 (控制器 : 存储), 所以控制器时钟必须是
// memory_clk 的一半。CLKDIV 原语输出与输入沿对齐, 适合做同源分频。
//
//============================================================================

module Gowin_CLKDIV_HALF (clkout, hclkin, resetn);

    output clkout;
    input  hclkin;
    input  resetn;

    wire gw_gnd;
    assign gw_gnd = 1'b0;

    CLKDIV clkdiv_inst (
        .CLKOUT(clkout),
        .HCLKIN(hclkin),
        .RESETN(resetn),
        .CALIB (gw_gnd)
    );

    defparam clkdiv_inst.DIV_MODE = "2";
    defparam clkdiv_inst.GSREN    = "false";

endmodule