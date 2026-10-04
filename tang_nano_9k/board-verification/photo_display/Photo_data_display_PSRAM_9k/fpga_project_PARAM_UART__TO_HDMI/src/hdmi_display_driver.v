//顶层模块
module hdmi_display_driver(
input sys_clock,         //系统时钟信号(也是像素频率)
input [23:0]pixel_data,  //外部模块向driver发送的像素信息  
input res_n,             //内部模块的复位信号  
output wire vs_begin,    //场有效数据开始信号
output wire fifo_read_go,//标志临时寄存器开始读数据的信号
input start_hdmi_display,//接收外部模块的开始显示画面的信号
//hdmi的端口
output tmds_clk_p,       //输出到HDMI接口的时钟P分量
output tmds_clk_n,       //输出到HDMI接口的时钟N分量
output [2:0]tmds_data_p, //输出到HDMI接口的RGB三通道串行数据差分P分量
output [2:0]tmds_data_n  //输出到HDMI接口的RGB三通道串行数据差分N分量

);


//像素的使能信号
wire lcd_de; 
//LCD 行同步信号        
wire lcd_hs;
//LCD 场同步信号          
wire lcd_vs;
//LCD RGB888 颜色数据        
wire [23:0] lcd_rgb;

//接收外部模块的开始显示画面的信号(消除帮助亚稳态用的)
reg start_hdmi_display_d0;
reg start_hdmi_display_d1;
//#############################
//***  main code  ************
//#############################


always@(posedge sys_clock , negedge res_n)begin
    if(res_n == 1'b0)begin
        //一级消除亚稳态的信号的复位
        start_hdmi_display_d0 <= 1'b0;
        //二级消除亚稳态的信号的复位
        start_hdmi_display_d1 <= 1'b0;
    end 
    else begin
        //一级消除亚稳态
        start_hdmi_display_d0 <= start_hdmi_display;
        //二级消除亚稳态
        start_hdmi_display_d1 <= start_hdmi_display_d0;
    end
end


//像素显示驱动文件
lcd_driver u_lcd_driver(
.pixel_clock(sys_clock),      //内部像素时钟
.reset_n(res_n),              //内部模块的复位信号
.lcd_id(16'h480),             //lcd型号的信号p720
.pixel_data(pixel_data),      //向driver发送的像素信息
.lcd_de(lcd_de),              //像素的使能信号
.lcd_hs(lcd_hs),              //LCD 行同步信号
.lcd_vs(lcd_vs),              //LCD 场同步信号
.lcd_rgb(lcd_rgb),            //LCD RGB888 颜色数据
.vs_begin(vs_begin),          //场有效数据开始信号
.fifo_read_go(fifo_read_go),  //标志临时寄存器开始读数据的信号
.en_cnt(start_hdmi_display_d1)//消除亚稳态后的hdmi显示开始的信号
);


DVI_TX_Top inst0 (
.I_rst_n      (res_n),           //重置信号
.I_rgb_clk    (sys_clock),       //系统时钟信号
.I_rgb_vs     (lcd_vs),          //场同步信号
.I_rgb_hs     (lcd_hs),          //行同步信号
.I_rgb_de     (lcd_de),          //数据使能信号（Data Enable）
.I_rgb_r      (lcd_rgb[23:16]),  //图像数据中的当前像素R通道8位数据
.I_rgb_g      (lcd_rgb[15:8]),   //图像数据中的当前像素G通道8位数据
.I_rgb_b      (lcd_rgb[7:0]),    //图像数据中的当前像素B通道8位数据
.O_tmds_clk_p (tmds_clk_p),      //输出到HDMI接口的时钟P分量
.O_tmds_clk_n (tmds_clk_n),      //输出到HDMI接口的时钟N分量
.O_tmds_data_p(tmds_data_p),     //输出到HDMI接口的RGB三通道串行数据差分P分量
.O_tmds_data_n(tmds_data_n)      //输出到HDMI接口的RGB三通道串行数据差分N分量
);




endmodule