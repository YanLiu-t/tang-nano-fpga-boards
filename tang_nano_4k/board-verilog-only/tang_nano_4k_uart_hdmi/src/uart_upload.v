//============================================================================
// uart_upload.v - Pure-Verilog UART image uploader (replaces M3 + C code)
//============================================================================
//
// PC --UART 921600 8N1--> uart_rx -> 每 4 字节打包 1 个 32-bit 词 (MSB first)
//   -> 电平握手 (out_req/out_ack toggle) 送入 top.v 的 HyperRAM 写打包 FSM
//   -> 收满 230400 词 (921600 字节 = 一帧 640x480 RGB888) 后拉高 out_start
//      (等价 C 固件写 CTRL=1), HDMI 开始显示。
//
// TX (921600 8N1): 串口平时保持静默 ——
//   - 上电后不发任何数据 (取消原来的 1.05s 周期状态包);
//   - 接收期间也不回显、不发进度字符;
//   - 只在整个 640x480 帧接收完成时发一个 0xAA 作为"收帧完成"标志,
//     发完之后串口再次静默。
//
// 时钟: 27MHz 晶振, 32 位相位累加 NCO 产生精确 16x 过采样 tick
//   (14.7456MHz), 波特率误差 ~0.003ppm。
//
// RX 抗噪: 2 级同步 + 下降沿启动 + 停止位必须为高 (线常低时不会产生
// 0x00 风暴, 表现为完全收不到字节, 便于区分"短路/断开")。
//============================================================================

