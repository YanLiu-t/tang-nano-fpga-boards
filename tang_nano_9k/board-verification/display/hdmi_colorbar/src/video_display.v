module video_display(
    input             pixel_clk,   // 像素时钟 (原 lcd_pclk)
    input             sys_rst_n,   // 复位，低电平有效 (原 rst_n)
    input      [10:0] pixel_xpos,  // 当前像素点横坐标
    input      [10:0] pixel_ypos,  // 当前像素点纵坐标 
    output reg [23:0] pixel_data   // 像素数据
);

// parameter define 
parameter H_DISP = 11'd1280;       // 水平分辨率 (需与 driver 模块一致)
parameter V_DISP = 11'd800;        // 垂直分辨率

parameter WHITE = 24'hFFFFFF;
parameter BLACK = 24'h000000;
parameter RED   = 24'hFF0000;
parameter GREEN = 24'h00FF00;
parameter BLUE  = 24'h0000FF;

//*****************************************************
//** main code
//*****************************************************

//根据当前像素点坐标指定当前像素点颜色数据，在屏幕上显示横向彩条
always @(posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        pixel_data <= BLACK;
    else begin
        if((pixel_xpos >= 11'd0) && (pixel_xpos < H_DISP/5*1))
            pixel_data <= WHITE;
        else if((pixel_xpos >= H_DISP/5*1) && (pixel_xpos < H_DISP/5*2)) 
            pixel_data <= BLACK;
        else if((pixel_xpos >= H_DISP/5*2) && (pixel_xpos < H_DISP/5*3)) 
            pixel_data <= RED; 
        else if((pixel_xpos >= H_DISP/5*3) && (pixel_xpos < H_DISP/5*4)) 
            pixel_data <= GREEN; 
        else
            pixel_data <= BLUE; 
    end 
end

endmodule