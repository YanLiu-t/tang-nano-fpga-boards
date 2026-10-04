module twinkle_twinkle(
    input  wire       clk,
    input  wire       rst_n,
    output reg        buzzer
);

// 27MHz系统时钟 音符分频值
parameter DO    = 16'd51763;  // 1
parameter RE    = 16'd46053;  // 2
parameter MI    = 16'd41048;  // 3
parameter FA    = 16'd38759;  // 4
parameter SOL   = 16'd34483;  // 5
parameter LA    = 16'd30729;  // 6
parameter SI    = 16'd27397;  // 7
parameter REST  = 16'd65535;  // 休止符

// ============================================
// 《小星星》原曲节奏，全部中音区
// 节拍完全按照原曲：每个音符0.5拍或1拍
// ============================================
reg [23:0] score [0:31];
initial begin
    // ===== 第一句：一闪一闪亮晶晶 =====
    // 简谱：1 1 5 5 6 6 5 -
    // 节奏：每个音0.5拍，最后一个音1拍
    score[0]  = {DO,  8'd1};   // 一
    score[1]  = {DO,  8'd1};   // 闪
    score[2]  = {SOL, 8'd1};   // 一
    score[3]  = {SOL, 8'd1};   // 闪
    score[4]  = {LA,  8'd1};   // 亮
    score[5]  = {LA,  8'd1};   // 晶
    score[6]  = {SOL, 8'd2};   // 晶（拉长）
    score[7]  = {REST,8'd1};   // 换气
    
    // ===== 第二句：满天都是小星星 =====
    // 简谱：4 4 3 3 2 2 1 -
    // 节奏：每个音0.5拍，最后一个音1拍
    score[8]  = {FA,  8'd1};   // 满
    score[9]  = {FA,  8'd1};   // 天
    score[10] = {MI,  8'd1};   // 都
    score[11] = {MI,  8'd1};   // 是
    score[12] = {RE,  8'd1};   // 小
    score[13] = {RE,  8'd1};   // 星
    score[14] = {DO,  8'd2};   // 星（拉长）
    score[15] = {REST,8'd1};   // 换气
    
    // ===== 第三句：挂在天空放光明 =====
    // 简谱：5 5 4 4 3 3 2 -
    // 节奏：每个音0.5拍，最后一个音1拍
    score[16] = {SOL, 8'd1};   // 挂
    score[17] = {SOL, 8'd1};   // 在
    score[18] = {FA,  8'd1};   // 天
    score[19] = {FA,  8'd1};   // 空
    score[20] = {MI,  8'd1};   // 放
    score[21] = {MI,  8'd1};   // 光
    score[22] = {RE,  8'd2};   // 明（拉长）
    score[23] = {REST,8'd1};   // 换气
    
    // ===== 第四句：好像许多小眼睛 =====
    // 简谱：5 5 4 4 3 3 1 -
    // 节奏：每个音0.5拍，最后一个音1拍
    score[24] = {SOL, 8'd1};   // 好
    score[25] = {SOL, 8'd1};   // 像
    score[26] = {FA,  8'd1};   // 许
    score[27] = {FA,  8'd1};   // 多
    score[28] = {MI,  8'd1};   // 小
    score[29] = {MI,  8'd1};   // 眼
    score[30] = {DO,  8'd2};   // 睛（拉长，收尾）
    score[31] = {REST,8'd1};   // 换气
end

reg  [5:0]  note_addr;
reg  [15:0] freq_div;
reg  [7:0]  beats;
reg  [15:0] freq_cnt;
reg  [23:0] time_cnt;

// 一拍时长 = 0.3秒（原曲速度）
parameter ONE_BEAT = 24'd8000000;

reg  [1:0] state;
parameter S_LOAD  = 2'd0;
parameter S_PLAY  = 2'd1;
parameter S_NEXT  = 2'd2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        note_addr <= 6'd0;
        freq_div  <= 16'd0;
        beats     <= 8'd0;
        freq_cnt  <= 16'd0;
        time_cnt  <= 24'd0;
        buzzer    <= 1'b0;
        state     <= S_LOAD;
    end 
    else begin
        case (state)
            S_LOAD: begin
                {freq_div, beats} <= score[note_addr];
                freq_cnt  <= 16'd0;
                time_cnt  <= 24'd0;
                buzzer    <= 1'b0;
                state     <= S_PLAY;
            end
            S_PLAY: begin
                if(freq_div != REST) begin
                    if (freq_cnt < freq_div)
                        freq_cnt <= freq_cnt + 16'd1;
                    else begin
                        freq_cnt <= 16'd0;
                        buzzer   <= ~buzzer;
                    end
                end
                else begin
                    buzzer <= 1'b0;
                end

                if (time_cnt < beats * ONE_BEAT)
                    time_cnt <= time_cnt + 24'd1;
                else begin
                    time_cnt <= 24'd0;
                    state    <= S_NEXT;
                end
            end
            S_NEXT: begin
                if (note_addr < 6'd31) begin
                    note_addr <= note_addr + 6'd1;
                end 
                else begin
                    note_addr <= 6'd0;
                end
                state <= S_LOAD;
            end
            default: state <= S_LOAD;
        endcase
    end
end

endmodule