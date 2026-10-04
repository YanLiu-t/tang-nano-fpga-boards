module i2c_dri
#(
    parameter   SLAVE_ADDR = 7'h3c  ,
    parameter   CLK_FREQ   = 50_000_000,
    parameter   I2C_FREQ   = 250_000
)(
    input               clk         ,
    input               rst_n       ,

    input               i2c_exec    ,
    input               bit_ctrl    ,
    input               i2c_rh_wl   ,
    input       [15:0]  i2c_addr    ,
    input       [ 7:0]  i2c_data_w  ,
    output reg  [ 7:0]  i2c_data_r  ,
    output reg          i2c_done    ,

    output reg          scl         ,
    inout               sda         ,
    output              dri_clk
);

localparam  DIV_CNT = CLK_FREQ / I2C_FREQ / 4;

reg [7:0] cnt;
reg [3:0] state;
reg       sda_o;
reg       sda_en;

assign sda    = sda_en ? sda_o : 1'bz;
assign dri_clk = cnt[2];

localparam IDLE     = 4'd0;
localparam START    = 4'd1;
localparam WR_ADDR  = 4'd2;
localparam WR_REG_H = 4'd3;
localparam WR_REG_L = 4'd4;
localparam WR_DATA  = 4'd5;
localparam RD_DATA  = 4'd6;
localparam STOP     = 4'd7;

reg [7:0] shift_buf;
reg [3:0] bit_cnt;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt         <= 8'd0;
        state       <= IDLE;
        scl         <= 1'b1;
        sda_o       <= 1'b1;
        sda_en      <= 1'b1;
        i2c_done    <= 1'b0;
        i2c_data_r  <= 8'd0;
        shift_buf   <= 8'd0;
        bit_cnt     <= 4'd0;
    end
    else begin
        cnt <= cnt + 1'b1;
        i2c_done <= 1'b0;

        case(state)
            IDLE: begin
                cnt <= 8'd0;
                scl <= 1'b1;
                sda_o <= 1'b1;
                sda_en <= 1'b1;
                if(i2c_exec) begin
                    state <= START;
                    shift_buf <= {SLAVE_ADDR,1'b0};
                end
            end

            START: begin
                if(cnt >= DIV_CNT) begin
                    cnt <= 8'd0;
                    sda_o <= 1'b0;
                    if(cnt == DIV_CNT) begin
                        state <= WR_ADDR;
                        bit_cnt <= 4'd7;
                    end
                end
            end

            WR_ADDR: begin
                if(cnt >= DIV_CNT) begin
                    cnt <= 8'd0;
                    scl <= ~scl;
                    if(scl == 1'b0) begin
                        sda_o <= shift_buf[bit_cnt];
                        if(bit_cnt == 0) begin
                            if(bit_ctrl) begin
                                state <= WR_REG_H;
                                shift_buf <= i2c_addr[15:8];
                            end
                            else begin
                                state <= WR_REG_L;
                                shift_buf <= i2c_addr[7:0];
                            end
                            bit_cnt <= 4'd7;
                        end
                        else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end
            end

            WR_REG_H: begin
                if(cnt >= DIV_CNT) begin
                    cnt <= 8'd0;
                    scl <= ~scl;
                    if(scl == 1'b0) begin
                        sda_o <= shift_buf[bit_cnt];
                        if(bit_cnt == 0) begin
                            state <= WR_REG_L;
                            shift_buf <= i2c_addr[7:0];
                            bit_cnt <= 4'd7;
                        end
                        else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end
            end

            WR_REG_L: begin
                if(cnt >= DIV_CNT) begin
                    cnt <= 8'd0;
                    scl <= ~scl;
                    if(scl == 1'b0) begin
                        sda_o <= shift_buf[bit_cnt];
                        if(bit_cnt == 0) begin
                            if(i2c_rh_wl) begin
                                state <= START;
                                shift_buf <= {SLAVE_ADDR,1'b1};
                            end
                            else begin
                                state <= WR_DATA;
                                shift_buf <= i2c_data_w;
                            end
                            bit_cnt <= 4'd7;
                        end
                        else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end
            end

            WR_DATA: begin
                if(cnt >= DIV_CNT) begin
                    cnt <= 8'd0;
                    scl <= ~scl;
                    if(scl == 1'b0) begin
                        sda_o <= shift_buf[bit_cnt];
                        if(bit_cnt == 0) begin
                            state <= STOP;
                        end
                        else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end
            end

            RD_DATA: begin
                sda_en <= 1'b0;
                if(cnt >= DIV_CNT) begin
                    cnt <= 8'd0;
                    scl <= ~scl;
                    if(scl == 1'b1) begin
                        shift_buf[bit_cnt] <= sda;
                        if(bit_cnt == 0) begin
                            i2c_data_r <= shift_buf;
                            state <= STOP;
                        end
                        else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end
            end

            STOP: begin
                sda_en <= 1'b1;
                if(cnt >= DIV_CNT) begin
                    cnt <= 8'd0;
                    scl <= 1'b1;
                    if(cnt == DIV_CNT) begin
                        sda_o <= 1'b1;
                        i2c_done <= 1'b1;
                        state <= IDLE;
                    end
                end
            end
        endcase
    end
end

endmodule
