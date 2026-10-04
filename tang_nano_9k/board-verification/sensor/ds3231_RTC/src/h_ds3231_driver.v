module h_ds3231_driver (
    input        clk,
    input        rst_n,
    inout        i2c_sda,
    output reg   i2c_scl,
    output reg [7:0] sec_bcd,
    output reg [7:0] min_bcd,
    output reg [7:0] hour_bcd
);

    localparam DS3231_ADDR = 7'h68;  
    
    // I2C 节拍生成 (20kHz)
    reg [8:0] div_cnt;
    reg [1:0] scl_cnt; 
    
    wire tick = (div_cnt == 337);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 0;
            scl_cnt <= 0;
        end else if (tick) begin
            div_cnt <= 0;
            scl_cnt <= scl_cnt + 1;
        end else begin
            div_cnt <= div_cnt + 1;
        end
    end

    // 状态机（只读取）
    localparam IDLE        = 5'd0;
    localparam START       = 5'd1;
    localparam SEND_ADDR_W = 5'd2;
    localparam WAIT_ACK1   = 5'd3;
    localparam SEND_REG    = 5'd4;
    localparam WAIT_ACK2   = 5'd5;
    localparam RESTART     = 5'd6;
    localparam SEND_ADDR_R = 5'd7;
    localparam WAIT_ACK3   = 5'd8;
    localparam READ_SEC    = 5'd9;
    localparam SEND_ACK    = 5'd10;
    localparam READ_MIN    = 5'd11;
    localparam SEND_ACK2   = 5'd12;
    localparam READ_HOUR   = 5'd13;
    localparam SEND_NACK   = 5'd14;
    localparam STOP        = 5'd15;
    localparam WAIT_DELAY  = 5'd16;

    reg [4:0] state;
    reg [7:0] data_buf;
    reg [3:0] bit_cnt;
    reg sda_out, sda_en;
    reg [19:0] delay_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            i2c_scl   <= 1'b1;
            sda_out   <= 1'b1;
            sda_en    <= 1'b1;
            sec_bcd   <= 8'h00;
            min_bcd   <= 8'h00;
            hour_bcd  <= 8'h00;
            bit_cnt   <= 0;
            data_buf  <= 0;
            delay_cnt <= 0;
        end else if (tick) begin
            case (state)
                IDLE: begin
                    i2c_scl <= 1'b1; sda_out <= 1'b1; sda_en <= 1'b1;
                    if (scl_cnt == 2'b11) state <= START;
                end
                
                START: begin
                    case (scl_cnt)
                        2'b00: begin sda_en <= 1'b1; sda_out <= 1'b1; i2c_scl <= 1'b1; end 
                        2'b01: begin i2c_scl <= 1'b1; end
                        2'b10: begin sda_out <= 1'b0; i2c_scl <= 1'b1; end
                        2'b11: begin i2c_scl <= 1'b1; end
                    endcase
                    if (scl_cnt == 2'b11) begin
                        state    <= SEND_ADDR_W;
                        data_buf <= {DS3231_ADDR, 1'b0}; 
                        bit_cnt  <= 0;
                    end
                end
                
                SEND_ADDR_W, SEND_REG, SEND_ADDR_R: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b1; sda_out <= data_buf[7]; end 
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin i2c_scl <= 1'b1; end 
                    endcase
                    if (scl_cnt == 2'b11) begin
                        bit_cnt  <= bit_cnt + 1;
                        data_buf <= {data_buf[6:0], 1'b0};
                        if (bit_cnt == 7) begin
                            bit_cnt <= 0;
                            if      (state == SEND_ADDR_W) state <= WAIT_ACK1;
                            else if (state == SEND_REG)    state <= WAIT_ACK2;
                            else                           state <= WAIT_ACK3;
                        end
                    end
                end
                
                WAIT_ACK1, WAIT_ACK2, WAIT_ACK3: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b0; end
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin 
                            i2c_scl <= 1'b1;
                            if (i2c_sda == 1'b1) state <= STOP;
                        end
                    endcase
                    if (scl_cnt == 2'b11 && i2c_sda == 1'b0) begin 
                        if      (state == WAIT_ACK1) state <= SEND_REG;
                        else if (state == WAIT_ACK2) begin 
                            state <= RESTART; 
                            data_buf <= {DS3231_ADDR, 1'b1}; 
                        end
                        else                         state <= READ_SEC;
                    end
                end
                
                RESTART: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b1; sda_out <= 1'b1; end 
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin sda_out <= 1'b0; end 
                    endcase
                    if (scl_cnt == 2'b11) begin
                        state <= SEND_ADDR_R;
                        data_buf <= {DS3231_ADDR, 1'b1};
                        bit_cnt <= 0;
                    end
                end
                
                // 读秒
                READ_SEC: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b0; end 
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin data_buf <= {data_buf[6:0], i2c_sda}; end 
                    endcase
                    if (scl_cnt == 2'b11) begin
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 7) begin
                            bit_cnt <= 0;
                            sec_bcd <= {1'b0, data_buf[5:0], i2c_sda};
                            state <= SEND_ACK;
                        end
                    end
                end
                
                // ACK后读分
                SEND_ACK: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b1; sda_out <= 1'b0; end
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin i2c_scl <= 1'b1; end
                    endcase
                    if (scl_cnt == 2'b11) begin
                        state <= READ_MIN;
                        data_buf <= 8'h00;
                        bit_cnt <= 0;
                    end
                end
                
                // 读分
                READ_MIN: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b0; end 
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin data_buf <= {data_buf[6:0], i2c_sda}; end 
                    endcase
                    if (scl_cnt == 2'b11) begin
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 7) begin
                            bit_cnt <= 0;
                            min_bcd <= {1'b0, data_buf[5:0], i2c_sda};
                            state <= SEND_ACK2;
                        end
                    end
                end
                
                // ACK后读时
                SEND_ACK2: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b1; sda_out <= 1'b0; end
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin i2c_scl <= 1'b1; end
                    endcase
                    if (scl_cnt == 2'b11) begin
                        state <= READ_HOUR;
                        data_buf <= 8'h00;
                        bit_cnt <= 0;
                    end
                end
                
                // 读时
                READ_HOUR: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b0; end 
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin data_buf <= {data_buf[6:0], i2c_sda}; end 
                    endcase
                    if (scl_cnt == 2'b11) begin
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 7) begin
                            bit_cnt <= 0;
                            hour_bcd <= {1'b0, data_buf[5:0], i2c_sda};
                            state <= SEND_NACK;
                        end
                    end
                end
                
                SEND_NACK: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b1; sda_out <= 1'b1; end
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin i2c_scl <= 1'b1; end
                    endcase
                    if (scl_cnt == 2'b11) state <= STOP;
                end
                
                STOP: begin
                    case (scl_cnt)
                        2'b00: begin i2c_scl <= 1'b0; end
                        2'b01: begin sda_en <= 1'b1; sda_out <= 1'b0; end 
                        2'b10: begin i2c_scl <= 1'b1; end
                        2'b11: begin sda_out <= 1'b1; end 
                    endcase
                    if (scl_cnt == 2'b11) state <= WAIT_DELAY;
                end
                
                WAIT_DELAY: begin
                    if (delay_cnt >= 20_000) begin
                        delay_cnt <= 0;
                        state <= IDLE;
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    assign i2c_sda = sda_en ? (sda_out ? 1'bz : 1'b0) : 1'bz;

endmodule