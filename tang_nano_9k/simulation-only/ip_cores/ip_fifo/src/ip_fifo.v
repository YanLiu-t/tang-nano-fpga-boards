module ip_fifo(
input sys_clk,        // 板子原始输入晶振时钟（你的板子为27MHz）
input sys_rst_n       // 全局低电平复位信号
);

// 内部连线定义
wire clk_50m ;              // PLL生成：FIFO写侧时钟 50MHz
wire clk_100m ;             // PLL生成：FIFO读侧时钟 100MHz
wire lock ;                 // PLL时钟锁定标志，高电平代表时钟稳定输出
wire rst_n ;                // 系统最终有效复位
wire fifo_wr_en ;           // FIFO写使能
wire fifo_rd_en ;           // FIFO读使能
wire [7:0] fifo_wr_data ;   // 待写入FIFO的8位数据
wire [7:0] fifo_rd_data ;   // 从FIFO读出的8位数据
wire almost_full ;          // FIFO即将写满
wire almost_empty ;         // FIFO即将读空
wire fifo_full ;            // FIFO已满标志
wire fifo_empty ;           // FIFO已空标志
wire [8:0] fifo_wr_data_count ; // 写时钟域：FIFO已存入数据个数
wire [8:0] fifo_rd_data_count ; // 读时钟域：FIFO剩余可读数据个数

// 生成最终复位：原始复位有效 并且 PLL时钟稳定锁定，系统才正常工作
assign rst_n = sys_rst_n & lock;

// 例化PLL锁相环IP：输入板载sys_clk，分频倍频出两路异步时钟
clk_wiz_0 clk_wiz_0(
    .clkout  (clk_100m),
    .lock    (lock    ),
    .clkoutd (clk_50m ),
    .reset   (~sys_rst_n),
    .clkin   (sys_clk)
);

// 例化异步FIFO IP核：写时钟50M，读时钟100M，完成跨时钟域缓存
fifo_top fifo_top(
    .Data        (fifo_wr_data     ),
    .Reset       (~rst_n           ),
    .WrClk       (clk_50m          ),
    .RdClk       (clk_100m         ),
    .WrEn        (fifo_wr_en       ),
    .RdEn        (fifo_rd_en      ),
    .Wnum        (fifo_wr_data_count),
    .Rnum        (fifo_rd_data_count),
    .Almost_Empty(almost_empty     ),
    .Almost_Full (almost_full      ),
    .Q           (fifo_rd_data     ),
    .Empty       (fifo_empty       ),
    .Full        (fifo_full        )
);

// 例化FIFO写控制模块：产生递增测试数据、写使能
fifo_wr u_fifo_wr(
    .wr_clk             (clk_50m          ),
    .rst_n              (rst_n            ),
    .fifo_wr_data_count (fifo_wr_data_count),
    .fifo_wr_en         (fifo_wr_en       ),
    .fifo_wr_data       (fifo_wr_data     ),
    .fifo_empty         (fifo_empty       )
);

// 例化FIFO读控制模块：产生读使能，读出FIFO内部数据
fifo_rd u_fifo_rd(
    .rd_clk             (clk_100m         ),
    .rst_n              (rst_n            ),
    .fifo_rd_data_count (fifo_rd_data_count),
    .fifo_rd_en         (fifo_rd_en       ),
    .fifo_rd_data       (fifo_rd_data     ),
    .fifo_full          (fifo_full        )
);

endmodule