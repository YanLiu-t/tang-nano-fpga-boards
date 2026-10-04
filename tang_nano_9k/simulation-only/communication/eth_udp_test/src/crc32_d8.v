module crc32_d8(
input               clk,
input               rst_n,

input      [7:0]    data,        //输入8位待校验数据
input               crc_en,      //CRC计算使能
input               crc_clr,     //CRC寄存器异步清零

output reg [31:0]   crc_data,    //CRC寄存器当前值
output reg [31:0]   crc_next     //CRC下一次计算输出
);

// CRC32 多项式 0x04C11DB7
always @(*) begin
    crc_next[0]  = crc_data[24] ^ data[0] ^ crc_data[30] ^ data[6];
    crc_next[1]  = crc_data[25] ^ data[1] ^ crc_data[31] ^ data[7] ^ crc_data[30] ^ data[6];
    crc_next[2]  = crc_data[26] ^ data[2] ^ crc_data[31] ^ data[7] ^ crc_data[24] ^ data[0] ^ crc_data[30] ^ data[6];
    crc_next[3]  = crc_data[27] ^ data[3] ^ crc_data[25] ^ data[1] ^ crc_data[31] ^ data[7] ^ crc_data[24] ^ data[0];
    crc_next[4]  = crc_data[28] ^ data[4] ^ crc_data[26] ^ data[2] ^ crc_data[25] ^ data[1] ^ crc_data[30] ^ data[6];
    crc_next[5]  = crc_data[29] ^ data[5] ^ crc_data[27] ^ data[3] ^ crc_data[26] ^ data[2] ^ crc_data[31] ^ data[7] ^ crc_data[30] ^ data[6];
    crc_next[6]  = crc_data[30] ^ data[6] ^ crc_data[28] ^ data[4] ^ crc_data[27] ^ data[3] ^ crc_data[26] ^ data[2] ^ crc_data[31] ^ data[7];
    crc_next[7]  = crc_data[31] ^ data[7] ^ crc_data[29] ^ data[5] ^ crc_data[28] ^ data[4] ^ crc_data[27] ^ data[3] ^ crc_data[24] ^ data[0];
    crc_next[8]  = crc_data[0] ^ crc_data[29] ^ data[5] ^ crc_data[28] ^ data[4] ^ crc_data[25] ^ data[1] ^ crc_data[24] ^ data[0];
    crc_next[9]  = crc_data[1] ^ crc_data[30] ^ data[6] ^ crc_data[29] ^ data[5] ^ crc_data[26] ^ data[2] ^ crc_data[25] ^ data[1];
    crc_next[10] = crc_data[2] ^ crc_data[31] ^ data[7] ^ crc_data[30] ^ data[6] ^ crc_data[27] ^ data[3] ^ crc_data[26] ^ data[2];
    crc_next[11] = crc_data[3] ^ crc_data[31] ^ data[7] ^ crc_data[28] ^ data[4] ^ crc_data[27] ^ data[3];
    crc_next[12] = crc_data[4] ^ crc_data[29] ^ data[5] ^ crc_data[28] ^ data[4] ^ crc_data[24] ^ data[0] ^ crc_data[30] ^ data[6];
    crc_next[13] = crc_data[5] ^ crc_data[30] ^ data[6] ^ crc_data[29] ^ data[5] ^ crc_data[25] ^ data[1] ^ crc_data[31] ^ data[7];
    crc_next[14] = crc_data[6] ^ crc_data[31] ^ data[7] ^ crc_data[30] ^ data[6] ^ crc_data[26] ^ data[2];
    crc_next[15] = crc_data[7] ^ crc_data[31] ^ data[7] ^ crc_data[27] ^ data[3];
    crc_next[16] = crc_data[8] ^ crc_data[28] ^ data[4];
    crc_next[17] = crc_data[9] ^ crc_data[29] ^ data[5];
    crc_next[18] = crc_data[10] ^ crc_data[30] ^ data[6];
    crc_next[19] = crc_data[11] ^ crc_data[31] ^ data[7];
    crc_next[20] = crc_data[12];
    crc_next[21] = crc_data[13];
    crc_next[22] = crc_data[14] ^ crc_data[24] ^ data[0];
    crc_next[23] = crc_data[15] ^ crc_data[25] ^ data[1];
    crc_next[24] = crc_data[16] ^ crc_data[26] ^ data[2];
    crc_next[25] = crc_data[17] ^ crc_data[27] ^ data[3];
    crc_next[26] = crc_data[18] ^ crc_data[28] ^ data[4];
    crc_next[27] = crc_data[19] ^ crc_data[29] ^ data[5];
    crc_next[28] = crc_data[20] ^ crc_data[30] ^ data[6];
    crc_next[29] = crc_data[21] ^ crc_data[31] ^ data[7];
    crc_next[30] = crc_data[22];
    crc_next[31] = crc_data[23];
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        crc_data <= 32'hffffffff;
    end
    else if(crc_clr) begin
        crc_data <= 32'hffffffff;  //以太网CRC初始值全1
    end
    else if(crc_en) begin
        crc_data <= crc_next;
    end
    else begin
        crc_data <= crc_data;
    end
end

endmodule