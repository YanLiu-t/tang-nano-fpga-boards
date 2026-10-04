module top(
    input Clk,        // 27MHz 系统时钟
    input Reset_n,    // 复位按键
    output DIO,       // 595 数据线
    output SRCLK,     // 595 移位时钟
    output RCLK       // 595 锁存时钟
);

// ================= 1. 参数定义 =================
localparam COUNT_DELAY = 13_500_000;   // 0.5秒加1
localparam SCAN_DIV    = 1349;         // 扫描分频（8状态）

// ================= 2. 变量定义 =================
reg [24:0] count_div;
reg [13:0] counter;
reg [14:0] scan_div;
reg [2:0]  scan_state;

reg [7:0] current_seg;
reg [7:0] current_sel;

// ================= 3. 0.5秒计数器 =================
always @(posedge Clk or negedge Reset_n) begin
    if (!Reset_n) begin
        count_div <= 0;
        counter <= 0;
    end else begin
        if (count_div >= COUNT_DELAY - 1) begin
            count_div <= 0;
            counter <= (counter >= 9999) ? 0 : counter + 1'b1;
        end else begin
            count_div <= count_div + 1'b1;
        end
    end
end

// ================= 4. 提取各位数字 =================
wire [3:0] digit0 = counter % 10;          // 个位 → D位
wire [3:0] digit1 = (counter / 10) % 10;   // 十位 → C位
wire [3:0] digit2 = (counter / 100) % 10;  // 百位 → B位
wire [3:0] digit3 = counter / 1000;        // 千位 → A位

// ================= 5. 段码转换（共阳码）=================
function [7:0] get_seg;
    input [3:0] num;
    case(num)
        4'd0: get_seg = 8'hc0;
        4'd1: get_seg = 8'hf9;
        4'd2: get_seg = 8'ha4;
        4'd3: get_seg = 8'hb0;
        4'd4: get_seg = 8'h99;
        4'd5: get_seg = 8'h92;
        4'd6: get_seg = 8'h82;
        4'd7: get_seg = 8'hf8;
        4'd8: get_seg = 8'h80;
        4'd9: get_seg = 8'h90;
        default: get_seg = 8'hff;
    endcase
endfunction

// ================= 6. 动态扫描（8状态：消隐+显示交替）=================
always @(posedge Clk or negedge Reset_n) begin
    if (!Reset_n) begin
        scan_div <= 0;
        scan_state <= 0;
    end else begin
        if (scan_div >= SCAN_DIV) begin
            scan_div <= 0;
            scan_state <= scan_state + 1'b1;
        end else begin
            scan_div <= scan_div + 1'b1;
        end
    end
end

// ================= 7. 输出（消隐+显示）=================
always @(*) begin
    case(scan_state)
        // 消隐
        3'd0: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        3'd2: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        3'd4: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        3'd6: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        
        // 显示
        3'd1: begin current_seg = get_seg(digit3); current_sel = 8'b0000_1000; end  // A位=千位
        3'd3: begin current_seg = get_seg(digit2); current_sel = 8'b0000_0100; end  // B位=百位
        3'd5: begin current_seg = get_seg(digit1); current_sel = 8'b0000_0010; end  // C位=十位
        3'd7: begin current_seg = get_seg(digit0); current_sel = 8'b0000_0001; end  // D位=个位
        
        default: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
    endcase
end

// ================= 8. 实例化 595 驱动 =================
HC595_Driver #(
    .CLOCK_FREQ(27_000_000),
    .SRCLK_FREQ(1_000_000)
) u_driver (
    .Clk(Clk),
    .Reset_n(Reset_n),
    .SEG(current_seg),
    .SEL(current_sel),
    .DIO(DIO),
    .SRCLK(SRCLK),
    .RCLK(RCLK)
);

endmodule