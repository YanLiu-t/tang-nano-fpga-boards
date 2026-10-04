`timescale 1ns/1ns
//--------------------------------------------------------------------------------------
//  CrazyBingo
//  模块功能：模拟OV系列CMOS摄像头DVP接口输出VSYNC、HREF、8bit数据，仅仿真使用，不可综合
//--------------------------------------------------------------------------------------
module Video_Image_Simulate_CMOS
#(
    parameter CMOS_VSYNC_VALID = 1'b1,  //OV5640: VSYNC高电平有效
    parameter IMG_HDISP        = 10'd32, //图像宽度（有效像素）
    parameter IMG_VDISP        = 10'd4   //图像高度（有效行数）
)(
    input               rst_n,
    input               cmos_xclk,      //摄像头输入时钟(xclk)
    output reg          cmos_pclk,      //像素输出时钟
    output reg          cmos_vsync,     //场同步
    output reg          cmos_href,      //行有效
    output reg [7:0]    cmos_data       //8bit输出数据
);

reg [9:0]   h_cnt;
reg [9:0]   v_cnt;

//像素pclk等于xclk直接输出
always @(posedge cmos_xclk or negedge rst_n) begin
    if(!rst_n)
        cmos_pclk <= 1'b0;
    else
        cmos_pclk <= ~cmos_pclk;
end

//行计数器
always @(posedge cmos_pclk or negedge rst_n) begin
    if(!rst_n)
        h_cnt <= 10'd0;
    else begin
        if(h_cnt == IMG_HDISP - 1'b1)
            h_cnt <= 10'd0;
        else
            h_cnt <= h_cnt + 1'b1;
    end
end

//场计数器
always @(posedge cmos_pclk or negedge rst_n) begin
    if(!rst_n)
        v_cnt <= 10'd0;
    else if(h_cnt == IMG_HDISP - 1'b1) begin
        if(v_cnt == IMG_VDISP - 1'b1)
            v_cnt <= 10'd0;
        else
            v_cnt <= v_cnt + 1'b1;
    end
end

//vsync场同步
always @(*) begin
    if(!rst_n)
        cmos_vsync = ~CMOS_VSYNC_VALID;
    else begin
        if(v_cnt == 10'd0)
            cmos_vsync = CMOS_VSYNC_VALID;
        else
            cmos_vsync = ~CMOS_VSYNC_VALID;
    end
end

//href行有效
always @(*) begin
    if(!rst_n)
        cmos_href = 1'b0;
    else begin
        if((v_cnt > 0) && (h_cnt < IMG_HDISP))
            cmos_href = 1'b1;
        else
            cmos_href = 1'b0;
    end
end

//模拟像素数据，递增0~255
always @(posedge cmos_pclk or negedge rst_n) begin
    if(!rst_n)
        cmos_data <= 8'd0;
    else if(cmos_href)
        cmos_data <= cmos_data + 1'b1;
    else
        cmos_data <= 8'd0;
end

endmodule
