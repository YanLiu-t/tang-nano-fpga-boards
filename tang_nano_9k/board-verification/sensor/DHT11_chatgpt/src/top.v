module top(

    input  wire sys_clk,       //27MHz
    input  wire rst_n,

    input  wire key0,

    inout  wire dht11,

    output wire oled_scl,
    output wire oled_sda

);


wire [7:0] temperature;
wire [7:0] humidity;

wire dht_valid;


wire key_press;

reg display_mode;


//--------------------------------
// 按键消抖
//--------------------------------

key_filter u_key(

    .clk(sys_clk),
    .rst_n(rst_n),
    .key_in(key0),

    .key_out(key_press)

);



//--------------------------------
// 显示切换
//--------------------------------

always @(posedge sys_clk or negedge rst_n)
begin

    if(!rst_n)

        display_mode <= 1'b0;


    else if(key_press)

        display_mode <= ~display_mode;


end



//--------------------------------
// DHT11
//--------------------------------

dht11_ctrl u_dht11(

    .clk(sys_clk),
    .rst_n(rst_n),

    .dht11(dht11),

    .temperature(temperature),
    .humidity(humidity),

    .valid(dht_valid)

);



//--------------------------------
// OLED
//--------------------------------


oled_ctrl u_oled(

    .clk(sys_clk),
    .rst_n(rst_n),

    .temperature(temperature),
    .humidity(humidity),

    .mode(display_mode),

    .scl(oled_scl),
    .sda(oled_sda)

);



endmodule