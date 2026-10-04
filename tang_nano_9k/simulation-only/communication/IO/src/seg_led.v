module seg_led(
input clk ,
input rst_n ,
input [4:0] key_value ,
input key_flag ,
output [3:0] sel_t ,
output [7:0] seg_led_t
);

//reg define
reg [3:0] sel ;
reg [7:0] seg_led;

//*****************************************************
//** main code
//*****************************************************

assign sel_t = ~sel ;    //共阴极接法这里取反，如果共阳极这里就不取反
assign seg_led_t = ~seg_led;//共阴极接法这里取反，如果共阳极这里就不取反

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)
        sel <= 4'b1111;
    else if(key_flag)
        sel <= 4'b0000;
    else
        sel <= 4'b1111;
end

always @(posedge clk or negedge rst_n)begin
    if(rst_n==1'b0)
        seg_led <= 8'b1111_1111;
    else if (key_flag)begin
        case (key_value)
        5'd0 : seg_led <= 8'b01000000;
        5'd1 : seg_led <= 8'b01111001;
        5'd2 : seg_led <= 8'b00100100;
        5'd3 : seg_led <= 8'b00110000;
        5'd4 : seg_led <= 8'b00011001;
        5'd5 : seg_led <= 8'b00010010;
        5'd6 : seg_led <= 8'b00000010;
        5'd7 : seg_led <= 8'b01111000;
        5'd8 : seg_led <= 8'b00000000;
        5'd9 : seg_led <= 8'b00010000;
        5'd10: seg_led <= 8'b00011000;
        5'd11: seg_led <= 8'b00000011;
        5'd12: seg_led <= 8'b01000110;
        5'd13: seg_led <= 8'b00100001;
        5'd14: seg_led <= 8'b00000110;
        5'd15: seg_led <= 8'b00001110;
        default:
            seg_led <= 8'b1111_1111;
        endcase
    end
    else
        seg_led <= 8'b1111_1111;
end

endmodule
