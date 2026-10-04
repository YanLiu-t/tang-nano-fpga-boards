module led_run2(
    input        Clk,
    input        Reset_n,
    output wire [5:0] Led  // 改为6位，匹配开发板6颗LED，舍弃Led[6]、Led[7]
);

reg [24:0] counter;
reg [2:0] counter2;

// 延时计数器 27MHz 约0.92秒溢出一次
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        counter <= 25'd0;
    else if(counter == 25000000 - 1)
        counter <= 25'd0;
    else
        counter <= counter + 1'd1;
end

// 3位地址计数器 仅循环0~5
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        counter2 <= 3'b000;
    else if(counter == 25000000 - 1) begin
        if(counter2 == 3'b101) // 到第5个灯归零，只跑6路
            counter2 <= 3'b000;
        else
            counter2 <= counter2 + 1'd1;
    end
end

// 例化38译码器，只取低6位输出给板载LED
wire [7:0] y_out;
decoder_3_8 decoder_3_8_inst0(
    .A(counter2),
    .Y(y_out)
);

assign Led = y_out[5:0]; // 截取低6位，对应6颗板载LED


endmodule