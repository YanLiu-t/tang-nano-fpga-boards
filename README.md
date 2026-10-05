# Tang Nano FPGA Board Verification Projects

![FPGA](https://img.shields.io/badge/FPGA-Gowin_4K_9K-009688?style=flat-square&logo=fpga) ![Stars](https://img.shields.io/github/stars/tt-520-cmd/tang-nano-fpga-boards?style=flat-square) ![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square) ![Verilog](https://img.shields.io/badge/Verilog-HDL-blue?style=flat-square)

<p align="center">
  <img src="https://wiki.sipeed.com/assets/images/hardware/tang-nano-9k/tang_nano_9k_01.png" width="300" alt="Tang Nano 9K">
  <br>
  <strong>Tang Nano 9K (GW1NR-9)</strong>
  <br><br>
  <img src="https://wiki.sipeed.com/assets/images/hardware/tang-nano-4k/tang_nano_4k_01.png" width="300" alt="Tang Nano 4K">
  <br>
  <strong>Tang Nano 4K (GW1NSR-4C)</strong>
</p>

---

## 📖 What's This / 这是什么

**61 个 Verilog 工程** — Gowin Tang Nano 4K 和 9K 的板级验证项目，全部带 `.cst` 约束文件，可直接综合下载。

61 ready-to-synthesize Verilog projects for Gowin Tang Nano 4K (GW1NSR-4C) and Tang Nano 9K (GW1NR-9). All include constraint files (`.cst`).

---

## 📁 Quick Start / 快速开始

### 1. Install Gowin IDE / 安装高云 IDE

下载地址：https://www.gowinsemi.com.cn/faqsoftware.aspx

推荐版本：**Gowin EDA V1.9.11**（教育版免费）

### 2. Clone & Open / 克隆并打开工程

```bash
git clone https://github.com/tt-520-cmd/tang-nano-fpga-boards.git
```

用 Gowin IDE 打开对应的 `.gprj` 工程文件。

### 3. Synthesize / 综合

在 Gowin IDE 中：
1. 确认 `.cst` 约束文件中的 FPGA 型号与你的板子匹配
2. 点击 **Run → Synthesis**（或按 F9）
3. 等待综合完成

### 4. Place & Route / 布局布线

点击 **Run → Place & Route**（或按 F10）

### 5. Download to Board / 下载到板子

1. 用 USB-C 数据线连接开发板到电脑
2. 打开 **Gowin Programmer**
3. 点击 **Detect** 自动识别设备
4. 选择 **Download Mode: Direct Download**（调试用）或 **Download to Flash**（永久存储）
5. 选择综合生成的 `.fs` 文件
6. 点击 **Download**

---

## 🛠️ Environment / 环境要求

| Item | Detail |
|---|---|
| **FPGA Board** | Tang Nano 4K (GW1NSR-4C) / Tang Nano 9K (GW1NR-9) |
| **IDE** | Gowin EDA V1.9.11 |
| **Language** | Verilog HDL |
| **Download Tool** | Gowin Programmer |
| **Cortex-M3 Softcore** | GMD IDE（仅 Category 2 项目需要） |

---

## 📂 Directory Structure / 目录结构

```
tang-nano-fpga-boards/
├── tang_nano_4k/
│   ├── board-verilog-only/          # Pure Verilog, no C firmware needed
│   │   ├── tang_nano_4k_pong/           # Pong game (pure Verilog)
│   │   └── tang_nano_4k_uart_hdmi/      # UART RX + HDMI display
│   └── board-verilog-with-c/        # Verilog + Cortex-M3 C firmware
│       ├── pong_psram/                   # Pong + HyperRAM + HDMI
│       ├── space_invaders/               # Space Invaders game
│       └── uart_test/                    # UART experiment
│
├── tang_nano_9k/
│   ├── board-verification/          # With .cst files, ready for hardware
│   │   ├── led/                          # LED (11 projects)
│   │   ├── sensor/                       # Sensors (6 projects)
│   │   ├── display/                      # Display & comm (11 projects)
│   │   ├── communication/                # UART (2 projects)
│   │   ├── game/                         # Pong game
│   │   └── photo_display/                # UART + PSRAM + LCD/HDMI
│   └── simulation-only/             # ⚠️ Simulation only, no .cst, cannot download
│       ├── logic_gates/                  # Divider, counter, edge detect
│       ├── ip_cores/                     # PLL, FIFO, RAM, ROM IP
│       ├── communication/                # Ethernet ARP/ICMP/UDP, MDIO
│       ├── memory/                       # SD card, DDR3, OV5640
│       ├── adc/                          # ADC128S102
│       └── dds/                          # DDS signal generator
│
├── .gitignore
├── README.md
└── LICENSE
```

---

## 📋 Project Index / 工程索引

### 🟦 Tang Nano 4K — board-verilog-only（纯 Verilog，无需 C 固件）

| Project | Description |
|---|---|
| `tang_nano_4k_pong` | Pong 乒乓球游戏 |
| `tang_nano_4k_uart_hdmi` | UART 串口接收 + HDMI 显示 |

### 🟦 Tang Nano 4K — board-verilog-with-c（Verilog + C 固件）

| Project | Description | C Firmware |
|---|---|---|
| `pong_psram` | Pong + HyperRAM + HDMI | `firmware/` |
| `space_invaders` | 太空入侵者游戏 | `firmware/` |
| `uart_test` | UART 收发实验 | `firmware/` |

### 🟩 Tang Nano 9K — board-verification（37 个，可上板验证）

| Category | Projects |
|---|---|
| **LED** | flow_led, key_led, led_run, breath_led, led_ctrl, led_twinkle, mux2, decoder_3_8, key_filter, key_debounce, fpga_project_hello |
| **Sensor** | DHT11, DHT11_chatgpt, ds18b20, tm1637_display, ds3231_RTC, ADC_test |
| **Display** | RGB_LCD, RGB_LCD_display, hdmi_colorbar, hdmi_colorbar_test, hdmi_colorbar_gemini, hdmi_block_move, NEC_Transceiver, Remote_Key_Reader, HC595_Driver, test, hs_ad_da |
| **UART** | uart_byte_tx, uart_byte_rx |
| **Game** | pong_tang_nano_9k |
| **Photo** | Photo_data_display_PSRAM_9k（3 个子工程） |

### ⚠️ Tang Nano 9K — simulation-only（22 个，仅仿真）

> **Only for simulation, no constraint files, cannot download to FPGA board.**

divider_4, hex8, edge_test, PLL, FIFO, RAM_test, ROM_test, gowin_sp, ip_pll, ip_fifo, ip_2port_ram, eth_arp_test, eth_icmp_test, eth_udp_test, MDIO, remote_rcv, IO, sd_rw, ddr3, sd_bmp_hdmi, sd_bmp_lcd, ov5640_lcd, adc128s102, dds

---

## ⚠️ Notes / 注意事项

- **simulation-only 目录** 无 `.cst` 约束文件，只能在 Gowin IDE 里看波形仿真，不能下载到板子
- **Category 2 项目** 的 C 固件在 `firmware/` 子目录，用 GMD IDE 编译后通过 UART 烧进 Cortex-M3 软核
- `.gitignore` 已过滤：Gowin IDE 综合输出 (`impl/`, `sim/`)、C 编译产物 (`.o`, `.bin`, `.elf`)、个人配置 (`*.gprj.user`)、PDF/EXE/ZIP
- 每个工程文件夹内有对应的 `.cst` 约束文件

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.
