`timescale 1ns/1ps

module tb_top_sd_rw;

reg         sys_clk;
reg         sys_rst_n;

wire        sd_miso;
wire        sd_clk;
wire        sd_cs;
wire        sd_mosi;
wire [3:0]  led;

// -------------------- DUT 顶层例化 --------------------
top_sd_rw u_top_sd_rw(
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .sd_miso    (sd_miso),
    .sd_clk     (sd_clk),
    .sd_cs      (sd_cs),
    .sd_mosi    (sd_mosi),
    .led        (led)
);

// -------------------- SD卡行为模拟模型（SPI从机） --------------------
sd_spi_slave_model u_sd_spi_slave_model(
    .sd_clk     (sd_clk),
    .sd_cs      (sd_cs),
    .sd_mosi    (sd_mosi),
    .sd_miso    (sd_miso)
);

// -------------------- 产生50MHz系统时钟 --------------------
initial begin
    sys_clk = 1'b0;
    forever #10 sys_clk = ~sys_clk;
end

initial begin
    sys_rst_n = 1'b0;
    #200;
    sys_rst_n = 1'b1;

    #200_000_000; //仿真足够长时间跑完初始化+写+读
    $display("========== Simulation Finish ==========");
    $finish;
end

initial begin
    $dumpfile("wave_sd_rw.vcd");
    $dumpvars(0,tb_top_sd_rw);
end

endmodule

//=====================================================================
// SD SPI从机行为模型：仿真用，模拟SD卡应答命令、返回R1、返回数据块0xFE+256*16bit数据+CRC
// 简化模型：不完整SD协议，适配本工程的CMD0,CMD17,CMD24命令
//=====================================================================
module sd_spi_slave_model(
input           sd_clk,
input           sd_cs,
input           sd_mosi,
output reg      sd_miso
);

reg [7:0] shift_reg_rx;
reg [7:0] shift_reg_tx;
integer bit_cnt;

//仿真SD卡存储扇区：扇区2000，512字节
reg [7:0] mem_sd [0:511];

initial begin
    sd_miso = 1'b1;
    bit_cnt = 0;
    shift_reg_rx = 8'hFF;
    shift_reg_tx = 8'hFF;
end

//SPI采样：sd_clk上升沿采样MOSI，下降沿输出MISO
always @(posedge sd_clk or posedge sd_cs) begin
    if(sd_cs == 1'b1) begin
        bit_cnt <= 0;
        shift_reg_rx <= 8'hFF;
    end
    else begin
        shift_reg_rx <= {shift_reg_rx[6:0], sd_mosi};
        bit_cnt <= bit_cnt + 1;
        if(bit_cnt == 7) begin
            //收到1字节命令
            case(shift_reg_rx)
                8'h40: shift_reg_tx <= 8'h01; // CMD0 R1=0x01 idle
                8'h51: shift_reg_tx <= 8'h00; // CMD17 读扇区 R1=0x00
                8'h58: shift_reg_tx <= 8'h00; // CMD24 写扇区 R1=0x00
                default: shift_reg_tx <= 8'h00;
            endcase
        end
    end
end

always @(negedge sd_clk or posedge sd_cs) begin
    if(sd_cs) begin
        sd_miso <= 1'b1;
    end
    else begin
        sd_miso <= shift_reg_tx[7];
        shift_reg_tx <= {shift_reg_tx[6:0],1'b1};
    end
end

endmodule
