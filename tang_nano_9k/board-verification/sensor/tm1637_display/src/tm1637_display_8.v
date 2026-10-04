module tm1637_display_8 (
    input  wire clk,
    output reg  tm1637_clk,
    inout  wire tm1637_dio
);

    reg dio_out;
    reg dio_en;
    assign tm1637_dio = dio_en ? dio_out : 1'bz;

    // 50us
    localparam DIV_50US = 11'd1349; 
    reg [10:0] div_cnt;
    reg tick_50us;
    
    always @(posedge clk) begin
        if (div_cnt == DIV_50US) begin
            div_cnt <= 11'd0;
            tick_50us <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
            tick_50us <= 1'b0;
        end
    end

    // 1秒刷新（改成1秒，减少闪烁）
    reg [25:0] refresh_cnt;
    reg need_refresh;
    
    always @(posedge clk) begin
        if (refresh_cnt == 26'd26_999_999) begin
            refresh_cnt <= 26'd0;
            need_refresh <= 1'b1;
        end else begin
            refresh_cnt <= refresh_cnt + 1'b1;
            need_refresh <= 1'b0;
        end
    end

    // 全亮
    wire [7:0] seg_data0 = 8'hFF;
    wire [7:0] seg_data1 = 8'hFF;
    wire [7:0] seg_data2 = 8'hFF;
    wire [7:0] seg_data3 = 8'hFF;

    // 状态机（移位在CLK=1之后）
    reg [5:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg [2:0] byte_idx;
    
    always @(posedge clk) begin
        if (tick_50us) begin
            case (state)
                6'd0: begin
                    tm1637_clk <= 1'b1;
                    dio_en <= 1'b0;
                    if (need_refresh) begin
                        state <= 6'd1;
                        shift_reg <= 8'h40;
                        bit_cnt <= 3'd0;
                        byte_idx <= 3'd0;
                    end
                end

                6'd1: begin
                    tm1637_clk <= 1'b1;
                    dio_en <= 1'b1; 
                    dio_out <= 1'b0; 
                    state <= 6'd2;
                end

                6'd2: begin
                    tm1637_clk <= 1'b0;
                    dio_en <= 1'b1;
                    dio_out <= shift_reg[0];
                    state <= 6'd3;
                end

                6'd3: begin
                    tm1637_clk <= 1'b1;
                    state <= 6'd4;
                end

                6'd4: begin
                    shift_reg <= {1'b0, shift_reg[7:1]};
                    bit_cnt <= bit_cnt + 1'b1;
                    if (bit_cnt < 3'd7)
                        state <= 6'd2;
                    else
                        state <= 6'd5;
                end

                6'd5: begin
                    tm1637_clk <= 1'b0; 
                    dio_en <= 1'b0;
                    state <= 6'd6;
                end

                6'd6: begin
                    tm1637_clk <= 1'b1;
                    
                    if (byte_idx == 3'd0) begin
                        state <= 6'd8;
                        byte_idx <= 3'd1; 
                        shift_reg <= 8'hC0;
                    end 
                    else if (byte_idx >= 3'd1 && byte_idx <= 3'd4) begin
                        case (byte_idx)
                            3'd1: shift_reg <= seg_data0;
                            3'd2: shift_reg <= seg_data1;
                            3'd3: shift_reg <= seg_data2;
                            3'd4: shift_reg <= seg_data3;
                        endcase
                        bit_cnt <= 3'd0;
                        byte_idx <= byte_idx + 1'b1;
                        state <= 6'd2;
                    end
                    else if (byte_idx == 3'd5) begin
                        state <= 6'd8;
                        byte_idx <= 3'd6; 
                        shift_reg <= 8'h8F;
                    end
                    else begin
                        state <= 6'd0;
                    end
                end

                6'd8: begin
                    tm1637_clk <= 1'b1;
                    dio_en <= 1'b1;
                    dio_out <= 1'b0;
                    state <= 6'd9;
                end

                6'd9: begin
                    dio_out <= 1'b1;
                    state <= 6'd10;
                end
                
                6'd10: begin
                    state <= 6'd11; 
                end
                
                6'd11: begin
                    tm1637_clk <= 1'b1;
                    dio_en <= 1'b1;
                    dio_out <= 1'b0;
                    bit_cnt <= 3'd0;
                    state <= 6'd2;
                end

                default: state <= 6'd0;
            endcase
        end
    end

endmodule