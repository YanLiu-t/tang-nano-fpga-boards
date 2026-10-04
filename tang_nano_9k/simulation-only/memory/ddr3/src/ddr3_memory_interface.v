// ------------------------------------------------------------
// 文件名：ddr3_memory_interface.v
// 说明：高云GW2A DDR3 IP 核的简易行为仿真模型
//       接口完全匹配顶层 ddr3_controler 中的实例化
//       支持突发长度8（写/读），CAS=5，仅用于仿真验证
// ------------------------------------------------------------
module ddr3_memory_interface (
    // ---- 系统接口 ----
    input               clk,              // 用户时钟（仿真与 memory_clk 同源）
    input               memory_clk,       // DDR3 物理时钟（仿真中可忽略）
    input               pll_lock,         // PLL锁定（仿真中视为固定1）
    input               rst_n,            // 复位（低有效）

    // ---- 用户命令接口 ----
    output              cmd_ready,        // 可接收命令（=app_rdy）
    input      [2:0]    cmd,              // 命令：0=写，1=读
    input               cmd_en,           // 命令有效
    input      [28:0]   addr,             // 字节地址（内部取低16位）

    // ---- 写数据接口 ----
    output              wr_data_rdy,      // 可接收写数据（=app_wdf_rdy）
    input      [127:0]  wr_data,          // 写数据（128位）
    input               wr_data_en,       // 写数据有效
    input               wr_data_end,      // 突发结束（本模型忽略）
    input      [15:0]   wr_data_mask,     // 写掩码（本模型忽略）

    // ---- 读数据接口 ----
    output     [127:0]  rd_data,          // 读数据
    output              rd_data_valid,    // 读数据有效
    output              rd_data_end,      // 突发结束（与valid同拍）

    // ---- 刷新/自刷新（仿真忽略） ----
    input               sr_req,
    input               ref_req,
    output              sr_ack,
    output              ref_ack,

    // ---- 状态与时钟输出 ----
    output              init_calib_complete,  // 初始化校准完成
    output              clk_out,              // 输出用户时钟（=clk）
    input               burst,                // 突发类型（仿真忽略）
    output              ddr_rst,              // DDR复位输出（仿真输出0）

    // ---- DDR3 物理接口（仿真中可输出固定值） ----
    output [13:0]       O_ddr_addr,
    output [2:0]        O_ddr_ba,
    output              O_ddr_cs_n,
    output              O_ddr_ras_n,
    output              O_ddr_cas_n,
    output              O_ddr_we_n,
    output              O_ddr_clk,
    output              O_ddr_clk_n,
    output              O_ddr_cke,
    output              O_ddr_odt,
    output              O_ddr_reset_n,
    output [1:0]        O_ddr_dqm,
    inout  [15:0]       IO_ddr_dq,
    inout  [1:0]        IO_ddr_dqs,
    inout  [1:0]        IO_ddr_dqs_n
);

    // ---------- 内部RAM (64K x 128位，即1MB) ----------
    reg [127:0] mem [0:65535];

    // ---------- 初始化及校准完成 ----------
    reg         init_done;
    reg [7:0]   init_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt <= 0;
            init_done <= 1'b0;
        end else if (init_cnt < 8'd100) begin
            init_cnt <= init_cnt + 1;
            init_done <= 1'b0;
        end else
            init_done <= 1'b1;
    end
    assign init_calib_complete = init_done;
    assign clk_out = clk;                // 用户时钟直接输出
    assign ddr_rst = 1'b0;               // 不复位
    assign sr_ack = 1'b0;
    assign ref_ack = 1'b0;

    // ---------- 就绪信号 ----------
    assign cmd_ready   = 1'b1;           // 始终可接收命令
    assign wr_data_rdy = 1'b1;           // 始终可接收写数据

    // ---------- 写操作 ----------
    // 写命令与写数据需同拍有效，地址取低16位
    always @(posedge clk) begin
        if (!rst_n) begin
            // 可初始化RAM（仿真时可忽略）
        end else if (init_done && cmd_en && wr_data_en && (cmd == 3'd0)) begin
            mem[addr[15:0]] <= wr_data;   // 写入数据
        end
    end

    // ---------- 读操作（固定CAS延迟5个周期） ----------
    reg         read_pending;
    reg [3:0]   read_delay_cnt;
    reg [15:0]  read_addr;
    reg [127:0] rd_data_buf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_pending <= 1'b0;
            read_delay_cnt <= 0;
            read_addr <= 0;
            rd_data_buf <= 0;
        end else begin
            // 发起读命令
            if (init_done && cmd_en && (cmd == 3'd1) && !read_pending) begin
                read_pending <= 1'b1;
                read_addr <= addr[15:0];
                read_delay_cnt <= 4'd4;   // 需要延迟4个周期后数据有效（因为还要1拍输出，总延迟5）
            end

            if (read_pending) begin
                if (read_delay_cnt == 0) begin
                    rd_data_buf <= mem[read_addr];
                    read_pending <= 1'b0;
                end else
                    read_delay_cnt <= read_delay_cnt - 1;
            end
        end
    end

    // 读数据输出（数据有效时正好读完）
    assign rd_data = rd_data_buf;
    // 有效信号：当延迟计数为0且读挂起时，即表示数据已读出（下一拍输出）
    // 但我们在延迟计数为0时已经取出了数据，并在同一时钟将read_pending清零，
    // 所以有效信号应该在read_delay_cnt==0且read_pending为1时产生（即在置数前的那一拍？）
    // 为了简单，我们直接让rd_data_valid在rd_data_buf更新后有效一个周期。
    // 更好的方法：在read_delay_cnt==0时，置位一个标志，下一拍输出。
    // 这里采用最直接方式：当read_pending由1变0时，说明数据已准备，但为了和时钟对齐，我们在下一个周期输出有效。
    // 实际仿真中，可以接受延迟一个周期，但为了符合CAS=5，我们设计读命令发出后第5个周期数据有效。
    // 下面按标准做法：
    reg rd_valid_delay;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_valid_delay <= 1'b0;
        else if (read_pending && (read_delay_cnt == 0))
            rd_valid_delay <= 1'b1;
        else
            rd_valid_delay <= 1'b0;
    end
    assign rd_data_valid = rd_valid_delay;
    assign rd_data_end   = rd_valid_delay;   // 突发结束同拍

    // ---------- 物理接口（仿真输出固定值） ----------
    assign O_ddr_addr   = 14'b0;
    assign O_ddr_ba     = 3'b0;
    assign O_ddr_cs_n   = 1'b1;
    assign O_ddr_ras_n  = 1'b1;
    assign O_ddr_cas_n  = 1'b1;
    assign O_ddr_we_n   = 1'b1;
    assign O_ddr_clk    = memory_clk;        // 可随输入时钟翻转，但非必需
    assign O_ddr_clk_n  = ~memory_clk;
    assign O_ddr_cke    = 1'b1;
    assign O_ddr_odt    = 1'b0;
    assign O_ddr_reset_n= 1'b1;
    assign O_ddr_dqm    = 2'b0;

    // 三态物理总线：仿真中可悬空或驱动高阻
    assign IO_ddr_dq   = 16'hzzzz;
    assign IO_ddr_dqs  = 2'bzz;
    assign IO_ddr_dqs_n= 2'bzz;

endmodule