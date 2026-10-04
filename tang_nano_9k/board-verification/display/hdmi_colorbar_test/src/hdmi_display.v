module hdmi_display(
    input  wire         clk_pixel,
    input  wire         rst_n,
    output reg  [23:0]  video_data,
    output reg          video_hsync,
    output reg          video_vsync,
    output reg          video_de
);

    localparam H_TOTAL  = 858;
    localparam H_ACTIVE = 720;
    localparam H_SYNC   = 62;
    localparam H_FRONT  = 16;

    localparam V_TOTAL  = 525;
    localparam V_ACTIVE = 480;
    localparam V_SYNC   = 6;
    localparam V_FRONT  = 9;

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 0;
            v_cnt <= 0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 0;
                else
                    v_cnt <= v_cnt + 1;
            end else begin
                h_cnt <= h_cnt + 1;
            end
        end
    end

    wire h_active = (h_cnt < H_ACTIVE);
    wire v_active = (v_cnt < V_ACTIVE);
    wire h_sync   = (h_cnt >= (H_ACTIVE + H_FRONT)) && (h_cnt < (H_ACTIVE + H_FRONT + H_SYNC));
    wire v_sync   = (v_cnt >= (V_ACTIVE + V_FRONT)) && (v_cnt < (V_ACTIVE + V_FRONT + V_SYNC));

    always @(posedge clk_pixel) begin
        video_hsync <= ~h_sync;
        video_vsync <= ~v_sync;
        video_de    <= h_active && v_active;
    end

    wire [1:0] bar = (h_cnt < 240) ? 2'd0 : (h_cnt < 480) ? 2'd1 : 2'd2;

    always @(posedge clk_pixel) begin
        case (bar)
            2'd0: video_data <= {8'hFF, 8'h00, 8'h00}; // 红
            2'd1: video_data <= {8'h00, 8'hFF, 8'h00}; // 绿
            2'd2: video_data <= {8'h00, 8'h00, 8'hFF}; // 蓝
        endcase
    end

endmodule