//============================================================================
// Tang Nano 4K - Pong timing constraints
//============================================================================
//
// Prior to this file the project had ONLY the 27 MHz input clock declared, so
// every derived domain was left unconstrained and the PnR log reported:
//   WARN (TA1132): 'clkdiv_inst/clkdiv_inst_s0/CLKOUT.default_gen_clk' was
//                  determined to be a clock but was not created.
//   WARN (TA1132): 'u_hyper/u_hpram/u_hpram_top/clkdiv/CLKOUT.default_gen_clk'
//                  was determined to be a clock but was not created.
//   WARN (PR1014): Generic routing resource will be used to clock signal 'clk_d'
//                  ... may lead to excessive delay or skew
// i.e. the 25.2 MHz pixel domain and the 31.5 MHz HyperRAM domain had NO
// timing analysis at all. They are declared below.

// 27 MHz crystal on pin 45.
create_clock -name clk_27mhz -period 37.037 -waveform {0 18.518} [get_ports {clk}]

// PLLVR: CLKOUT = 27 * 14/3 = 126 MHz (TMDS serial), CLKOUTD = /2 = 63 MHz
// (HyperRAM memory_clk).
create_generated_clock -name clk_126m -source [get_ports {clk}] -master_clock clk_27mhz -multiply_by 14 -divide_by 3 [get_pins {pll_inst/pllvr_inst/CLKOUT}]
create_generated_clock -name clk_63m -source [get_pins {pll_inst/pllvr_inst/CLKOUT}] -master_clock clk_126m -divide_by 2 [get_pins {pll_inst/pllvr_inst/CLKOUTD}]

// Gowin_CLKDIV /5 -> 25.2 MHz pixel clock (clk_p). 800x525 @ 59.94 Hz.
create_generated_clock -name clk_p_25m2 -source [get_pins {pll_inst/pllvr_inst/CLKOUT}] -master_clock clk_126m -divide_by 5 [get_pins {clkdiv_inst/clkdiv_inst_s0/CLKOUT}]

// HyperRAM IP internal /2 of memory_clk -> 31.5 MHz hp_clkout.
create_generated_clock -name hp_clkout_31m5 -source [get_pins {pll_inst/pllvr_inst/CLKOUTD}] -master_clock clk_63m -divide_by 2 [get_pins {u_hyper/u_hpram/u_hpram_top/clkdiv/CLKOUT}]

// The design crosses between these domains ONLY through 2-flop toggle
// synchronisers (with the toggle sampled 4 cycles after edge detection), so
// declare them asynchronous. This is the same treatment the Gowin HyperRAM
// reference design applies, and it stops the tool from trying to close
// (and failing to close) timing across the CDC while letting it optimise each
// domain on its own.
set_clock_groups -asynchronous -group [get_clocks {clk_27mhz}] -group [get_clocks {clk_126m}] -group [get_clocks {clk_63m}] -group [get_clocks {clk_p_25m2}] -group [get_clocks {hp_clkout_31m5}]