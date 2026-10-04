module video_driver(
    input             pixel_clk,  // 像素时钟
    input             sys_rst_n,  // 复位，低电平有效
    
    // RGB 视频接口输出 (对接 HDMI 编码模块)
    output            video_hs,   // 行同步信号
    output            video_vs,   // 场同步信号
    output reg        video_de,   // 数据使能信号
    output     [23:0] video_rgb,  // RGB888 颜色数据
    
    // 对接 Display 显示模块
    output reg        data_req,   // 数据请求信号
    output reg [10:0] pixel_xpos, // 当前像素点横坐标
    output reg [10:0] pixel_ypos, // 当前像素点纵坐标 
    input      [23:0] pixel_data  // 像素数据输入
);

// 固化时序参数：10.1寸 1280*800 (对应 50MHz 基础像素时钟)
parameter H_SYNC  = 11'd10;
parameter H_BACK  = 11'd80;
parameter H_DISP  = 11'd1280;
parameter H_FRONT = 11'd60;
parameter H_TOTAL = 11'd1430;

parameter V_SYNC  = 11'd10;
parameter V_BACK  = 11'd23;
parameter V_DISP  = 11'd800;
parameter V_FRONT = 11'd10;
parameter V_TOTAL = 11'd843;

// 内部计数器
reg [10:0] h_cnt;
reg [10:0] v_cnt;

//*****************************************************
//** main code
//*****************************************************

// 【修改点】：生成真实的行场同步信号，DVI/HDMI 需要依赖此信号锁定画面
assign video_hs = (h_cnt < H_SYNC) ? 1'b1 : 1'b0;
assign video_vs = (v_cnt < V_SYNC) ? 1'b1 : 1'b0;

// RGB888 数据输出 (非有效区域输出黑色)
assign video_rgb = video_de ? pixel_data : 24'd0;

// 像素点 x 坐标
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        pixel_xpos <= 11'd0;
    else if(data_req)
        pixel_xpos <= h_cnt + 2'd2 - H_SYNC - H_BACK;
    else
        pixel_xpos <= 11'd0;
end

// 像素点 y 坐标 
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        pixel_ypos <= 11'd0;
    else if(v_cnt >= (V_SYNC + V_BACK) && v_cnt < (V_SYNC + V_BACK + V_DISP))
        pixel_ypos <= v_cnt + 1'b1 - (V_SYNC + V_BACK);
    else
        pixel_ypos <= 11'd0;
end

// 数据使能信号
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) 
        video_de <= 1'b0;
    else
        video_de <= data_req;
end

// 请求像素点颜色数据输入 (提前量匹配流水线延迟)
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) 
        data_req <= 1'b0;
    else if((h_cnt >= H_SYNC + H_BACK - 2'd2) && (h_cnt < H_SYNC + H_BACK + H_DISP - 2'd2 )
         && (v_cnt >= V_SYNC + V_BACK) && (v_cnt < V_SYNC + V_BACK + V_DISP))
        data_req <= 1'b1;
    else
        data_req <= 1'b0;
end

// 行计数器对像素时钟计数
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        h_cnt <= 11'd0;
    else begin
        if(h_cnt == H_TOTAL - 1'b1)
            h_cnt <= 11'd0;
        else
            h_cnt <= h_cnt + 1'b1; 
    end
end

// 场计数器对行计数
always@ (posedge pixel_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        v_cnt <= 11'd0;
    else begin
        if(h_cnt == H_TOTAL - 1'b1) begin
            if(v_cnt == V_TOTAL - 1'b1)
                v_cnt <= 11'd0;
            else
                v_cnt <= v_cnt + 1'b1; 
        end
    end 
end

endmodule