# Tang Nano FPGA Board Verification Projects

**This repo contains Verilog board verification projects for Gowin Tang Nano 4K and Tang Nano 9K, with constraint files (.cst), ready for synthesis and download.**

中文版：本仓库包含 Gowin Tang Nano 4K / Tang Nano 9K 的板级 Verilog 验证工程，
含约束文件 (.cst)，可直接综合下载到 FPGA 开发板。

---

## 📁 Directory Structure

```
tang-nano-fpga-boards/
├── tang_nano_4k/
│   ├── board-verilog-only/       # 纯 Verilog，无需 C 固件，可直接上板
│   │   ├── tang_nano_4k_pong/           # Pong 乒乓球游戏（纯 Verilog）
│   │   └── tang_nano_4k_uart_hdmi/      # UART 串口接收 + HDMI 显示
│   └── board-verilog-with-c/     # Verilog + Cortex-M3 C 固件，软硬协同
│       ├── pong_psram/                  # Pong + PSRAM + HDMI（含 C 固件 firmware/）
│       ├── space_invaders/              # 太空入侵者游戏（含 C 固件 firmware/）
│       └── uart_test/                   # UART 实验（含 C 固件 firmware/）
│
├── tang_nano_9k/
│   ├── board-verification/       # 有 .cst 约束文件，可上板验证
│   │   ├── led/                         # LED 流水灯/呼吸灯/按键/译码器等 (11个)
│   │   ├── sensor/                      # DHT11/DS18B20/DS3231/ADC 等 (6个)
│   │   ├── display/                     # RGB LCD/HDMI/红外/HC595 等 (11个)
│   │   ├── communication/                # UART 收发 (2个)
│   │   ├── game/                        # Pong 乒乓球游戏
│   │   └── photo_display/               # UART + PSRAM + LCD/HDMI 三个子工程
│   └── simulation-only/           # Only for simulation, no constraint files, cannot download to FPGA board.
│       ├── logic_gates/                 # 分频器/数码管/边沿检测等
│       ├── ip_cores/                    # PLL/FIFO/RAM/ROM IP 实验
│       ├── communication/               # 以太网 ARP/ICMP/UDP, MDIO, 矩阵键盘
│       ├── memory/                      # SD 卡, DDR3, DVI/OV5640
│       ├── adc/                         # ADC128S102
│       └── dds/                         # DDS 信号发生器
│
├── .gitignore
├── README.md
└── LICENSE
```

## 🛠️ Environment

| Item | Detail |
|---|---|
| **FPGA Board** | Tang Nano 4K (GW1N-4C) / Tang Nano 9K (GW1N-9C) |
| **IDE** | Gowin EDA |
| **Language** | Verilog HDL |
| **Download Tool** | Gowin Programmer |
| **Category 2 (Verilog + C)** | GMD IDE (Cortex-M3 软核 C 固件开发) |

## ⚠️ Notes

- **simulation-only 目录**标注了 `Only for simulation, no constraint files, cannot download to FPGA board.`
- C 固件中 `.o` / `.d` / `.bin` / `.elf` / `.hex` / `.map` / `Debug/` 编译产物已被 `.gitignore` 过滤
- Gowin IDE 综合/布局布线中间文件 (`impl/`, `sim/` 等) 同样被 `.gitignore` 过滤
- `* (1).*` 重名备份文件自动过滤（Gowin IDE 经常生成这种重复文件）

## 📂 Project List

### Tang Nano 4K · board-verilog-only (2)

| Project | Description |
|---|---|
| `tang_nano_4k_pong` | Pong 乒乓球游戏，纯 Verilog，4K 板直接运行 |
| `tang_nano_4k_uart_hdmi` | UART 串口接收数据 + HDMI 显示 |

### Tang Nano 4K · board-verilog-with-c (3) ⚠️ 需要 C 固件配合

| Project | Description |
|---|---|
| `pong_psram` | Pong 游戏 + HyperRAM + HDMI，C 固件在 `firmware/` 子目录 |
| `space_invaders` | 太空入侵者游戏，Verilog 显示 + C 固件游戏逻辑 |
| `uart_test` | UART 收发实验，C 固件在 `firmware/` 子目录 |

