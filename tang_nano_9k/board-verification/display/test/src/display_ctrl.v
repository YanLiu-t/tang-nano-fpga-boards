//核心思想：动态扫描，分时显示

//1. 扫描原理
  // · 两个数码管轮流点亮
   // 利用视觉暂留，看起来像同时显示
//2. 实现方式
  // · 计数器产生约824Hz扫描频率
   // scan_sel在0/1间切换
   //· 0时显示高4位，1时显示低4位
//3. 译码显示
   //· 4位十六进制数查表转8位段码
   //· 共阳极编码：0点亮，1熄灭
module display_ctrl(
    input clk,               // 系统时钟输入（27MHz）
    input rst_n,             // 复位信号输入（低电平有效）
    input [7:0] key_val,     // 从红外解码模块传来的 8 位键值
    output reg [7:0] SEG,    // 数码管段码输出（接 HC595）
    output reg [7:0] SEL     // 数码管位码输出（接 HC595）
);

    // 动态扫描分频计数器（约 1kHz 扫描频率防止闪烁）
    reg [14:0] scan_cnt;                          // 15 位扫描计数器
    always @(posedge clk) scan_cnt <= scan_cnt + 1;  // 每个时钟上升沿计数器加 1
    wire scan_tick = (scan_cnt == 0);             // 计数器溢出时产生扫描切换脉冲
    
    reg scan_sel; // 扫描选择寄存器：0 或 1，用于切换两个数码管

    always @(posedge clk or negedge rst_n) begin  // 时序逻辑：时钟上升沿或复位下降沿触发
        if(!rst_n) scan_sel <= 0;                 // 复位时扫描选择清零
        else if (scan_tick) scan_sel <= ~scan_sel; // 扫描脉冲到来时切换数码管
    end

    // 当前需要显示的 4bit 十六进制数
    reg [3:0] current_hex;                        // 当前要显示的十六进制数（4 位）
    always @(*) begin                             // 组合逻辑：根据扫描选择输出位码和选择数据
        if (scan_sel == 0) begin                  // 如果扫描选择为 0
            SEL = 8'b1111_1110;                   // 位码：点亮最右边第 1 个数码管（低电平有效）
            current_hex = key_val[7:4];           // 取键值高 4 位作为显示数据
        end else begin                            // 如果扫描选择为 1
            SEL = 8'b1111_1101;                   // 位码：点亮右边第 2 个数码管（低电平有效）
            current_hex = key_val[3:0];           // 取键值低 4 位作为显示数据
        end
    end

    // 16进制转共阳极 7 段数码管段码译码
    always @(*) begin                             // 组合逻辑：根据十六进制数输出段码
        case(current_hex)                         // 根据当前十六进制值选择段码
            4'h0: SEG = 8'hc0;                    // 显示字符 "0"：共阳极编码
            4'h1: SEG = 8'hf9;                    // 显示字符 "1"：共阳极编码
            4'h2: SEG = 8'ha4;                    // 显示字符 "2"：共阳极编码
            4'h3: SEG = 8'hb0;                    // 显示字符 "3"：共阳极编码
            4'h4: SEG = 8'h99;                    // 显示字符 "4"：共阳极编码
            4'h5: SEG = 8'h92;                    // 显示字符 "5"：共阳极编码
            4'h6: SEG = 8'h82;                    // 显示字符 "6"：共阳极编码
            4'h7: SEG = 8'hf8;                    // 显示字符 "7"：共阳极编码
            4'h8: SEG = 8'h80;                    // 显示字符 "8"：共阳极编码
            4'h9: SEG = 8'h90;                    // 显示字符 "9"：共阳极编码
            4'ha: SEG = 8'h88;                    // 显示字符 "A"：共阳极编码
            4'hb: SEG = 8'h83;                    // 显示字符 "b"：共阳极编码
            4'hc: SEG = 8'hc6;                    // 显示字符 "C"：共阳极编码
            4'hd: SEG = 8'ha1;                    // 显示字符 "d"：共阳极编码
            4'he: SEG = 8'h86;                    // 显示字符 "E"：共阳极编码
            4'hf: SEG = 8'h8e;                    // 显示字符 "F"：共阳极编码
            default: SEG = 8'hff;                 // 默认情况：所有段熄灭
        endcase
    end
endmodule