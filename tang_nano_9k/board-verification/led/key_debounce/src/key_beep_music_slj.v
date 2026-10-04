module key_beep_music_slj(
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
// 音符表 (基于 27MHz 系统时钟)
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

// 基础拍子时钟周期数：27MHz * 0.3秒 = 8,100,000 (节奏更轻快)
parameter ONE_BEAT_CYCLES = 32'd8100000; 

//================================================
// 一闪一闪亮晶晶 音符与节拍选择
//================================================
always @(*) begin
    case(note_num)
        // 1 1 5 5 | 6 6 5 - (一闪一闪亮晶晶)
        0:  begin tone_freq = DO; note_beats = 1; end
        1:  begin tone_freq = DO; note_beats = 1; end
        2:  begin tone_freq = SO; note_beats = 1; end
        3:  begin tone_freq = SO; note_beats = 1; end
        4:  begin tone_freq = LA; note_beats = 1; end
        5:  begin tone_freq = LA; note_beats = 1; end
        6:  begin tone_freq = SO; note_beats = 2; end // 晶~ (长音)

        // 4 4 3 3 | 2 2 1 - (满天都是小星星)
        7:  begin tone_freq = FA; note_beats = 1; end
        8:  begin tone_freq = FA; note_beats = 1; end
        9:  begin tone_freq = MI; note_beats = 1; end
        10: begin tone_freq = MI; note_beats = 1; end
        11: begin tone_freq = RE; note_beats = 1; end
        12: begin tone_freq = RE; note_beats = 1; end
        13: begin tone_freq = DO; note_beats = 2; end // 星~ (长音)

        // 5 5 4 4 | 3 3 2 - (挂在天上放光明)
        14: begin tone_freq = SO; note_beats = 1; end
        15: begin tone_freq = SO; note_beats = 1; end
        16: begin tone_freq = FA; note_beats = 1; end
        17: begin tone_freq = FA; note_beats = 1; end
        18: begin tone_freq = MI; note_beats = 1; end
        19: begin tone_freq = MI; note_beats = 1; end
        20: begin tone_freq = RE; note_beats = 2; end // 明~ (长音)

        // 5 5 4 4 | 3 3 2 - (好像许多小眼睛)
        21: begin tone_freq = SO; note_beats = 1; end
        22: begin tone_freq = SO; note_beats = 1; end
        23: begin tone_freq = FA; note_beats = 1; end
        24: begin tone_freq = FA; note_beats = 1; end
        25: begin tone_freq = MI; note_beats = 1; end
        26: begin tone_freq = MI; note_beats = 1; end
        27: begin tone_freq = RE; note_beats = 2; end // 睛~ (长音)

        // 1 1 5 5 | 6 6 5 - (一闪一闪亮晶晶)
        28: begin tone_freq = DO; note_beats = 1; end
        29: begin tone_freq = DO; note_beats = 1; end
        30: begin tone_freq = SO; note_beats = 1; end
        31: begin tone_freq = SO; note_beats = 1; end
        32: begin tone_freq = LA; note_beats = 1; end
        33: begin tone_freq = LA; note_beats = 1; end
        34: begin tone_freq = SO; note_beats = 2; end // 晶~ (长音)

        // 4 4 3 3 | 2 2 1 - (满天都是小星星)
        35: begin tone_freq = FA; note_beats = 1; end
        36: begin tone_freq = FA; note_beats = 1; end
        37: begin tone_freq = MI; note_beats = 1; end
        38: begin tone_freq = MI; note_beats = 1; end
        39: begin tone_freq = RE; note_beats = 1; end
        40: begin tone_freq = RE; note_beats = 1; end
        41: begin tone_freq = DO; note_beats = 4; end // 结尾长音，余音绕梁
        
        default: begin tone_freq = 0; note_beats = 1; end
    endcase
end

// 索引上限改为 41 (总共 42 个音符)
assign song_end = (play_en && (note_num == 41) && (tone_cnt >= (note_beats * ONE_BEAT_CYCLES - 1)));

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
            // 索引上限同步改为 41
            if(note_num < 41)
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
        // 这里增加一个断音处理：在每个音符即将结束的一小段时间(比如拍子的最后一小段)，停止发声
        // 这样两个连续相同的音符(比如 DO DO)听起来就是分开的，不会连成一个长音，更加流畅清晰。
        if (tone_cnt > (note_beats * ONE_BEAT_CYCLES - 32'd400000)) begin
             beep <= 1'b1; // 强制静音，产生音符间隔
        end
        else if(freq_cnt >= tone_freq) begin
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