module asyn_rst_syn(
    input      reset_n,   // 外部输入异步复位信号（低电平有效）
    input      clk,       // 驱动时钟
    output reg syn_reset  // 输出同步复位信号（高电平有效，对应你代码里的需求）
);

reg rst_r1;

always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rst_r1    <= 1'b1;
        syn_reset <= 1'b1;
    end
    else begin
        rst_r1    <= 1'b0;
        syn_reset <= rst_r1;
    end
end

endmodule