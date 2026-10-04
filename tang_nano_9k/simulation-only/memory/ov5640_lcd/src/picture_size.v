module picture_size (
input        clk ,             //时钟信号
input        rst_n ,           //复位信号
input [15:0] lcd_id ,          //LCD 的器件 ID

output reg [12:0] cmos_h_pixel ,   //摄像头水平分辨率
output reg [12:0] cmos_v_pixel ,   //摄像头垂直分辨率
output reg [12:0] total_h_pixel ,  //水平总像素大小
output reg [12:0] total_v_pixel ,  //垂直总像素大小
output reg [12:0] y_addr_st ,      //开窗垂直方向起始地址
output reg [12:0] y_addr_end ,     //开窗垂直方向截止地址
output reg [27:0] ddr3_max_addr    //ddr3 最大读写地址
);

//*****************************************************
//** main code
//*****************************************************

//配置摄像头输出尺寸的大小
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cmos_h_pixel <= 13'b0;
        cmos_v_pixel <= 13'd0;
        ddr3_max_addr <= 23'd0;
    end
    else begin
        case(lcd_id )
            16'h4342 : begin
                cmos_h_pixel <= 13'd480;
                cmos_v_pixel <= 13'd272;
                ddr3_max_addr <= 23'd130560;
            end
            16'h7084 : begin
                cmos_h_pixel <= 13'd800;
                cmos_v_pixel <= 13'd480;
                ddr3_max_addr <= 23'd384000;
            end
            16'h7016 : begin
                cmos_h_pixel <= 13'd1024;
                cmos_v_pixel <= 13'd600;
                ddr3_max_addr <= 23'd614400;
            end
            16'h1018 : begin
                cmos_h_pixel <= 13'd1280;
                cmos_v_pixel <= 13'd800;
                ddr3_max_addr <= 23'd1024000;
            end
            16'h4384 : begin
                cmos_h_pixel <= 13'd800;
                cmos_v_pixel <= 13'd480;
                ddr3_max_addr <= 23'd384000;
            end
            default : begin
                cmos_h_pixel <= 13'd480;
                cmos_v_pixel <= 13'd272;
                ddr3_max_addr <= 23'd384000;
            end
        endcase
    end
end

//对 HTS 及 VTS 的配置会影响摄像头输出图像的帧率
always @(*) begin
    case(lcd_id)
        16'h4342 : begin
            total_h_pixel = 13'd1800;
            total_v_pixel = 13'd1000;
        end
        16'h7084 : begin
            total_h_pixel = 13'd1800;
            total_v_pixel = 13'd1000;
        end
        16'h7016 : begin
            total_h_pixel = 13'd2200;
            total_v_pixel = 13'd1000;
        end
        16'h1018 : begin
            total_h_pixel = 13'd2570;
            total_v_pixel = 13'd980;
        end
        16'h4384 : begin
            total_h_pixel = 13'd1800;
            total_v_pixel = 13'd1000;
        end
        default : begin
            total_h_pixel = 13'd1800;
            total_v_pixel = 13'd1000;
        end
    endcase
end

//按照 LCD 屏幕的分辨率比例，输出 OV5640 预缩放窗口大小，避免画面拉伸
always @(*) begin
    case(lcd_id)
        16'h4342 : begin
            y_addr_st = 13'd228;
            y_addr_end = 13'd1723;
        end
        16'h7084 : begin
            y_addr_st = 13'd187;
            y_addr_end = 13'd1763;
        end
        16'h7016 : begin
            y_addr_st = 13'd201;
            y_addr_end = 13'd1749;
        end
        16'h1018 : begin
            y_addr_st = 13'd153;
            y_addr_end = 13'd1798;
        end
        16'h4384 : begin
            y_addr_st = 13'd187;
            y_addr_end = 13'd1763;
        end
        default : begin
            y_addr_st = 13'd228;
            y_addr_end = 13'd1723;
        end
    endcase
end

endmodule
