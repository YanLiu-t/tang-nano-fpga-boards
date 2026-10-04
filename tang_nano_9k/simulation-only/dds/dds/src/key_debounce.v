module key_debounce(
input           sys_clk ,
input           sys_rst_n ,

input           key ,         //外部输入的按键值
output reg      key_filter    //消抖后稳定按键输出
);

//parameter define
parameter CNT_MAX = 20'd540_000;   // 27MHz 20ms消抖

//reg define
reg [19:0] cnt ;
reg key_d0;   //同步打拍1级，消除亚稳态
reg key_d1;   //同步打拍2级

//两级寄存器同步外部按键信号
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

//消抖计数器逻辑
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        cnt <= 20'd0;
    else begin
        if(key_d1 != key_d0)        //检测电平跳变（抖动产生）
            cnt <= CNT_MAX;
        else begin
            if(cnt > 20'd0)
                cnt <= cnt - 1'b1;
            else
                cnt <= 20'd0;
        end
    end
end

//计时结束，更新稳定按键电平
always @ (posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        key_filter <= 1'b1;
    else if(cnt == 20'd1)
        key_filter <= key_d1;
    else
        key_filter <= key_filter;
end

endmodule