//============================================================================
// Tang Nano 4K - UART -> HyperRAM -> HDMI timing constraints
//============================================================================
//
// 时钟树:
//   clk (27MHz 板载晶振)
//     └─ Gowin_PLLVR
//          ├─ CLKOUT  = 126 MHz (clk_p5)  -> TMDS 串行
//          └─ CLKOUTD =  63 MHz (clk_d63) -> HyperRAM memory_clk
//               └─ IP 内部 /2 -> hp_clkout = 31.5 MHz (全部 HyperRAM 用户逻辑)
//     126 MHz -- Gowin_CLKDIV(/5) --> clk_p = 25.2 MHz (像素域)
//
// 说明: Gowin 在 PnR 阶段已经从网表自动推导出 PLL/CLKDIV/IP 的全部生成时钟
// (Clock Summary 里的 *.default_gen_clk, 周期/主从关系都正确), 所以本文件
// **不再重复 create_generated_clock** —— 重复声明会被拒绝 (TA2003)。
//
// 这里只做一件事: 声明跨时钟域分组。
//   A 组 (同步, 同源 PLL, 必须互查时序):
//       clk_27mhz / CLKOUT(126M) / CLKOUTP(126M) / clk_p(25.2M)
//       —— 其中 clk_p -> clk_p5 是 svo_enc 到 svo_tmds 串行器的真实路径,
//          绝不能分组隔离。
//   B 组 (HyperRAM 侧):
//       CLKOUTD(63M) / hp_clkout(31.5M)
//   A 与 B 之间只有双时钟 FIFO (hp_clkout 写 / clk_p 读) 与 2 级同步器
//   (UART 27MHz -> wd_s0/wd_s1 于 hp_clkout)。这些跨域路径若按单周期分析
//   会产生大量虚假违例 (实测 u_upload/out_data_* -> wd_s0_* slack -2.272,
//   另有 431 个 setup 违例端点), 既误导排查也占掉 PnR 的优化预算。
//============================================================================

// 27 MHz 板载晶振 (base clock)
create_clock -name clk_27mhz -period 37.037 -waveform {0 18.518} [get_ports {clk}]

// PLL: 27 * 14/3 = 126 MHz ; 27 * 7/3 = 63 MHz (wrapper 内是 pllvr_inst 原语)
create_generated_clock -name clk_p5 -source [get_ports {clk}] -master_clock clk_27mhz -multiply_by 14 -divide_by 3 [get_pins {pll_inst/pllvr_inst/CLKOUT}]
create_generated_clock -name clk_d63 -source [get_ports {clk}] -master_clock clk_27mhz -multiply_by 7 -divide_by 3 [get_pins {pll_inst/pllvr_inst/CLKOUTD}]

// 126 / 5 = 25.2 MHz 像素时钟
create_generated_clock -name clk_p -source [get_pins {pll_inst/pllvr_inst/CLKOUT}] -master_clock clk_p5 -divide_by 5 [get_pins {clkdiv_inst/clkdiv_inst_s0/CLKOUT}]

// 63 / 2 = 31.5 MHz HyperRAM 用户时钟 (IP 内部 div 输出)
create_generated_clock -name hp_clkout -source [get_pins {pll_inst/pllvr_inst/CLKOUTD}] -master_clock clk_d63 -divide_by 2 [get_pins {u_hyper/u_hpram/u_hpram_top/clkdiv/CLKOUT}]

// A 组 (像素/TMDS/晶振, 同步)  <->  B 组 (memory_clk)  <->  C 组 (hp_clkout)
// 与官方参考设计 hpram.sdc 一致: memory_clk 与 clk_x1(hp_clkout) 分属独立异步组
set_clock_groups -asynchronous -group [get_clocks {clk_27mhz clk_p5 clk_p}] -group [get_clocks {clk_d63}] -group [get_clocks {hp_clkout}]