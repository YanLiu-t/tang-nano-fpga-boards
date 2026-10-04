module rtc_top(
    input wire clk,
    input wire reset_n,
    input wire display_btn,    // S1按键
    inout wire i2c_sda,
    output wire i2c_scl,
    output wire dio,
    output wire srclk,
    output wire rclk
);

wire [7:0] sec_bcd;
wire [7:0] min_bcd;
wire [7:0] hour_bcd;

reg [7:0] seg_data;
reg [7:0] sel_data;

h_ds3231_driver ds3231_inst(
    .clk(clk),
    .rst_n(reset_n),
    .i2c_sda(i2c_sda),
    .i2c_scl(i2c_scl),
    .sec_bcd(sec_bcd),
    .min_bcd(min_bcd),
    .hour_bcd(hour_bcd)
);

function [7:0] seg_code;
    input [3:0] digit;
    begin
        case(digit)
            4'd0: seg_code = 8'hC0;
            4'd1: seg_code = 8'hF9;
            4'd2: seg_code = 8'hA4;
            4'd3: seg_code = 8'hB0;
            4'd4: seg_code = 8'h99;
            4'd5: seg_code = 8'h92;
            4'd6: seg_code = 8'h82;
            4'd7: seg_code = 8'hF8;
            4'd8: seg_code = 8'h80;
            4'd9: seg_code = 8'h90;
            default: seg_code = 8'hFF;
        endcase
    end
endfunction

reg [15:0] refresh_counter;
reg [1:0] current_digit;
reg blank;

always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        refresh_counter <= 0;
        current_digit <= 0;
        blank <= 0;
    end else begin
        refresh_counter <= refresh_counter + 1;
        if(refresh_counter >= 27000) begin
            refresh_counter <= 0;
            blank <= 1;
            current_digit <= current_digit + 1;
        end else if(refresh_counter >= 2700) begin
            blank <= 0;
        end
    end
end

always @(*) begin
    if(blank) begin
        seg_data = 8'hFF;
        sel_data = 8'h00;
    end else begin
        if(!display_btn) begin
            // S1按下：显示分:秒
            case(current_digit)
                2'd0: begin
                    seg_data = seg_code(sec_bcd[3:0]);
                    sel_data = 8'b0000_0001;
                end
                2'd1: begin
                    seg_data = seg_code(sec_bcd[7:4]);
                    sel_data = 8'b0000_0010;
                end
                2'd2: begin
                    seg_data = seg_code(min_bcd[3:0]);
                    sel_data = 8'b0000_0100;
                end
                2'd3: begin
                    seg_data = seg_code(min_bcd[7:4]);
                    sel_data = 8'b0000_1000;
                end
                default: begin
                    seg_data = 8'hFF;
                    sel_data = 8'h00;
                end
            endcase
        end else begin
            // S1松开：显示时:分
            case(current_digit)
                2'd0: begin
                    seg_data = seg_code(min_bcd[3:0]);
                    sel_data = 8'b0000_0001;
                end
                2'd1: begin
                    seg_data = seg_code(min_bcd[7:4]);
                    sel_data = 8'b0000_0010;
                end
                2'd2: begin
                    seg_data = seg_code(hour_bcd[3:0]) & 8'h7F;
                    sel_data = 8'b0000_0100;
                end
                2'd3: begin
                    seg_data = seg_code(hour_bcd[7:4]);
                    sel_data = 8'b0000_1000;
                end
                default: begin
                    seg_data = 8'hFF;
                    sel_data = 8'h00;
                end
            endcase
        end
    end
end

HC595_Driver hc595_inst(
    .Clk(clk),
    .Reset_n(reset_n),
    .SEG(seg_data),
    .SEL(sel_data),
    .DIO(dio),
    .SRCLK(srclk),
    .RCLK(rclk)
);

endmodule