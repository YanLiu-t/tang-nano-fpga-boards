// rtc_top.v
module rtc_top(
    input  clk,
    input  rst_n,
    inout  i2c_sda,
    output i2c_scl,
    output DIO,
    output SRCLK,
    output RCLK
);

    wire [7:0] second;
    wire ack_ok;
    wire init_done;
    
    ds3231_driver u_ds3231(
        .clk        (clk),
        .rst_n      (rst_n),
        .i2c_sda    (i2c_sda),
        .i2c_scl    (i2c_scl),
        .second     (second),
        .ack_ok     (ack_ok),
        .init_done  (init_done)
    );
    
    reg [7:0] seg_data;
    reg [7:0] sel_data;
    reg [1:0] digit_sel;
    reg [15:0] scan_cnt;
    reg [7:0] disp_second;
    reg [3:0] disp_digit [0:3];
    
    function [7:0] seg7_anode;
        input [3:0] digit;
        begin
            case(digit)
                4'd0: seg7_anode = 8'b1100_0000;
                4'd1: seg7_anode = 8'b1111_1001;
                4'd2: seg7_anode = 8'b1010_0100;
                4'd3: seg7_anode = 8'b1011_0000;
                4'd4: seg7_anode = 8'b1001_1001;
                4'd5: seg7_anode = 8'b1001_0010;
                4'd6: seg7_anode = 8'b1000_0010;
                4'd7: seg7_anode = 8'b1111_1000;
                4'd8: seg7_anode = 8'b1000_0000;
                4'd9: seg7_anode = 8'b1001_0000;
                4'hA: seg7_anode = 8'b1000_1000;
                default: seg7_anode = 8'hFF;
            endcase
        end
    endfunction
    
    function [7:0] bcd_to_dec;
        input [7:0] bcd;
        begin
            bcd_to_dec = ((bcd >> 4) & 8'h0F) * 10 + (bcd & 8'h0F);
        end
    endfunction
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 0;
            digit_sel <= 0;
            disp_second <= 0;
        end
        else begin
            if (init_done && ack_ok) begin
                disp_second <= bcd_to_dec(second);
            end
            
            if (scan_cnt >= 16'd26999) begin
                scan_cnt <= 0;
                digit_sel <= digit_sel + 1;
            end
            else
                scan_cnt <= scan_cnt + 1;
        end
    end
    
    always @(*) begin
        disp_digit[0] = disp_second % 10;
        disp_digit[1] = (disp_second / 10) % 10;
        disp_digit[2] = 4'hA;
        disp_digit[3] = 4'h1;
    end
    
    always @(*) begin
        case(digit_sel)
            2'd0: begin
                seg_data = seg7_anode(disp_digit[0]);
                sel_data = 8'b0000_0001;
            end
            2'd1: begin
                seg_data = seg7_anode(disp_digit[1]);
                sel_data = 8'b0000_0010;
            end
            2'd2: begin
                seg_data = seg7_anode(disp_digit[2]);
                sel_data = 8'b0000_0100;
            end
            2'd3: begin
                seg_data = seg7_anode(disp_digit[3]);
                sel_data = 8'b0000_1000;
            end
            default: begin
                seg_data = 8'hFF;
                sel_data = 8'h00;
            end
        endcase
    end
    
    HC595_Driver u_hc595(
        .Clk     (clk),
        .Reset_n (rst_n),
        .SEG     (seg_data),
        .SEL     (sel_data),
        .DIO     (DIO),
        .SRCLK   (SRCLK),
        .RCLK    (RCLK)
    );

endmodule