`timescale 1ns / 1ps

//============================================================================
// UART RX, 16x oversampled, 8N1, LSB first
//============================================================================
module uart_rx (
    input  wire       clk,
    input  wire       rstn,
    input  wire       tick,       // 16x baud tick, 1-cycle pulse
    input  wire       rxd,
    output reg  [7:0] rx_data,
    output reg        rx_valid    // 1-cycle pulse when a frame is received
);
    reg s0, s1, s2;
    reg [3:0] tcnt;               // 0..15, ticks inside current bit
    reg [3:0] bcnt;               // 0..7 data bits
    reg [1:0] state;

    localparam R_IDLE  = 2'd0;
    localparam R_START = 2'd1;
    localparam R_DATA  = 2'd2;
    localparam R_STOP  = 2'd3;

    wire fall = s2 & ~s1;         // synchronized falling edge

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s0 <= 1'b1; s1 <= 1'b1; s2 <= 1'b1;
        end else begin
            s0 <= rxd; s1 <= s0; s2 <= s1;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state   <= R_IDLE;
            tcnt    <= 4'd0;
            bcnt    <= 4'd0;
            rx_data <= 8'd0;
            rx_valid<= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
            R_IDLE: begin
                if (fall) begin
                    state <= R_START;
                    tcnt  <= 4'd0;
                end
            end

            // center of start bit ~8 ticks after the detected edge
            R_START: if (tick) begin
                if (tcnt == 4'd7) begin
                    if (s1 == 1'b0) begin
                        state <= R_DATA;      // valid start
                        bcnt  <= 4'd0;
                    end else begin
                        state <= R_IDLE;      // spike / false start
                    end
                    tcnt <= 4'd0;
                end else begin
                    tcnt <= tcnt + 4'd1;
                end
            end

            R_DATA: if (tick) begin
                if (tcnt == 4'd15) begin
                    rx_data <= {s1, rx_data[7:1]};  // LSB first
                    tcnt <= 4'd0;
                    if (bcnt == 4'd7)
                        state <= R_STOP;
                    else
                        bcnt <= bcnt + 4'd1;
                end else begin
                    tcnt <= tcnt + 4'd1;
                end
            end

            // stop bit must be high; framing error (line stuck low) -> drop
            R_STOP: if (tick) begin
                if (tcnt == 4'd15) begin
                    state <= R_IDLE;
                    if (s1 == 1'b1)
                        rx_valid <= 1'b1;
                end else begin
                    tcnt <= tcnt + 4'd1;
                end
            end
            endcase
        end
    end
endmodule

//============================================================================
// UART TX, 8N1, LSB first. Start accepted only in idle (!tx_busy).
//============================================================================
module uart_tx (
    input  wire       clk,
    input  wire       rstn,
    input  wire       tick,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        txd,
    output wire       tx_busy
);
    reg [1:0] state;
    reg [3:0] tcnt;
    reg [3:0] bcnt;               // 0..9 = start+8data+stop
    reg [9:0] sh;                 // {stop, data[7:0], start}

    localparam T_IDLE  = 2'd0;
    localparam T_SEND  = 2'd1;

    assign tx_busy = (state != T_IDLE);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= T_IDLE;
            tcnt  <= 4'd0;
            bcnt  <= 4'd0;
            sh    <= 10'b1111111111;
            txd   <= 1'b1;
        end else begin
            case (state)
            T_IDLE: begin
                txd <= 1'b1;
                if (tx_start) begin
                    sh    <= {1'b1, tx_data, 1'b0};
                    txd   <= 1'b0;            // start bit
                    tcnt  <= 4'd0;
                    bcnt  <= 4'd0;
                    state <= T_SEND;
                end
            end

            T_SEND: if (tick) begin
                if (tcnt == 4'd15) begin
                    tcnt <= 4'd0;
                    txd  <= sh[1];
                    sh   <= {1'b1, sh[9:1]};
                    if (bcnt == 4'd9) begin
                        state <= T_IDLE;       // final (stop) bit done
                    end else begin
                        bcnt <= bcnt + 4'd1;
                    end
                end else begin
                    tcnt <= tcnt + 4'd1;
                end
            end
            endcase
        end
    end
endmodule

//============================================================================
// Upload engine
//============================================================================
module uart_upload #(
    parameter integer CLK_HZ     = 27000000,
    parameter integer BAUD       = 921600,
    parameter integer FRAME_WORDS = 230400     // 921600 bytes / 4
) (
    input  wire        clk,
    input  wire        rstn,

    input  wire        rxd,
    output wire        txd,

    // image word stream handshake (consumed by top.v write FSM)
    output reg  [31:0] out_data,
    output reg         out_req,     // toggles per accepted word
    output reg         out_start,   // level: display start
    input  wire        out_ack,     // toggles per consumed word (other domain)

    // HyperRAM-side status (clk_out domain, reported in status packet)
    input  wire        hp_init,     // IP init/calibration done
    input  wire        hp_busy,     // controller burst in progress
    input  wire        hp_wact,     // top.v write FSM not idle

    // Display/storage measurements. Kept as a port for now but not
    // transmitted anywhere: the status packet was removed so the line stays
    // silent (see the header comment).
    input  wire [7:0]  hp_rd_status
);
    //------------------------------------------------------------------
    // 16x baud NCO: step = round(16*BAUD / CLK_HZ * 2^26)
    //   27MHz @921600 -> 36650387 (tick 14.74559998MHz, -0.016ppm)
    //------------------------------------------------------------------
    localparam signed [63:0] NCO_STEP_FULL =
        ((64'd16 * BAUD) * 64'h0000000004000000) / CLK_HZ;  // *2^26
    localparam [25:0] NCO_STEP = NCO_STEP_FULL[25:0];
    reg  [25:0] nco_acc;
    wire        nco_tick = (nco_acc + NCO_STEP < nco_acc);
    always @(posedge clk or negedge rstn) begin
        if (!rstn) nco_acc <= 32'd0;
        else       nco_acc <= nco_acc + NCO_STEP;
    end

    //------------------------------------------------------------------
    // UARTs
    //------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    uart_rx u_rx (
        .clk(clk), .rstn(rstn), .tick(nco_tick), .rxd(rxd),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    uart_tx u_tx (
        .clk(clk), .rstn(rstn), .tick(nco_tick),
        .tx_start(tx_start), .tx_data(tx_data),
        .txd(txd), .tx_busy(tx_busy)
    );

    //------------------------------------------------------------------
    // out_ack 2-flop synchronizer (hp_clkout -> clk)
    //------------------------------------------------------------------
    reg ack_s0, ack_s1;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin ack_s0 <= 1'b0; ack_s1 <= 1'b0; end
        else     begin ack_s0 <= out_ack; ack_s1 <= ack_s0; end
    end

    //------------------------------------------------------------------
    // HyperRAM status sync (diagnostics only)
    //------------------------------------------------------------------
    reg init_s0, init_s1, busy_s0, busy_s1, wact_s0, wact_s1;
    reg [7:0] rs_s0, rs_s1;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            {init_s0, init_s1, busy_s0, busy_s1, wact_s0, wact_s1} <= 6'b0;
            rs_s0 <= 8'b0; rs_s1 <= 8'b0;
        end else begin
            init_s0 <= hp_init; init_s1 <= init_s0;
            busy_s0 <= hp_busy; busy_s1 <= busy_s0;
            wact_s0 <= hp_wact; wact_s1 <= wact_s0;
            rs_s0   <= hp_rd_status; rs_s1 <= rs_s0;
        end
    end

    //------------------------------------------------------------------
    // Packing + word handshake
    //   bytes shift into `word`; every 4th byte submits one 32-bit word.
    //   Only ONE word may be in flight (hs_busy). A word completing while
    //   the previous one is still un-acked is HELD in pend_word (never
    //   dropped) and dispatched right after the ack.
    //------------------------------------------------------------------
    reg [31:0] word;
    reg [1:0]  byte_cnt;
    reg        hs_busy;             // word in flight, waiting for ack
    reg [31:0] pend_word;
    reg        pend;                // completed word awaiting dispatch
    reg [17:0] word_cnt;            // 0..230399
    reg        frame_done;
    reg        rx_seen;

    //------------------------------------------------------------------
    // TX message slot: 0xAA at frame end (one shot). Nothing else is ever
    // transmitted, so the line stays silent before the upload and silent
    // again once the frame has been received.
    //------------------------------------------------------------------
    reg        aa_pend;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            out_data  <= 32'd0;
            out_req   <= 1'b0;
            out_start <= 1'b0;
            word       <= 32'd0;
            byte_cnt   <= 2'd0;
            hs_busy    <= 1'b0;
            pend_word  <= 32'd0;
            pend       <= 1'b0;
            word_cnt   <= 18'd0;
            frame_done <= 1'b0;
            rx_seen    <= 1'b0;
            aa_pend    <= 1'b0;
            tx_start   <= 1'b0;
            tx_data    <= 8'd0;
        end else begin
            tx_start <= 1'b0;            // default pulse

            //----------------------------------------------------------
            // RX byte: pack (packing gated after done)
            //----------------------------------------------------------
            if (rx_valid) begin
                rx_seen   <= 1'b1;

                if (!frame_done) begin
                    word     <= {word[23:0], rx_data};   // MSB = first byte
                    byte_cnt <= byte_cnt + 2'd1;
                    if (byte_cnt == 2'd3) begin
                        if (!hs_busy && !pend) begin
                            out_data <= {word[23:0], rx_data};
                            out_req  <= ~out_req;        // submit word
                            hs_busy  <= 1'b1;
                        end else begin
                            pend_word <= {word[23:0], rx_data};
                            pend      <= 1'b1;           // hold, never drop
                        end
                    end
                end
            end

            //----------------------------------------------------------
            // Word accepted by the HyperRAM write path (ack toggle seen)
            //----------------------------------------------------------
            if (hs_busy && (ack_s1 == out_req)) begin
                hs_busy <= 1'b0;
                if (word_cnt == FRAME_WORDS - 1) begin
                    frame_done <= 1'b1;
                    out_start  <= 1'b1;                  // CTRL=1
                    aa_pend    <= 1'b1;                  // report 0xAA
                    pend       <= 1'b0;                  // discard extras
                end else begin
                    word_cnt <= word_cnt + 18'd1;
                end
            end

            //----------------------------------------------------------
            // Dispatch a held word once the previous one is acked
            //----------------------------------------------------------
            if (!hs_busy && pend && !frame_done) begin
                out_data <= pend_word;
                out_req  <= ~out_req;
                hs_busy  <= 1'b1;
                pend     <= 1'b0;
            end

            //----------------------------------------------------------
            // No periodic status packet. The only TX activity in the whole
            // design is the single 0xAA sent when the frame completes, so the
            // line is silent from power-on (before the upload) and silent
            // again as soon as that byte is out.

            //----------------------------------------------------------
            // TX arbiter: the one-shot 0xAA and nothing else.
            //----------------------------------------------------------
            if (!tx_busy && !tx_start && aa_pend) begin
                tx_start <= 1'b1;
                tx_data  <= 8'hAA;
                aa_pend  <= 1'b0;
            end
        end
    end
endmodule
