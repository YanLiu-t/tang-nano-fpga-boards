module display_ctrl(
    input clk,
    input rst_n,
    input [7:0] key_val,   // 从解码模块传来的键值
    output reg [7:0] SEG,  // 段码 (接HC595)
    output reg [7:0] SEL   // 位码 (接HC595)
);

    // 动态扫描分频器 (约 1kHz 扫描频率防闪烁)
    reg [14:0] scan_cnt;
    always @(posedge clk) scan_cnt <= scan_cnt + 1;
    wire scan_tick = (scan_cnt == 0);
    
    reg scan_sel; // 0或1，切换两个数码管

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) scan_sel <= 0;
        else if (scan_tick) scan_sel <= ~scan_sel;
    end

    // 当前需要显示的 4bit 十六进制数
    reg [3:0] current_hex;
    always @(*) begin
        if (scan_sel == 0) begin
            SEL = 8'b1111_1110;       // 点亮最右边第1个数码管
            current_hex = key_val[7:4]; // 显示高 4 位
        end else begin
            SEL = 8'b1111_1101;       // 点亮右边第2个数码管
            current_hex = key_val[3:0]; // 显示低 4 位
        end
    end

    // 16进制转 共阳极 7段数码管段码
    always @(*) begin
        case(current_hex)
            4'h0: SEG = 8'hc0;
            4'h1: SEG = 8'hf9;
            4'h2: SEG = 8'ha4;
            4'h3: SEG = 8'hb0;
            4'h4: SEG = 8'h99;
            4'h5: SEG = 8'h92;
            4'h6: SEG = 8'h82;
            4'h7: SEG = 8'hf8;
            4'h8: SEG = 8'h80;
            4'h9: SEG = 8'h90;
            4'ha: SEG = 8'h88;
            4'hb: SEG = 8'h83;
            4'hc: SEG = 8'hc6;
            4'hd: SEG = 8'ha1;
            4'he: SEG = 8'h86;
            4'hf: SEG = 8'h8e;
            default: SEG = 8'hff;
        endcase
    end
endmodule