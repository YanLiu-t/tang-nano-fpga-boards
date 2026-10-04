module rd_id(
input clk , //时钟
input rst_n , //复位，低电平有效
input [23:0] lcd_rgb, //RGB LCD 像素数据,用于读取 ID
output reg [15:0] lcd_id //LCD 屏 ID
);

//reg define
reg rd_flag; //读 ID 标志

//*****************************************************
//** main code
//*****************************************************

//获取 LCD ID M2:B7 M1:G7 M0:R7
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rd_flag <= 1'b0;
        lcd_id <= 16'd0;
    end 
    else begin
        if(rd_flag == 1'b0) begin
            rd_flag <= 1'b1;
            case({lcd_rgb[7],lcd_rgb[15],lcd_rgb[23]})
                3'b000 : lcd_id <= 16'h4342; //4.3' RGB LCD RES:480x272
                3'b001 : lcd_id <= 16'h7084; //7' RGB LCD RES:800x480
                3'b010 : lcd_id <= 16'h7016; //7' RGB LCD RES:1024x600
                3'b100 : lcd_id <= 16'h4384; //4.3' RGB LCD RES:800x480
                3'b101 : lcd_id <= 16'h1018; //10' RGB LCD RES:1280x800
                default : lcd_id <= 16'd0;
            endcase 
        end
    end 
end

endmodule