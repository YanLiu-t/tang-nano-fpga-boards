module clk_div(
input clk,                  //27Mhz的系统时钟
input rst_n,                //系统的复位信号
input [15:0] lcd_id,        //lcd屏的id
output reg lcd_pclk         //分频后的时钟信号
);
//reg define
//频率为13.5mhz的时钟信号
reg clk_13_5m;


//时钟 2 分频 输出 13.5MHz 时钟
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)
        clk_13_5m <= 1'b0;
    else
        clk_13_5m <= ~clk_13_5m;
end



always @(*) begin
    //判断lcd屏幕的版本
    case(lcd_id)
        16'h4342 : lcd_pclk = clk_13_5m;
        16'h4384 : lcd_pclk = clk;
    //默认不产生时钟频率
    default : lcd_pclk = 1'b0;
    endcase 
end

endmodule