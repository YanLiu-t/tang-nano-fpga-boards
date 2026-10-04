module hc595_display(
    input wire clk,
    input wire [11:0] voltage_mv,
    output wire dio,
    output wire srclk,
    output wire rclk
);

// 扫描分频
localparam SCAN_DIV = 1349;

reg [14:0] scan_div;
reg [2:0] scan_state;
reg [7:0] current_seg;
reg [7:0] current_sel;

// 提取各位数字
wire [3:0] digit0 = voltage_mv % 10;           // 个位
wire [3:0] digit1 = (voltage_mv / 10) % 10;    // 十位
wire [3:0] digit2 = (voltage_mv / 100) % 10;   // 百位
wire [3:0] digit3 = voltage_mv / 1000;         // 千位

// 段码转换
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

// 动态扫描（8状态：消隐+显示交替）
always @(posedge clk) begin
    if (scan_div >= SCAN_DIV) begin
        scan_div <= 0;
        scan_state <= scan_state + 1'b1;
    end else begin
        scan_div <= scan_div + 1'b1;
    end
end

// 输出
always @(*) begin
    case(scan_state)
        // 消隐
        3'd0: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        3'd2: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        3'd4: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        3'd6: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
        
        // 显示（千位加小数点）
        3'd1: begin 
            current_seg = get_seg(digit3); 
            current_seg[7] = 1'b0;  // dp亮
            current_sel = 8'b0000_1000; 
        end
        3'd3: begin current_seg = get_seg(digit2); current_sel = 8'b0000_0100; end
        3'd5: begin current_seg = get_seg(digit1); current_sel = 8'b0000_0010; end
        3'd7: begin current_seg = get_seg(digit0); current_sel = 8'b0000_0001; end
        
        default: begin current_seg = 8'hff; current_sel = 8'b0000_0000; end
    endcase
end

// 实例化你验证过的HC595_Driver
HC595_Driver u_driver (
    .Clk(clk),
    .Reset_n(1'b1),
    .SEG(current_seg),
    .SEL(current_sel),
    .DIO(dio),
    .SRCLK(srclk),
    .RCLK(rclk)
);

endmodule