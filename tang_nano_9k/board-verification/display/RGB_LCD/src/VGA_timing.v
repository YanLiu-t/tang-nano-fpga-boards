module VGA_timing(
    input PixelClk,
    input nRST,
    output reg LCD_DE,
    output reg LCD_HSYNC,
    output reg LCD_VSYNC,
    output [4:0] LCD_B,
    output [5:0] LCD_G,
    output [4:0] LCD_R
);

// 480x272 时序参数
parameter H_ACTIVE = 480;
parameter H_FP = 40;    
parameter H_SYNC = 1;
parameter H_BP = 40;
parameter V_ACTIVE = 272;
parameter V_FP = 8;
parameter V_SYNC = 1;
parameter V_BP = 8;

reg [9:0] h_cnt;  
reg [8:0] v_cnt;  

// 三色块颜色输出（组合逻辑）
reg [4:0] r_tmp;
reg [5:0] g_tmp;
reg [4:0] b_tmp;

always @(*) begin
    // 水平方向分成3个区域（每160列一个色块）
    if(h_cnt < 160) begin          // 左区：红色
        r_tmp = 5'b11111;
        g_tmp = 6'b000000;
        b_tmp = 5'b00000;
    end else if(h_cnt < 320) begin // 中区：绿色
        r_tmp = 5'b00000;
        g_tmp = 6'b111111;
        b_tmp = 5'b00000;
    end else begin                 // 右区：蓝色
        r_tmp = 5'b00000;
        g_tmp = 6'b000000;
        b_tmp = 5'b11111;
    end
end

assign LCD_R = r_tmp;
assign LCD_G = g_tmp;
assign LCD_B = b_tmp;

// 行时序
always @(posedge PixelClk or negedge nRST) begin
    if(!nRST) begin
        h_cnt <= 0;
        LCD_HSYNC <= 1;  
    end else begin
        if(h_cnt < H_ACTIVE + H_FP + H_SYNC + H_BP - 1)
            h_cnt <= h_cnt + 1'b1;
        else
            h_cnt <= 0;
            
        if(h_cnt >= H_ACTIVE + H_FP && h_cnt < H_ACTIVE + H_FP + H_SYNC)
            LCD_HSYNC <= 1'b0;
        else
            LCD_HSYNC <= 1'b1;
    end
end

// 场时序
always @(posedge PixelClk or negedge nRST) begin
    if(!nRST) begin
        v_cnt <= 0;
        LCD_VSYNC <= 1;
    end else if(h_cnt == H_ACTIVE + H_FP + H_SYNC + H_BP - 1) begin
        if(v_cnt < V_ACTIVE + V_FP + V_SYNC + V_BP - 1)
            v_cnt <= v_cnt + 1'b1;
        else
            v_cnt <= 0;
            
        if(v_cnt >= V_ACTIVE + V_FP && v_cnt < V_ACTIVE + V_FP + V_SYNC)
            LCD_VSYNC <= 1'b0;
        else
            LCD_VSYNC <= 1'b1;
    end
end

// DE信号
always @(posedge PixelClk) begin
    if(h_cnt < H_ACTIVE && v_cnt < V_ACTIVE)
        LCD_DE <= 1'b1;
    else
        LCD_DE <= 1'b0;
end

endmodule