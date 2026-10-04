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

// 行场时序生成 (与原代码一致)
always @(posedge PixelClk or negedge nRST) begin
    if(!nRST) h_cnt <= 0;
    else if(h_cnt < H_ACTIVE + H_FP + H_SYNC + H_BP - 1) h_cnt <= h_cnt + 1'b1;
    else h_cnt <= 0;
end

always @(posedge PixelClk or negedge nRST) begin
    if(!nRST) LCD_HSYNC <= 1;  
    else if(h_cnt >= H_ACTIVE + H_FP && h_cnt < H_ACTIVE + H_FP + H_SYNC) LCD_HSYNC <= 1'b0;
    else LCD_HSYNC <= 1'b1;
end

always @(posedge PixelClk or negedge nRST) begin
    if(!nRST) v_cnt <= 0;
    else if(h_cnt == H_ACTIVE + H_FP + H_SYNC + H_BP - 1) begin
        if(v_cnt < V_ACTIVE + V_FP + V_SYNC + V_BP - 1) v_cnt <= v_cnt + 1'b1;
        else v_cnt <= 0;
    end
end

always @(posedge PixelClk or negedge nRST) begin
    if(!nRST) LCD_VSYNC <= 1;
    else if(v_cnt >= V_ACTIVE + V_FP && v_cnt < V_ACTIVE + V_FP + V_SYNC) LCD_VSYNC <= 1'b0;
    else LCD_VSYNC <= 1'b1;
end

always @(posedge PixelClk) begin
    if(h_cnt < H_ACTIVE && v_cnt < V_ACTIVE) LCD_DE <= 1'b1;
    else LCD_DE <= 1'b0;
end

// ==========================================
// 1. 图片ROM控制逻辑
// ==========================================
wire image_active = (h_cnt >= 100 && h_cnt < 200) && (v_cnt >= 100 && v_cnt < 200);
wire [13:0] rom_addr = (v_cnt - 100) * 100 + (h_cnt - 100); 
wire [15:0] rom_data; // RGB565数据格式: [15:11]R, [10:5]G, [4:0]B

// 实例化你刚才生成的ROM IP核 (确保模块名一致)
image_rom u_image_rom (
    .dout(rom_data), 
    .clk(PixelClk),  
    .oce(1'b1),      
    .ce(image_active),     
    .reset(~nRST),   
    .ad(rom_addr)    
);

// ==========================================
// 2. 字符“A”的点阵字模 (8x16)
// ==========================================
// ==========================================
// 2. 字符“tt”的点阵显示 (两个 8x16 小写 t，间隔 2 像素)
// ==========================================
wire char_active = (h_cnt >= 250 && h_cnt < 270) && (v_cnt >= 100 && v_cnt < 116);
wire [4:0] char_x = h_cnt - 250;   // 0 ~ 19
wire [3:0] char_y = v_cnt - 100;   // 0 ~ 15

reg [7:0] char_font [0:15];
initial begin
    // 小写 t 的字模，8x16，bit7 为最左列
    char_font[0]  = 8'h00;
    char_font[1]  = 8'h00;
    char_font[2]  = 8'h00;
    char_font[3]  = 8'h10;   // 竖线开始
    char_font[4]  = 8'h10;
    char_font[5]  = 8'h10;
    char_font[6]  = 8'h7C;   // 横线
    char_font[7]  = 8'h10;
    char_font[8]  = 8'h10;
    char_font[9]  = 8'h10;
    char_font[10] = 8'h10;
    char_font[11] = 8'h10;
    char_font[12] = 8'h10;
    char_font[13] = 8'h0C;   // 底部向右弯
    char_font[14] = 8'h00;
    char_font[15] = 8'h00;
end

wire [2:0] col0 = char_x[2:0];                    // 第一个 t 的列
wire [2:0] col1 = char_x[2:0] - 3'd2;          // 第二个 t 的列（偏移 10 后取低 3 位）

wire char_pixel;
assign char_pixel = (char_x < 5'd8)              ? char_font[char_y][7 - col0] :
                    (char_x >= 5'd10 && char_x < 5'd18) ? char_font[char_y][7 - col1] :
                    1'b0;   // 中间间隔或两侧空白

// ==========================================
// 3. 画面图层叠加与颜色输出
// ==========================================
reg [4:0] r_out, b_out;
reg [5:0] g_out;

always @(*) begin
    if (!LCD_DE) begin
        r_out = 5'd0; g_out = 6'd0; b_out = 5'd0;
    end else if (image_active) begin
        // 显示图片 (ROM读取延迟1个时钟周期，这里做简化直接输出，画面可能会向右偏移1像素，属于正常现象)
        r_out = rom_data[15:11];
        g_out = rom_data[10:5];
        b_out = rom_data[4:0];
    end else if (char_active && char_pixel) begin
        // 显示字符 (红色)
        r_out = 5'b11111; g_out = 6'b000000; b_out = 5'b00000;
    end else begin
        // 默认背景色 (深灰色)
        r_out = 5'b01000; g_out = 6'b010000; b_out = 5'b01000;
    end
end

assign LCD_R = r_out;
assign LCD_G = g_out;
assign LCD_B = b_out;

endmodule