module Display_Scan(
    input wire Clk,
    input wire Reset_n,
    input wire next_digit,        
    input wire [15:0] bcd_data,   
    output wire [7:0] SEG,
    output wire [7:0] SEL
);

    reg [1:0] scan_idx;
    reg [3:0] cur_bcd;
    reg show_dp;
    
    reg [7:0] raw_sel;
    reg [7:0] raw_seg;

    // 同步切换
    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) scan_idx <= 0;
        else if(next_digit) scan_idx <= scan_idx + 1'b1;
    end

    // ========================================================
    // 💡 核心改动：重新映射数码管位置 (从左到右 十位-个位.-小数-C)
    // ========================================================
    always @(*) begin
        show_dp = 1'b0;
        case(scan_idx)
            2'd3: begin raw_sel = 8'b1111_0111; cur_bcd = bcd_data[15:12]; end // 【最左】 十位
            2'd2: begin raw_sel = 8'b1111_1011; cur_bcd = bcd_data[11:8];  show_dp = 1'b1; end // 【次左】 个位 + 小数点
            2'd1: begin raw_sel = 8'b1111_1101; cur_bcd = bcd_data[7:4];   end // 【次右】 小数位
            2'd0: begin raw_sel = 8'b1111_1110; cur_bcd = bcd_data[3:0];   end // 【最右】 字母 C
            default: begin raw_sel = 8'b1111_1111; cur_bcd = 0; end
        endcase
    end

    // 生成基础段码 (1 为亮)
    always @(*) begin
        case(cur_bcd)
            4'h0: raw_seg = 8'h3F; 
            4'h1: raw_seg = 8'h06; 
            4'h2: raw_seg = 8'h5B;
            4'h3: raw_seg = 8'h4F;
            4'h4: raw_seg = 8'h66;
            4'h5: raw_seg = 8'h6D;
            4'h6: raw_seg = 8'h7D;
            4'h7: raw_seg = 8'h07;
            4'h8: raw_seg = 8'h7F;
            4'h9: raw_seg = 8'h6F;
            4'hC: raw_seg = 8'h39; // 'C'
            default: raw_seg = 8'h00;
        endcase
        if(show_dp) raw_seg = raw_seg | 8'h80; // 加入小数点
    end

    // 共阳极驱动 (低电平亮段，高电平选位)
    assign SEG = ~raw_seg;  
    assign SEL = ~raw_sel;  

endmodule