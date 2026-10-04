module adcs128102(
    Clk,
    Reset_n,
    Conv_Go,
    Conv_Done,
    Addr,
    Data,
    ADC_SCLK,
    ADC_CS_N,
    ADC_DIN,
    ADC_DOUT
);

input Clk;
input Reset_n;
input Conv_Go;
input [3:0] Addr;

output reg Conv_Done;
output reg [11:0] Data;
output reg ADC_CS_N;
output reg ADC_DIN;
output reg ADC_SCLK;
input ADC_DOUT;

// 参数定义（请勿修改数值，保持原样）
parameter CLOCK_FERQ = 50_000_000;
parameter SCLK_FREQ = 12_500_000;
parameter MCNT_DIV_CNT = CLOCK_FERQ / (SCLK_FREQ * 2) - 1;   // 计算结果为 1

// 内部信号声明
reg [7:0] DIV_CNT;
reg Conv_En;
reg [5:0] LSM_CNT;
reg [11:0] Data_r;
reg [2:0] r_Addr;

// 1. 转换使能
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        Conv_En <= 1'b0;
    else if(Conv_Go)
        Conv_En <= 1'b1;
    else if((LSM_CNT == 6'd34) && (DIV_CNT == MCNT_DIV_CNT))
        Conv_En <= 1'b0;
    else
        Conv_En <= Conv_En;
end

// 2. 锁存地址
always @(posedge Clk) begin
    if(Conv_Go)
        r_Addr <= Addr[2:0];
    else
        r_Addr <= r_Addr;
end

// 3. 分频计数器
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        DIV_CNT <= 8'd0;
    else if(Conv_En) begin
        if(DIV_CNT == MCNT_DIV_CNT)
            DIV_CNT <= 8'd0;
        else
            DIV_CNT <= DIV_CNT + 1'd1;
    end
    else
        DIV_CNT <= 8'd0;
end

// 4. 状态计数器（每个半周期加1）
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        LSM_CNT <= 6'd0;
    else if(DIV_CNT == MCNT_DIV_CNT) begin
        if(LSM_CNT == 6'd34)
            LSM_CNT <= 6'd0;
        else
            LSM_CNT <= LSM_CNT + 1'd1;
    end
    else
        LSM_CNT <= LSM_CNT;
end

// 5. 主状态机（完整 0~34）
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) begin
        Data_r     <= 12'd0;
        ADC_CS_N   <= 1'd1;
        ADC_DIN    <= 1'd1;
        ADC_SCLK   <= 1'd1;
    end
    else begin
        case(LSM_CNT)
            6'd0 : begin ADC_CS_N <= 1'd1; ADC_SCLK <= 1'd1; end
            6'd1 : begin ADC_CS_N <= 1'd0; end
            6'd2 : begin ADC_SCLK <= 1'd0; end
            6'd3 : begin ADC_SCLK <= 1'd1; ADC_DIN <= r_Addr[2]; end
            6'd4 : begin ADC_SCLK <= 1'd0; end
            6'd5 : begin ADC_SCLK <= 1'd1; ADC_DIN <= r_Addr[1]; end
            6'd6 : begin ADC_SCLK <= 1'd0; end
            6'd7 : begin ADC_SCLK <= 1'd1; ADC_DIN <= r_Addr[0]; end
            6'd8 : begin ADC_SCLK <= 1'd0; end
            6'd9 : begin ADC_SCLK <= 1'd1; ADC_DIN <= 1'b0; end      // 第4位固定0
            6'd10: begin ADC_SCLK <= 1'd0; end
            6'd11: begin ADC_SCLK <= 1'd1; Data_r[11] <= ADC_DOUT; end
            6'd12: begin ADC_SCLK <= 1'd0; end
            6'd13: begin ADC_SCLK <= 1'd1; Data_r[10] <= ADC_DOUT; end
            6'd14: begin ADC_SCLK <= 1'd0; end
            6'd15: begin ADC_SCLK <= 1'd1; Data_r[9]  <= ADC_DOUT; end
            6'd16: begin ADC_SCLK <= 1'd0; end
            6'd17: begin ADC_SCLK <= 1'd1; Data_r[8]  <= ADC_DOUT; end
            6'd18: begin ADC_SCLK <= 1'd0; end
            6'd19: begin ADC_SCLK <= 1'd1; Data_r[7]  <= ADC_DOUT; end
            6'd20: begin ADC_SCLK <= 1'd0; end
            6'd21: begin ADC_SCLK <= 1'd1; Data_r[6]  <= ADC_DOUT; end
            6'd22: begin ADC_SCLK <= 1'd0; end
            6'd23: begin ADC_SCLK <= 1'd1; Data_r[5]  <= ADC_DOUT; end
            6'd24: begin ADC_SCLK <= 1'd0; end
            6'd25: begin ADC_SCLK <= 1'd1; Data_r[4] <= ADC_DOUT; end
            6'd26: begin ADC_SCLK <= 1'd0; end
            6'd27: begin ADC_SCLK <= 1'd1; Data_r[3] <= ADC_DOUT; end
            6'd28: begin ADC_SCLK <= 1'd0; end
            6'd29: begin ADC_SCLK <= 1'd1; Data_r[2] <= ADC_DOUT; end
            6'd30: begin ADC_SCLK <= 1'd0; end
            6'd31: begin ADC_SCLK <= 1'd1; Data_r[1] <= ADC_DOUT; end
            6'd32: begin ADC_SCLK <= 1'd0; end
            6'd33: begin ADC_SCLK <= 1'd1; Data_r[0] <= ADC_DOUT; end
            6'd34: begin ADC_SCLK <= 1'd1; ADC_CS_N <= 1'd1; ADC_DIN <= 1'd1; end
            default: begin ADC_CS_N <= 1'd1; ADC_SCLK <= 1'd1; ADC_DIN <= 1'd1; end
        endcase
    end
end

// 6. 转换完成与数据输出
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) begin
        Data      <= 12'd0;
        Conv_Done <= 1'b0;
    end
    else if((LSM_CNT == 6'd34) && (DIV_CNT == MCNT_DIV_CNT)) begin
        Conv_Done <= 1'b1;
        Data      <= Data_r;
    end
    else begin
        Conv_Done <= 1'b0;
        Data      <= Data;
    end
end

endmodule