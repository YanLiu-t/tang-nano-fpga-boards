`timescale 1ns / 1ps

module tb_sd_photo_sim;

parameter SYS_CLK_PERIOD = 20;   //50MHz sys_clk
parameter DDR_MAX_ADDR   = 786432;
parameter SD_SEC_NUM     = 4609;

reg         sys_clk;
reg         rst_n;
reg         sd_miso;

wire        sd_clk;
wire        sd_cs;
wire        sd_mosi;

wire        sd_init_done;
wire        sd_rd_busy;
wire        sd_rd_val_en;
wire [15:0] sd_rd_val_data;
wire        sd_rd_start_en;
wire [31:0] sd_rd_sec_addr;
wire        ddr_wr_en;
wire [15:0] ddr_wr_data;

// ----------------------
// 1.例化 sd_read_photo
// ----------------------
sd_read_photo u_sd_read_photo(
    .clk            (sys_clk),
    .rst_n          (rst_n),
    .ddr_max_addr   (DDR_MAX_ADDR),
    .sd_sec_num     (SD_SEC_NUM),
    .rd_busy        (sd_rd_busy),
    .sd_rd_val_en   (sd_rd_val_en),
    .sd_rd_val_data (sd_rd_val_data),
    .rd_start_en    (sd_rd_start_en),
    .rd_sec_addr    (sd_rd_sec_addr),
    .ddr_wr_en      (ddr_wr_en),
    .ddr_wr_data    (ddr_wr_data)
);

// ----------------------
// 2.例化 sd_ctrl_top
// ----------------------
sd_ctrl_top u_sd_ctrl_top(
    .clk_ref        (sys_clk),
    .clk_ref_180deg (sys_clk),  //仿真没有180°相位时钟，直接复用sys_clk
    .rst_n          (rst_n),
    //SD卡物理接口
    .sd_miso        (sd_miso),
    .sd_clk         (sd_clk),
    .sd_cs          (sd_cs),
    .sd_mosi        (sd_mosi),
    //写SD：仿真不用写，固定0
    .wr_start_en    (1'b0),
    .wr_sec_addr    (32'd0),
    .wr_data        (16'd0),
    .wr_busy        (),
    .wr_req         (),
    //读SD 用户接口
    .rd_start_en    (sd_rd_start_en),
    .rd_sec_addr    (sd_rd_sec_addr),
    .rd_busy        (sd_rd_busy),
    .rd_val_en      (sd_rd_val_en),
    .rd_val_data    (sd_rd_val_data),

    .sd_init_done   (sd_init_done)
);

// ----------------------
// 时钟、复位
// ----------------------
initial begin
    sys_clk = 1'b0;
    forever #(SYS_CLK_PERIOD/2) sys_clk = ~sys_clk;
end

initial begin
    rst_n   = 1'b0;
    sd_miso = 1'b1;
    #100;
    rst_n   = 1'b1;
    #3_000_000;   //仿真3ms，SD初始化比较慢
    $display("sim finish");
    $finish;
end

//打印关键信号
initial begin
    $monitor("T=%0t | sd_init_done=%b | sd_rd_busy=%b | rd_start_en=%b | sec_addr=%0d | ddr_wr_en=%b",
        $time, sd_init_done, sd_rd_busy, sd_rd_start_en, sd_rd_sec_addr, ddr_wr_en);
end

//---------------------------
//简易SD卡SPI从机模拟（极简模型）
//注意：这个是极简模型，只做演示；真实SD命令应答需要完善，这里模拟初始化成功，返回测试数据
//---------------------------
reg [7:0] spi_shift_reg;
always@(posedge sd_clk or negedge rst_n) begin
    if(!rst_n) begin
        spi_shift_reg <= 8'hff;
        sd_miso <= 1'b1;
    end else begin
        spi_shift_reg <= {spi_shift_reg[6:0], sd_mosi};
        //模拟：CS拉低一段时间后返回0x01（SD初始化应答）
        if(sd_cs == 1'b0) begin
            sd_miso <= 1'b0;
        end else begin
            sd_miso <= 1'b1;
        end
    end
end

endmodule