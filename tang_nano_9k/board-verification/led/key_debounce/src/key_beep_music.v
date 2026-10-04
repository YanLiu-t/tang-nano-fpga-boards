module key_beep_music(
    input sys_clk,
    input sys_rst_n,

    input key_filter,

    output reg beep
);

reg key_d0;
wire key_down;

//----------------------
// 1. 按键下降沿检测
//----------------------
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        key_d0 <= 1'b1;
    else
        key_d0 <= key_filter;
end

assign key_down = (~key_filter) & key_d0;

//----------------------
// 2. 播放状态与结束标志
//----------------------
reg play_en;
wire song_end; 

always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        play_en <= 1'b0;
    else if(key_down)
        play_en <= ~play_en; 
    else if(song_end)
        play_en <= 1'b0;     
end

//================================================
// 东方红音符表 (基于 27MHz 系统时钟)
//================================================
parameter DO  = 25813;   // 523Hz
parameter RE  = 22998;   // 587Hz
parameter MI  = 20486;   // 659Hz
parameter FA  = 19341;   // 698Hz
parameter SO  = 17219;   // 784Hz
parameter LA  = 15341;   // 880Hz
parameter XI  = 13664;   // 988Hz

reg [31:0] freq_cnt;
reg [31:0] tone_freq;

reg [31:0] tone_cnt; 
reg [7:0]  note_num;
reg [7:0]  note_beats; // 当前音符的拍数

// 基础拍子时钟周期数：27MHz * 0.35秒 ≈ 9,450,000 
parameter ONE_BEAT_CYCLES = 32'd9450000; 

//================================================
// 音符与节拍选择（实现真正的旋律节奏）
//================================================
always @(*) begin
    case(note_num)
        // 第一段：东方红，太阳升
        0:  begin tone_freq = SO; note_beats = 1; end // 东
        1:  begin tone_freq = SO; note_beats = 1; end // 方
        2:  begin tone_freq = LA; note_beats = 2; end // 红 —— (长音)
        3:  begin tone_freq = SO; note_beats = 1; end // 太
        4:  begin tone_freq = MI; note_beats = 1; end // 阳
        5:  begin tone_freq = RE; note_beats = 2; end // 升 —— (长音)
        
        6:  begin tone_freq = DO; note_beats = 1; end // 中
        7:  begin tone_freq = RE; note_beats = 1; end // 国
        8:  begin tone_freq = MI; note_beats = 1; end // 出
        9:  begin tone_freq = SO; note_beats = 1; end // 了
        10: begin tone_freq = LA; note_beats = 1; end // 个
        11: begin tone_freq = SO; note_beats = 1; end // 毛
        12: begin tone_freq = MI; note_beats = 1; end // 泽
        13: begin tone_freq = RE; note_beats = 1; end // 东
        14: begin tone_freq = DO; note_beats = 4; end // 完结长音
        
        // 第二段：中国出了个毛泽东
        15: begin tone_freq = SO; note_beats = 1; end
        16: begin tone_freq = LA; note_beats = 1; end
        17: begin tone_freq = DO; note_beats = 2; end
        18: begin tone_freq = LA; note_beats = 1; end
        19: begin tone_freq = SO; note_beats = 1; end
        20: begin tone_freq = MI; note_beats = 2; end
        
        21: begin tone_freq = RE; note_beats = 1; end
        22: begin tone_freq = MI; note_beats = 1; end
        23: begin tone_freq = SO; note_beats = 1; end
        24: begin tone_freq = MI; note_beats = 1; end
        25: begin tone_freq = RE; note_beats = 1; end
        26: begin tone_freq = DO; note_beats = 1; end
        27: begin tone_freq = LA; note_beats = 2; end
        28: begin tone_freq = SO; note_beats = 4; end // 全曲终长音
        
        default: begin tone_freq = 0; note_beats = 1; end
    endcase
end

// 当播放到最后一个音符，并且这个音符的拍数走完时，触发结束信号
assign song_end = (play_en && (note_num == 28) && (tone_cnt >= (note_beats * ONE_BEAT_CYCLES - 1)));

//================================================
// 音符时间与节拍控制
//================================================
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        tone_cnt <= 0;
        note_num <= 0;
    end
    else if(play_en) begin
        if(tone_cnt >= (note_beats * ONE_BEAT_CYCLES - 1)) begin
            tone_cnt <= 0;
            if(note_num < 28)
                note_num <= note_num + 1;
            else
                note_num <= 0; 
        end
        else begin
            tone_cnt <= tone_cnt + 1;
        end
    end
    else begin
        tone_cnt <= 0;
        note_num <= 0;
    end
end

//================================================
// 产生方波输出给蜂鸣器
//================================================
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        freq_cnt <= 0;
        beep <= 1'b1;
    end
    else if(play_en && tone_freq != 0) begin
        if(freq_cnt >= tone_freq) begin
            freq_cnt <= 0;
            beep <= ~beep; 
        end
        else begin
            freq_cnt <= freq_cnt + 1;
        end
    end
    else begin
        freq_cnt <= 0;
        beep <= 1'b1; 
    end
end

endmodule