### Tang Nano 9K · board-verification (37)

#### led/ — LED 基础实验 (11)

| Project | Description |
|---|---|
| `flow_led` | 8 位 LED 流水灯 |
| `key_led` | 按键控制 LED |
| `led_run` | 跑马灯 + 3-8 译码器 |
| `breath_led` | PWM 呼吸灯 |
| `led_ctrl` | LED 闪烁控制器 |
| `led_twinkle` | LED 闪烁 |
| `mux2` | 二选一数据选择器 |
| `decoder_3_8` | 3-8 译码器 |
| `key_filter` | 按键滤波消抖 |
| `key_debounce` | 按键消抖 + 蜂鸣器 |
| `fpga_project_hello` | 点灯入门工程 |

#### sensor/ — 传感器 (6)

| Project | Description |
|---|---|
| `DHT11` | DHT11 温湿度 + OLED 显示 |
| `DHT11_chatgpt` | DHT11 另一实现版本 |
| `ds18b20` | DS18B20 温度传感器 + 数码管 |
| `tm1637_display` | TM1637 数码管 + DS3231 RTC |
| `ds3231_RTC` | DS3231 实时时钟驱动 |
| `ADC_test` | ADC 采样 + HC595 数码管显示 |

#### display/ — 显示 + 通信外设 (11)

| Project | Description |
|---|---|
| `RGB_LCD` | RGB LCD + VGA 时序 |
| `RGB_LCD_display` | RGB LCD 显示 |
| `hdmi_colorbar` | HDMI 彩条发生器 |
| `hdmi_colorbar_test` | HDMI 测试信号 |
| `hdmi_colorbar_gemini` | Gemini 版 HDMI |
| `hdmi_block_move` | HDMI 方块移动动画 |
| `NEC_Transceiver` | NEC 红外收发 |
| `Remote_Key_Reader` | 红外遥控解码 |
| `HC595_Driver` | 74HC595 移位寄存器驱动 |
| `test` | HC595 + 红外 + 数码管综合实验 |
| `hs_ad_da` | 高速 AD/DA 采集回放 |

#### communication/ — UART (2)

| Project | Description |
|---|---|
| `uart_byte_tx` | UART 串口发送 |
| `uart_byte_rx` | UART 串口接收 |

#### game/ — 游戏 (1)

| Project | Description |
|---|---|
| `pong_tang_nano_9k` | Pong 乒乓球游戏（9K 板版） |

#### photo_display/ — 图像显示 (1)

| Project | Description |
|---|---|
| `Photo_data_display_PSRAM_9k` | 三个子工程：UART+PSRAM+LCD, UART+PSRAM+RGB, UART+PARAM+HDMI |

### Tang Nano 9K · simulation-only (22)

> ⚠️ **Only for simulation, no constraint files, cannot download to FPGA board.**

| Project | Description |
|---|---|
| `divider_4` | 4 分频器 |
| `hex8` | 8 位数码管扫描 |
| `edge_test` | 边沿检测 |
| `PLL` | PLL 锁相环实验 |
| `FIFO` | 异步 FIFO 设计 |
| `RAM_test` | BRAM IP 读写测试 |
| `ROM_test` | ROM IP 读取测试 |
| `gowin_sp` | 单端口 RAM IP |
| `ip_pll` | PLL IP |
| `ip_fifo` | FIFO IP |
| `ip_2port_ram` | 双端口 RAM IP |
| `eth_arp_test` | 以太网 ARP 协议 |
| `eth_icmp_test` | 以太网 ICMP Ping |
| `eth_udp_test` | 以太网 UDP |
| `MDIO` | MDIO 总线读写 |
| `remote_rcv` | 红外接收 |
| `IO` | 矩阵键盘 + 数码管 + 拨码开关 |
| `sd_rw` | SD 卡 SPI 读写 |
| `ddr3` | DDR3 控制器 |
| `sd_bmp_hdmi` | SD 卡 BMP + HDMI |
| `sd_bmp_lcd` | SD 卡 BMP + LCD |
| `ov5640_lcd` | OV5640 摄像头 + DDR3 + LCD |
| `adc128s102` | ADC128S102 八通道 ADC |
| `dds` | DDS 信号发生器 |

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.
