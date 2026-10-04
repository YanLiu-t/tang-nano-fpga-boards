module HC595_Driver(
    input  Clk, 
    input  Reset_n, 
    input  [7:0] SEG, 
    input  [7:0] SEL, 
    output reg DIO, 
    output reg SRCLK, 
    output reg RCLK
);

// 修改为 27MHz，匹配开发板板载晶振
parameter CLOCK_FREQ = 27_000_000;   
parameter SRCLK_FREQ = 1_000_000;
parameter MCNT = CLOCK_FREQ / (SRCLK_FREQ * 2) - 1;

reg [7:0] div_cnt;
reg [5:0] cnt;          

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) div_cnt <= 0;
    else if(div_cnt >= MCNT) div_cnt <= 0;
    else div_cnt <= div_cnt + 1'b1;
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) cnt <= 0;
    else if(div_cnt == MCNT) begin
        if(cnt >= 6'd32) cnt <= 0;
        else cnt <= cnt + 1'b1;
    end
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) begin 
        DIO <= 1'b0; SRCLK <= 1'b0; RCLK <= 1'b0; 
    end else begin
        case(cnt)
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
            16: begin DIO <= SEL[7]; SRCLK <= 1'b0; end
            17: begin SRCLK <= 1'b1; end
            18: begin DIO <= SEL[6]; SRCLK <= 1'b0; end
            19: begin SRCLK <= 1'b1; end
            20: begin DIO <= SEL[5]; SRCLK <= 1'b0; end
            21: begin SRCLK <= 1'b1; end
            22: begin DIO <= SEL[4]; SRCLK <= 1'b0; end
            23: begin SRCLK <= 1'b1; end
            24: begin DIO <= SEL[3]; SRCLK <= 1'b0; end
            25: begin SRCLK <= 1'b1; end
            26: begin DIO <= SEL[2]; SRCLK <= 1'b0; end
            27: begin SRCLK <= 1'b1; end
            28: begin DIO <= SEL[1]; SRCLK <= 1'b0; end
            29: begin SRCLK <= 1'b1; end
            30: begin DIO <= SEL[0]; SRCLK <= 1'b0; end
            31: begin SRCLK <= 1'b1; end             
            32: begin RCLK <= 1'b1; end              
            default: begin DIO <= 1'b0; SRCLK <= 1'b0; RCLK <= 1'b0; end
        endcase
    end
end
endmodule