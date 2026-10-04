module top_dht11 (
    input  sys_clk ,   // 系统时钟 (27MHz)
    input  sys_rst_n , // 系统复位

    inout  dht11 ,     // DHT11 温湿度传感器单总线
    input  key ,       // 切换按键

    // 替换为你的 OLED 屏幕引脚
    output oled_scl ,  // OLED I2C 时钟线 (接屏幕 SCL)
    inout  oled_sda    // OLED I2C 数据线 (接屏幕 SDA)
);

// wire define
wire [31:0] data_valid;
wire [31:0] display_data ;
wire [5:0]  point ;
wire flag_mux ;
wire key_flag;
wire key_value;
wire sign;
wire en;

// 1. DHT11 驱动模块 (记得修改里面分频代码)
dht11_drive u_dht11_drive (
    .sys_clk    (sys_clk),
    .rst_n      (sys_rst_n),
    .dht11      (dht11),
    .data_valid (data_valid)
);

// 2. 按键消抖模块 (代码无需修改，540_000 完美适配 27MHz)
key_debounce u_key_debounce(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .key        (key),
    .key_flag   (key_flag),
    .key_value  (key_value)
);

// 3. 数据处理模块 (按键切换温湿度)
dht11_key u_dht11_key(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .key_flag   (key_flag),
    .key_value  (key_value),
    .data_valid (data_valid),
    .data       (display_data), 
    .sign       (sign),
    .en         (en),
    .flag_mux   (flag_mux), 
    .point      (point)
);

// 4. 全新的 I2C OLED 显示模块 (你需要编写或引用的新模块)
// 该模块负责将 display_data 转换为 ASCII 码，通过 I2C 协议发送给 SSD1306
oled_i2c_driver u_oled_display (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    
    // 要显示的数据
    .show_data  (display_data), // 来自 dht11_key 模块的温湿度数值
    .is_humid   (flag_mux),     // 0:显示温度(C), 1:显示湿度(%)
    
    // 物理 I2C 引脚
    .i2c_scl    (oled_scl),
    .i2c_sda    (oled_sda)
);

endmodule