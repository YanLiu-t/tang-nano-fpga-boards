module key_debounce(
    input           sys_clk ,
    input           sys_rst_n ,
    input           key ,         // 外部输入的按键值
    
    output reg      key_flag ,    // 按键状态发生变化时的单周期脉冲
    output wire     key_value     // 消抖后的稳定按键电平
);

// parameter define (27MHz 20ms消抖)
parameter CNT_MAX = 20'd540_000;   

// reg define
reg [19:0] cnt ;
reg key_d0;   // 同步打拍1级，消除亚稳态
reg key_d1;   // 同步打拍2级
reg key_filter; // 内部稳定状态

assign key_value = key_filter;

// 两级寄存器同步外部按键信号
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        key_d0 <= 1'b1;
        key_d1 <= 1'b1;
    end
    else begin
        key_d0 <= key;
        key_d1 <= key_d0;
    end
end

// 消抖计数器逻辑
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt <= 20'd0;
    else begin
        if(key_d1 != key_d0)        // 检测电平跳变（抖动产生）
            cnt <= CNT_MAX;
        else begin
            if(cnt > 20'd0)
                cnt <= cnt - 1'b1;
            else
                cnt <= 20'd0;
        end
    end
end

// 计时结束，更新稳定按键电平
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        key_filter <= 1'b1;
    else if(cnt == 20'd1)
        key_filter <= key_d1;
    else
        key_filter <= key_filter;
end

// 提取按键状态变化的边沿（生成 key_flag 脉冲）
reg key_filter_d0;
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        key_filter_d0 <= 1'b1;
    else
        key_filter_d0 <= key_filter;
end

always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        key_flag <= 1'b0;
    else if(key_filter_d0 != key_filter) // 只要电平变了，就给一个时钟周期的 1
        key_flag <= 1'b1;
    else
        key_flag <= 1'b0;
end

endmodule