// ds3231_driver.v - 终极强制初始化版
module ds3231_driver(
    input  clk,
    input  rst_n,
    inout  i2c_sda,
    output i2c_scl,
    output [7:0] second,
    output       ack_ok,
    output       init_done
);

    localparam DEV_ADDR = 7'h68;
    
    localparam IDLE          = 4'd0;
    localparam START         = 4'd1;
    localparam SEND_BYTE     = 4'd2;
    localparam ACK_CHECK     = 4'd3;
    localparam READ_BYTE     = 4'd4;
    localparam STOP_BIT      = 4'd5;
    localparam WAIT          = 4'd6;
    
    reg [3:0]  state;
    reg [7:0]  shift_reg;
    reg [3:0]  bit_cnt;
    reg [15:0] clk_div;
    reg [3:0]  phase_cnt;
    reg        scl_reg;
    reg        sda_out;
    reg        sda_oe;
    reg        ack_ok_reg;
    reg [25:0] delay_cnt;
    reg [7:0]  second_reg;
    reg [3:0]  read_cnt;
    reg        init_done_reg;
    reg [4:0]  init_cnt;       // 初始化计数器 0~18
    
    assign i2c_scl = scl_reg;
    assign i2c_sda = sda_oe ? sda_out : 1'bz;
    assign ack_ok = ack_ok_reg;
    assign second = second_reg;
    assign init_done = init_done_reg;
    
    // I2C时钟
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_div <= 0;
        else if (clk_div >= 16'd249)
            clk_div <= 0;
        else
            clk_div <= clk_div + 1;
    end
    
    wire i2c_tick = (clk_div == 16'd249);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            shift_reg <= 0;
            bit_cnt <= 0;
            phase_cnt <= 0;
            scl_reg <= 1;
            sda_out <= 1;
            sda_oe <= 0;
            ack_ok_reg <= 0;
            delay_cnt <= 0;
            second_reg <= 0;
            read_cnt <= 0;
            init_done_reg <= 0;
            init_cnt <= 0;
        end
        else if (i2c_tick) begin
            case (state)
                
                IDLE: begin
                    scl_reg <= 1;
                    sda_out <= 1;
                    sda_oe <= 0;
                    delay_cnt <= delay_cnt + 1;
                    
                    if (delay_cnt >= 26'd500000) begin
                        delay_cnt <= 0;
                        state <= START;
                        phase_cnt <= 0;
                        sda_oe <= 1;
                        
                        if (!init_done_reg) begin
                            // ⭐ 初始化：写设备地址
                            shift_reg <= {DEV_ADDR, 1'b0};
                            bit_cnt <= 8;
                            init_cnt <= 0;
                        end
                        else begin
                            // ⭐ 读取：写设备地址
                            shift_reg <= {DEV_ADDR, 1'b0};
                            bit_cnt <= 8;
                        end
                    end
                end
                
                START: begin
                    case (phase_cnt)
                        0: begin 
                            sda_out <= 0; 
                            phase_cnt <= 1; 
                        end
                        1: begin
                            scl_reg <= 0;
                            phase_cnt <= 0;
                            state <= SEND_BYTE;
                        end
                    endcase
                end
                
                SEND_BYTE: begin
                    case (phase_cnt)
                        0: begin
                            sda_out <= shift_reg[7];
                            sda_oe <= 1;
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            phase_cnt <= 1;
                        end
                        1: begin 
                            scl_reg <= 1; 
                            phase_cnt <= 2; 
                        end
                        2: begin
                            scl_reg <= 0;
                            if (bit_cnt > 1) begin
                                bit_cnt <= bit_cnt - 1;
                                phase_cnt <= 0;
                            end
                            else begin
                                phase_cnt <= 0;
                                sda_oe <= 0;
                                state <= ACK_CHECK;
                            end
                        end
                    endcase
                end
                
                ACK_CHECK: begin
                    case (phase_cnt)
                        0: begin
                            scl_reg <= 1;
                            phase_cnt <= 1;
                        end
                        1: begin
                            phase_cnt <= 2;
                        end
                        2: begin
                            scl_reg <= 0;
                            phase_cnt <= 0;
                            
                            if (i2c_sda == 1'b0) begin
                                ack_ok_reg <= 1;
                                
                                // ===== 初始化阶段 =====
                                if (!init_done_reg) begin
                                    init_cnt <= init_cnt + 1;
                                    case (init_cnt)
                                        // 写入寄存器地址 0x00 (秒寄存器)
                                        0: begin
                                            shift_reg <= 8'h00;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // 写入秒 = 0x00
                                        1: begin
                                            shift_reg <= 8'h00;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // 写入寄存器地址 0x01 (分寄存器)
                                        2: begin
                                            shift_reg <= 8'h01;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // 写入分 = 0x30 (30分)
                                        3: begin
                                            shift_reg <= 8'h30;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // 写入寄存器地址 0x02 (时寄存器)
                                        4: begin
                                            shift_reg <= 8'h02;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // 写入时 = 0x12 (12点)
                                        5: begin
                                            shift_reg <= 8'h12;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // ⭐ 写入控制寄存器地址 0x0E (启动振荡器)
                                        6: begin
                                            shift_reg <= 8'h0E;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // ⭐ 控制寄存器 = 0x00 (启动振荡器)
                                        7: begin
                                            shift_reg <= 8'h00;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // ⭐ 写入状态寄存器地址 0x0F (清除OSF)
                                        8: begin
                                            shift_reg <= 8'h0F;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // ⭐ 状态寄存器 = 0x00 (清除OSF标志)
                                        9: begin
                                            shift_reg <= 8'h00;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // ⭐ 再写一次控制寄存器确保启动
                                        10: begin
                                            shift_reg <= 8'h0E;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        11: begin
                                            shift_reg <= 8'h00;
                                            bit_cnt <= 8;
                                            sda_oe <= 1;
                                            state <= SEND_BYTE;
                                        end
                                        // 初始化完成
                                        12: begin
                                            init_done_reg <= 1;
                                            state <= STOP_BIT;
                                            phase_cnt <= 0;
                                        end
                                        default: state <= IDLE;
                                    endcase
                                end
                                // ===== 读取阶段 =====
                                else begin
                                    // 写寄存器地址 0x00
                                    shift_reg <= 8'h00;
                                    bit_cnt <= 8;
                                    sda_oe <= 1;
                                    state <= SEND_BYTE;
                                end
                            end
                            else begin
                                ack_ok_reg <= 0;
                                state <= IDLE;
                            end
                        end
                    endcase
                end
                
                READ_BYTE: begin
                    case (phase_cnt)
                        0: begin
                            sda_oe <= 0;
                            phase_cnt <= 1;
                        end
                        1: begin
                            scl_reg <= 1;
                            phase_cnt <= 2;
                        end
                        2: begin
                            shift_reg <= {shift_reg[6:0], i2c_sda};
                            scl_reg <= 0;
                            if (read_cnt < 7) begin
                                read_cnt <= read_cnt + 1;
                                phase_cnt <= 0;
                            end
                            else begin
                                read_cnt <= 0;
                                phase_cnt <= 0;
                                
                                second_reg <= shift_reg & 8'h7F;
                                
                                sda_out <= 1;
                                sda_oe <= 1;
                                state <= STOP_BIT;
                            end
                        end
                    endcase
                end
                
                STOP_BIT: begin
                    case (phase_cnt)
                        0: begin 
                            sda_out <= 0; 
                            sda_oe <= 1; 
                            phase_cnt <= 1; 
                        end
                        1: begin 
                            scl_reg <= 1; 
                            phase_cnt <= 2; 
                        end
                        2: begin
                            sda_out <= 1;
                            sda_oe <= 0;
                            phase_cnt <= 0;
                            
                            if (!init_done_reg) begin
                                // 初始化还没完成，继续
                                state <= IDLE;
                            end
                            else begin
                                // ⭐ 读取完成，发读地址
                                state <= START;
                                phase_cnt <= 0;
                                sda_oe <= 1;
                                shift_reg <= {DEV_ADDR, 1'b1};  // 读地址
                                bit_cnt <= 8;
                            end
                        end
                    endcase
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule