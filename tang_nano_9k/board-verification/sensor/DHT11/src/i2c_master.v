module i2c_master(
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        i2c_start,
    input  wire [15:0] i2c_data, // 高8位控制字(0x00/0x40)，低8位数据
    output reg         i2c_done,
    output wire        i2c_scl,
    inout  wire        i2c_sda
);
    parameter C_DIV = 6'd130;
    reg [5:0] cnt;
    reg [6:0] state;
    reg scl_r, sda_out, sda_dir;
    reg [23:0] s_data;
    
    assign i2c_scl = scl_r;
    assign i2c_sda = sda_dir ? sda_out : 1'bz;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            cnt<=0; state<=0; scl_r<=1; sda_out<=1; sda_dir<=1; i2c_done<=0;
        end else begin
            if(i2c_start && state==0) begin
                state <= 1; s_data <= {8'h7E, i2c_data}; // 0x78 是 OLED 默认设备地址
            end
            if(state != 0) begin
                cnt <= cnt + 1;
                if(cnt == C_DIV) begin
                    cnt <= 0;
                    case(state)
                        1: begin sda_dir<=1; sda_out<=0; state<=2; end // START: SCL=1, SDA=0
                        2: begin scl_r<=0; state<=3; end               // SCL=0
                        // 循环发送 3 字节 (Device Addr -> Control -> Data)
                        3,6,9,12,15,18,21,24: begin sda_out<=s_data[23 - (state-3)/3]; state<=state+1; end
                        4,7,10,13,16,19,22,25: begin scl_r<=1; state<=state+1; end
                        5,8,11,14,17,20,23,26: begin scl_r<=0; state<=state+1; end
                        27: begin sda_dir<=0; state<=28; end // ACK 1
                        28: begin scl_r<=1; state<=29; end
                        29: begin scl_r<=0; state<=30; end
                        30,33,36,39,42,45,48,51: begin sda_dir<=1; sda_out<=s_data[15 - (state-30)/3]; state<=state+1; end
                        31,34,37,40,43,46,49,52: begin scl_r<=1; state<=state+1; end
                        32,35,38,41,44,47,50,53: begin scl_r<=0; state<=state+1; end
                        54: begin sda_dir<=0; state<=55; end // ACK 2
                        55: begin scl_r<=1; state<=56; end
                        56: begin scl_r<=0; state<=57; end
                        57,60,63,66,69,72,75,78: begin sda_dir<=1; sda_out<=s_data[7 - (state-57)/3]; state<=state+1; end
                        58,61,64,67,70,73,76,79: begin scl_r<=1; state<=state+1; end
                        59,62,65,68,71,74,77,80: begin scl_r<=0; state<=state+1; end
                        81: begin sda_dir<=0; state<=82; end // ACK 3
                        82: begin scl_r<=1; state<=83; end
                        83: begin scl_r<=0; state<=84; end
                        // STOP
                        84: begin sda_dir<=1; sda_out<=0; state<=85; end
                        85: begin scl_r<=1; state<=86; end
                        86: begin sda_out<=1; state<=87; end
                        87: begin i2c_done<=1; state<=88; end
                        88: begin i2c_done<=0; state<=0; end
                    endcase
                end
            end
        end
    end
endmodule