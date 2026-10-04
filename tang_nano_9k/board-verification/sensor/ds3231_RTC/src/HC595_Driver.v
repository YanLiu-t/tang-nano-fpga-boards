module HC595_Driver(
    input Clk, 
    input Reset_n, 
    input [7:0] SEG, 
    input [7:0] SEL, 
    output reg DIO, 
    output reg SRCLK, 
    output reg RCLK
);

parameter CLOCK_FREQ = 27_000_000;
parameter SRCLK_FREQ = 1_000_000;
parameter MCNT = CLOCK_FREQ / (SRCLK_FREQ * 2) - 1;

reg [7:0] div_cnt;
reg [5:0] cnt;

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) 
        div_cnt <= 0;
    else if(div_cnt >= MCNT)
        div_cnt <= 0;
    else 
        div_cnt <= div_cnt + 1'b1;
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) 
        cnt <= 0;
    else if(div_cnt == MCNT) begin
        if(cnt >= 6'd33)       // 多一个状态用于消隐
            cnt <= 0;
        else
            cnt <= cnt + 1'b1;
    end
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) begin 
        DIO <= 1'b0; SRCLK <= 1'b0; RCLK <= 1'b0; 
    end else begin
        case(cnt)
            // ---- 先发 SEG ----
            0:  begin DIO <= SEG[7]; SRCLK <= 1'b0; RCLK <= 1'b0; end
            1:  begin SRCLK <= 1'b1; end
            2:  begin DIO <= SEG[6]; SRCLK <= 1'b0; end
            3:  begin SRCLK <= 1'b1; end
            4:  begin DIO <= SEG[5]; SRCLK <= 1'b0; end
            5:  begin SRCLK <= 1'b1; end
            6:  begin DIO <= SEG[4]; SRCLK <= 1'b0; end
            7:  begin SRCLK <= 1'b1; end
            8:  begin DIO <= SEG[3]; SRCLK <= 1'b0; end
            9:  begin SRCLK <= 1'b1; end
            10: begin DIO <= SEG[2]; SRCLK <= 1'b0; end
            11: begin SRCLK <= 1'b1; end
            12: begin DIO <= SEG[1]; SRCLK <= 1'b0; end
            13: begin SRCLK <= 1'b1; end
            14: begin DIO <= SEG[0]; SRCLK <= 1'b0; end
            15: begin SRCLK <= 1'b1; end
            
            // ---- 再发 SEL（先发全灭，消除重影） ----
            16: begin DIO <= 1'b1; SRCLK <= 1'b0; end  // SEL[7]=1（假设高电平灭）
            17: begin SRCLK <= 1'b1; end
            18: begin DIO <= 1'b1; SRCLK <= 1'b0; end  // SEL[6]=1
            19: begin SRCLK <= 1'b1; end
            20: begin DIO <= 1'b1; SRCLK <= 1'b0; end  // SEL[5]=1
            21: begin SRCLK <= 1'b1; end
            22: begin DIO <= 1'b1; SRCLK <= 1'b0; end  // SEL[4]=1
            23: begin SRCLK <= 1'b1; end
            24: begin DIO <= SEL[3]; SRCLK <= 1'b0; end
            25: begin SRCLK <= 1'b1; end
            26: begin DIO <= SEL[2]; SRCLK <= 1'b0; end
            27: begin SRCLK <= 1'b1; end
            28: begin DIO <= SEL[1]; SRCLK <= 1'b0; end
            29: begin SRCLK <= 1'b1; end
            30: begin DIO <= SEL[0]; SRCLK <= 1'b0; end
            31: begin SRCLK <= 1'b1; end
            
            // ---- 锁存 ----
            32: begin RCLK <= 1'b1; end
            
            // ---- 消隐：锁存后立即关闭所有位 ----
            33: begin 
                RCLK <= 1'b0; 
                // 发送全灭的位选
                DIO <= 1'b1; SRCLK <= 1'b0;
            end
            
            default: begin DIO <= 1'b0; SRCLK <= 1'b0; RCLK <= 1'b0; end
        endcase
    end
end

endmodule