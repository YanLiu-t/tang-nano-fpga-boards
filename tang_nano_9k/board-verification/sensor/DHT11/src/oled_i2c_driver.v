module oled_i2c_driver(
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire [31:0] show_data,
    input  wire        is_humid,
    
    output wire        i2c_scl,
    inout  wire        i2c_sda
);

    wire [3:0] d_thou, d_hund, d_tens, d_ones;
    bin2bcd u_bin2bcd(
        .bin_in (show_data[15:0]), 
        .thou(d_thou), .hund(d_hund), .tens(d_tens), .ones(d_ones)
    );

    reg        i2c_req;
    reg [15:0] i2c_data; // 包含控制位与数据位
    wire       i2c_done;

    i2c_master u_i2c (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i2c_start(i2c_req), .i2c_data(i2c_data), .i2c_done(i2c_done),
        .i2c_scl(i2c_scl), .i2c_sda(i2c_sda)
    );

    // 迷你 5x8 点阵字库
    function [7:0] get_font;
        input [3:0] char;
        input [2:0] col;
        begin
            case (char)
                4'd0: case(col) 0:get_font=8'h3E; 1:get_font=8'h51; 2:get_font=8'h49; 3:get_font=8'h45; 4:get_font=8'h3E; default:get_font=8'h00; endcase
                4'd1: case(col) 0:get_font=8'h00; 1:get_font=8'h42; 2:get_font=8'h7F; 3:get_font=8'h40; 4:get_font=8'h00; default:get_font=8'h00; endcase
                4'd2: case(col) 0:get_font=8'h42; 1:get_font=8'h61; 2:get_font=8'h51; 3:get_font=8'h49; 4:get_font=8'h46; default:get_font=8'h00; endcase
                4'd3: case(col) 0:get_font=8'h21; 1:get_font=8'h41; 2:get_font=8'h45; 3:get_font=8'h4B; 4:get_font=8'h31; default:get_font=8'h00; endcase
                4'd4: case(col) 0:get_font=8'h18; 1:get_font=8'h14; 2:get_font=8'h12; 3:get_font=8'h7F; 4:get_font=8'h10; default:get_font=8'h00; endcase
                4'd5: case(col) 0:get_font=8'h27; 1:get_font=8'h45; 2:get_font=8'h45; 3:get_font=8'h45; 4:get_font=8'h39; default:get_font=8'h00; endcase
                4'd6: case(col) 0:get_font=8'h3C; 1:get_font=8'h4A; 2:get_font=8'h49; 3:get_font=8'h49; 4:get_font=8'h30; default:get_font=8'h00; endcase
                4'd7: case(col) 0:get_font=8'h01; 1:get_font=8'h71; 2:get_font=8'h09; 3:get_font=8'h05; 4:get_font=8'h03; default:get_font=8'h00; endcase
                4'd8: case(col) 0:get_font=8'h36; 1:get_font=8'h49; 2:get_font=8'h49; 3:get_font=8'h49; 4:get_font=8'h36; default:get_font=8'h00; endcase
                4'd9: case(col) 0:get_font=8'h06; 1:get_font=8'h49; 2:get_font=8'h49; 3:get_font=8'h29; 4:get_font=8'h1E; default:get_font=8'h00; endcase
                4'd10:case(col) 0:get_font=8'h00; 1:get_font=8'h60; 2:get_font=8'h60; 3:get_font=8'h00; 4:get_font=8'h00; default:get_font=8'h00; endcase // 小数点
                default: get_font = 8'h00;
            endcase
        end
    endfunction

    reg [4:0] state;
    reg [7:0] init_cnt;
    reg [2:0] char_idx, col_idx;
    reg [23:0] refresh_timer;

    parameter S_INIT = 0, S_IDLE = 1, S_SET_PAGE = 2, S_SET_COL = 3, S_WRITE_DATA = 4, S_SPACE = 5;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state <= S_INIT; init_cnt <= 0; i2c_req <= 0;
            char_idx <= 0; col_idx <= 0; refresh_timer <= 0;
        end else begin
            case (state)
                S_INIT: begin
                    if (i2c_done) begin
                        i2c_req <= 0; init_cnt <= init_cnt + 1;
                        if (init_cnt == 24) state <= S_IDLE;
                    end else if (!i2c_req) begin
                        i2c_req <= 1;
                        case(init_cnt)
                            0: i2c_data <= {8'h00, 8'hAE}; 1: i2c_data <= {8'h00, 8'h00};
                            2: i2c_data <= {8'h00, 8'h10}; 3: i2c_data <= {8'h00, 8'h40};
                            4: i2c_data <= {8'h00, 8'hB0}; 5: i2c_data <= {8'h00, 8'h81};
                            6: i2c_data <= {8'h00, 8'hFF}; 7: i2c_data <= {8'h00, 8'hA1};
                            8: i2c_data <= {8'h00, 8'hA6}; 9: i2c_data <= {8'h00, 8'hA8};
                            10: i2c_data <= {8'h00, 8'h3F}; 11: i2c_data <= {8'h00, 8'hC8};
                            12: i2c_data <= {8'h00, 8'hD3}; 13: i2c_data <= {8'h00, 8'h00};
                            14: i2c_data <= {8'h00, 8'hD5}; 15: i2c_data <= {8'h00, 8'h80};
                            16: i2c_data <= {8'h00, 8'hD8}; 17: i2c_data <= {8'h00, 8'h05};
                            18: i2c_data <= {8'h00, 8'hD9}; 19: i2c_data <= {8'h00, 8'hF1};
                            20: i2c_data <= {8'h00, 8'hDA}; 21: i2c_data <= {8'h00, 8'h12};
                            22: i2c_data <= {8'h00, 8'hDB}; 23: i2c_data <= {8'h00, 8'h30};
                            24: i2c_data <= {8'h00, 8'hAF}; default: i2c_data <= {8'h00, 8'hE3};
                        endcase
                    end
                end
                
                S_IDLE: begin // 每 0.5 秒刷新一次
                    if (refresh_timer >= 24'd13_500_000) begin
                        refresh_timer <= 0; state <= S_SET_PAGE; char_idx <= 0;
                    end else refresh_timer <= refresh_timer + 1;
                end
                
                S_SET_PAGE: begin
                    if (i2c_done) begin i2c_req <= 0; state <= S_SET_COL; end
                    else if (!i2c_req) begin i2c_req <= 1; i2c_data <= {8'h00, 8'hB0}; end // 定位到第一行
                end
                
                S_SET_COL: begin
                    if (i2c_done) begin i2c_req <= 0; state <= S_WRITE_DATA; col_idx <= 0; end
                    else if (!i2c_req) begin i2c_req <= 1; i2c_data <= {8'h00, 8'h00}; end // 从列开头写起
                end
                
                S_WRITE_DATA: begin // 显示数据: 十位、个位、小数点、小数位
                    if (i2c_done) begin
                        i2c_req <= 0; col_idx <= col_idx + 1;
                        if (col_idx == 4) state <= S_SPACE;
                    end else if (!i2c_req) begin
                        i2c_req <= 1;
                        case(char_idx)
                            0: i2c_data <= {8'h40, get_font(d_thou, col_idx)}; // 十位
                            1: i2c_data <= {8'h40, get_font(d_hund, col_idx)}; // 个位
                            2: i2c_data <= {8'h40, get_font(4'd10, col_idx)};  // 小数点
                            3: i2c_data <= {8'h40, get_font(d_tens, col_idx)}; // 小数位
                            default: i2c_data <= {8'h40, 8'h00};
                        endcase
                    end
                end
                
                S_SPACE: begin
                    if (i2c_done) begin
                        i2c_req <= 0; char_idx <= char_idx + 1; col_idx <= 0;
                        if (char_idx == 3) state <= S_IDLE; else state <= S_WRITE_DATA;
                    end else if (!i2c_req) begin
                        i2c_req <= 1; i2c_data <= {8'h40, 8'h00}; // 字符间距
                    end
                end
            endcase
        end
    end
endmodule