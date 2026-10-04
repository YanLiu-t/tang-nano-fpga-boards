module tm7705_ctrl(
    input wire clk,
    input wire rst_n,
    
    output reg adc_rst,
    output wire adc_sclk,      // 改为 wire，通过组合逻辑生成
    input wire adc_dout,
    output reg adc_cs,
    output reg adc_din,
    input wire adc_drdy,
    
    output reg [15:0] adc_data,
    output reg data_valid
);

// 分频生成SPI时钟 27MHz/14 ≈ 1.93MHz
reg [4:0] clk_div;
reg spi_clk;

always @(posedge clk) begin
    if(clk_div >= 5'd13) begin
        clk_div <= 0;
        spi_clk <= ~spi_clk;
    end else begin
        clk_div <= clk_div + 1;
    end
end

// 状态机定义
localparam IDLE          = 4'd0;
localparam INIT_RST      = 4'd1;
localparam INIT_CLK_REG  = 4'd2;
localparam INIT_SET_REG  = 4'd3;
localparam WAIT_DRDY     = 4'd4;
localparam SEND_READ_CMD = 4'd5;  // 新增：发送读取数据指令状态
localparam READ_DATA     = 4'd6;

reg [3:0] state;
reg [4:0] bit_cnt;       // 扩大一点防止溢出
reg [7:0] cmd;
reg [7:0] reg_data;      // TM7705 寄存器大多是 8 位的
reg [15:0] timer;

// === 发送数据逻辑 (在 spi_clk 的下降沿触发，确保上升沿时数据稳定) ===
always @(negedge spi_clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= IDLE;
        adc_rst <= 1'b1;
        adc_cs <= 1'b1;
        adc_din <= 1'b1;
        bit_cnt <= 0;
        timer <= 0;
        cmd <= 8'd0;
        reg_data <= 8'd0;
    end else begin
        case(state)
            IDLE: begin
                timer <= timer + 1;
                adc_cs <= 1'b1;
                if(timer == 16'd500) begin
                    timer <= 0;
                    state <= INIT_RST;
                end
            end
            
            INIT_RST: begin
                adc_rst <= 1'b0;
                timer <= timer + 1;
                if(timer == 16'd10) begin
                    adc_rst <= 1'b1;
                    timer <= 0;
                    state <= INIT_CLK_REG;
                    cmd <= 8'h20;        // 写时钟寄存器
                    reg_data <= 8'h04;   // 时钟配置参数 (8位即可)
                    bit_cnt <= 0;
                end
            end
            
            INIT_CLK_REG: begin
                adc_cs <= 1'b0;
                if(bit_cnt < 8) begin
                    adc_din <= cmd[7];
                    cmd <= {cmd[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                end else if(bit_cnt < 16) begin
                    adc_din <= reg_data[7];
                    reg_data <= {reg_data[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    adc_cs <= 1'b1;
                    bit_cnt <= 0;
                    state <= INIT_SET_REG;
                    cmd <= 8'h10;        // 写设置寄存器
                    reg_data <= 8'h40;   // 自校准，增益1 (8位即可)
                end
            end
            
            INIT_SET_REG: begin
                adc_cs <= 1'b0;
                if(bit_cnt < 8) begin
                    adc_din <= cmd[7];
                    cmd <= {cmd[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                end else if(bit_cnt < 16) begin
                    adc_din <= reg_data[7];
                    reg_data <= {reg_data[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    adc_cs <= 1'b1;
                    bit_cnt <= 0;
                    state <= WAIT_DRDY;
                end
            end
            
            WAIT_DRDY: begin
                if(adc_drdy == 1'b0) begin
                    bit_cnt <= 0;
                    state <= SEND_READ_CMD;
                    cmd <= 8'h38;  // 关键修复：告诉TM7705下一步要读数据
                end
            end
            
            SEND_READ_CMD: begin
                adc_cs <= 1'b0;
                if(bit_cnt < 8) begin
                    adc_din <= cmd[7];
                    cmd <= {cmd[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    adc_cs <= 1'b1;
                    bit_cnt <= 0;
                    state <= READ_DATA;
                end
            end
            
            READ_DATA: begin
                adc_cs <= 1'b0;
                if(bit_cnt < 16) begin
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    adc_cs <= 1'b1;
                    bit_cnt <= 0;
                    state <= WAIT_DRDY;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

// === 接收数据逻辑 (在 spi_clk 的上升沿采样，保证数据稳定) ===
always @(posedge spi_clk or negedge rst_n) begin
    if(!rst_n) begin
        adc_data <= 16'd0;
        data_valid <= 1'b0;
    end else begin
        data_valid <= 1'b0;
        if(state == READ_DATA && adc_cs == 1'b0) begin
            if(bit_cnt < 16) begin
                adc_data <= {adc_data[14:0], adc_dout};
            end
            // 当接收完最后一位后，拉高 valid 标志
            if(bit_cnt == 15) begin
                data_valid <= 1'b1;
            end
        end
    end
end

// 优化 SCLK 输出逻辑：空闲时保持高电平 (CPOL=1)，只在 CS 拉低时输出时钟
assign adc_sclk = (adc_cs == 1'b0) ? spi_clk : 1'b1;

endmodule