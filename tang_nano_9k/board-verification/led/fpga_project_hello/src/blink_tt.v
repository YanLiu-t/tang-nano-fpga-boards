module led(input clk,  //时钟
           input reset,  //复位
           output reg [5:0] light  //输出位
);

parameter delaytime=28'd27000000*0.2; //间隔0.2s一次
parameter ledstyle=6'b000001; //五亮一灭
//parameter ledstyle=6'b111110; //五灭一亮
reg [27:0] count; //计数器

always @(posedge clk or negedge reset) begin
    if(!reset)
        count<=28'd0;
    else if(count <delaytime)
        count<=count+1'd1;
    else
        count<=28'd0;

end

always @(posedge clk or negedge reset) begin
    if(!reset)
        light<=ledstyle;
    else if(delaytime==count)
        light[5:0]<={light[4:0],light[5]};

end

endmodule