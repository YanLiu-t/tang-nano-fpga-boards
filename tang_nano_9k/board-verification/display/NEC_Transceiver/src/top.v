module top(
    input clk,
    input rst_n,
    input ir_in_1,     // 第一个接收管 OUT (听遥控器)
    input ir_in_2,     // 第二个接收管 OUT (听发射管)
    output ir_tx,      // 三极管基极电阻
    output red_led,
    output green_led
);

    wire [7:0] key_val_1;
    wire key_valid_1;
    wire [7:0] key_val_2;
    wire key_valid_2;

    // 1. 接收管1：解码遥控器信号
    ir_receiver u_rx1(
        .clk(clk),
        .rst_n(rst_n),
        .ir_in(ir_in_1),
        .key_val(key_val_1),
        .key_valid(key_valid_1)
    );

    // 2. 发射管：把接收管1的信号转发出去
    ir_transmitter u_tx(
        .clk(clk),
        .rst_n(rst_n),
        .tx_en(key_valid_1), 
        .cmd(key_val_1),     
        .ir_tx(ir_tx)
    );

    // 3. 接收管2：接收自己发射管发出的信号
    ir_receiver u_rx2(
        .clk(clk),
        .rst_n(rst_n),
        .ir_in(ir_in_2),
        .key_val(key_val_2),
        .key_valid(key_valid_2)
    );

    // 4. LED控制：根据接收管2收到的信号亮灯
    led_controller u_led(
        .clk(clk),
        .rst_n(rst_n),
        .key_val(key_val_2),    
        .key_valid(key_valid_2),
        .red_led(red_led),
        .green_led(green_led)
    );

endmodule