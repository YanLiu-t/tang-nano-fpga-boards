module oled_ctrl(

input  wire clk,
input  wire rst_n,


input  wire [7:0] temperature,
input  wire [7:0] humidity,

input  wire mode,


output wire scl,
output wire sda

);

wire [7:0] temp_h;
wire [7:0] temp_t;
wire [7:0] temp_o;

wire [7:0] hum_h;
wire [7:0] hum_t;
wire [7:0] hum_o;

reg i2c_start;
reg [7:0] i2c_data;


wire i2c_busy;
wire i2c_done;


reg [7:0] char_index;

reg [7:0] current_char;

reg [3:0] font_row;


wire [7:0] font_data;

num_to_ascii u_temp(

    .num(temperature),

    .hundred(temp_h),
    .ten(temp_t),
    .one(temp_o)

);


num_to_ascii u_hum(

    .num(humidity),

    .hundred(hum_h),
    .ten(hum_t),
    .one(hum_o)

);

oled_font u_font(

    .ascii(current_char),

    .row(font_row),

    .data(font_data)

);

oled_i2c u_i2c(

    .clk(clk),
    .rst_n(rst_n),

    .start(i2c_start),
    .data(i2c_data),

    .busy(i2c_busy),
    .done(i2c_done),

    .scl(scl),
    .sda(sda)

);





reg [3:0] state;


reg [7:0] init_cnt;



parameter

RESET  = 4'd0,
INIT   = 4'd1,
PAGE   = 4'd2,
WRITE  = 4'd3,
WAIT   = 4'd4;



always @(posedge clk or negedge rst_n)
begin


if(!rst_n)

begin

    state<=RESET;

    init_cnt<=0;

    i2c_start<=0;

end


else
begin


i2c_start<=0;



case(state)



RESET:

begin

    init_cnt<=0;

    state<=INIT;

end



//--------------------------------
// SSD1306初始化
//--------------------------------

INIT:

begin


if(!i2c_busy)

begin


case(init_cnt)



0:
begin
    i2c_data<=8'h00; //命令模式
    i2c_start<=1;
end


1:
begin
    i2c_data<=8'hAE; //关闭显示
    i2c_start<=1;
end


2:
begin
    i2c_data<=8'hD5;
    i2c_start<=1;
end


3:
begin
    i2c_data<=8'h80;
    i2c_start<=1;
end


4:
begin
    i2c_data<=8'hA8;
    i2c_start<=1;
end


5:
begin
    i2c_data<=8'h3F;
    i2c_start<=1;
end


6:
begin
    i2c_data<=8'hAF; //开启显示
    i2c_start<=1;
end



default:

begin

    init_cnt<=0;

    state<=PAGE;

end


endcase



init_cnt<=init_cnt+1;



end


end



//--------------------------------
// 设置显示位置
//--------------------------------


PAGE:

begin


if(!i2c_busy)

begin


i2c_data<=8'h00;

i2c_start<=1;


state<=WRITE;



end


end



//--------------------------------
// 后面进入字符发送
//--------------------------------


WRITE:

begin


if(!i2c_busy)

begin


//--------------------------------
// 温度显示
//--------------------------------

if(mode==1'b0)

begin


case(char_index)


0:
current_char="T";


1:
current_char="E";


2:
current_char="M";


3:
current_char="P";


4:
current_char=":";


5:
current_char=temp_t;


6:
current_char=temp_o;


7:
current_char="C";



default:

begin

char_index<=0;

end



endcase


end



//--------------------------------
// 湿度显示
//--------------------------------

else

begin


case(char_index)


0:
current_char="H";


1:
current_char="U";


2:
current_char="M";


3:
current_char="I";


4:
current_char=":";


5:
current_char=hum_t;


6:
current_char=hum_o;


7:
current_char="%";



default:

begin

char_index<=0;

end


endcase


end



//--------------------------------
// 发送点阵
//--------------------------------


i2c_data <= font_data;

i2c_start <= 1;



font_row <= font_row + 1;



if(font_row==7)

begin

    font_row<=0;

    char_index<=char_index+1;

end



end



end



endcase


end


end



endmodule