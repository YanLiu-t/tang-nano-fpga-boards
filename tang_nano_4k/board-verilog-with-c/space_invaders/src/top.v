//============================================================================
// TOP MODULE - Pong for Tang Nano 4K (Cortex-M3 + Verilog co-design)
//============================================================================
// C 语言侧 (Cortex-M3 硬核, 跑在 Gowin EMPU 上): 游戏逻辑
// Verilog 侧: 显示驱动 (HDMI SVO 栈), 键盘采集 (74HC165), APB2 寄存器桥
//
// 时钟方案:
//   clk (27MHz 晶振) -> PLLVR -> clk_p5 (126MHz, TMDS 串行时钟)
//                         |-> CLKDIV (/5) -> clk_p (25.2MHz, 像素时钟)
//   master_pclk (27MHz, 来自 EMPU) : 键盘 + APB2 寄存器桥
//
//============================================================================
`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module top(
    //----------------------------------------------------------------------
    // Clock & Reset
    //----------------------------------------------------------------------
    input clk,              // 27 MHz from crystal
    input resetn,           // Reset button S1 (active low)

    //----------------------------------------------------------------------
    // Keyboard (74HC165 shift register)
    //----------------------------------------------------------------------
    output keyboard_pl,     // Parallel Load  (Pin 41)
    output keyboard_cp,     // Clock          (Pin 42)
    input  keyboard_q7,     // Serial Data    (Pin 43)

    //----------------------------------------------------------------------
    // UART (EMPU debug, optional)
    //----------------------------------------------------------------------
    input  uart0_rxd,       // Pin 39
    output uart0_txd,       // Pin 40

    //----------------------------------------------------------------------
    // HDMI Output (differential)
    //----------------------------------------------------------------------
    output tmds_clk_n,
    output tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

//============================================================================
// VIDEO PARAMETERS
//============================================================================
parameter SVO_MODE             = "640x480";
parameter SVO_FRAMERATE        = 60;
parameter SVO_BITS_PER_PIXEL   = 24;
parameter SVO_BITS_PER_RED     = 8;
parameter SVO_BITS_PER_GREEN   = 8;
parameter SVO_BITS_PER_BLUE    = 8;
parameter SVO_BITS_PER_ALPHA   = 0;

//============================================================================
// INTERNAL SIGNALS
//============================================================================
wire pll_lock;
wire clk_p5;            // 126 MHz (5x pixel clock)
wire clk_p;             // 25.2 MHz pixel clock
wire sys_resetn;        // clk_p domain reset
wire apb_resetn;        // master_pclk domain reset

//============================================================================
// PLL - Generate 126 MHz
//============================================================================
Gowin_PLLVR pll_inst (
    .clkout(clk_p5),
    .lock(pll_lock),
    .clkin(clk)
);

//============================================================================
// CLOCK DIVIDER - 126 MHz / 5 = 25.2 MHz
//============================================================================
Gowin_CLKDIV clkdiv_inst (
    .clkout(clk_p),
    .hclkin(clk_p5),
    .resetn(pll_lock)
);

//============================================================================
// RESET SYNC (pixel clock domain)
//============================================================================
Reset_Sync reset_sync_px (
    .resetn(sys_resetn),
    .ext_reset(resetn & pll_lock),
    .clk(clk_p)
);

//============================================================================
// EMPU (Cortex-M3) instantiation
//   master_prst polarity is not used: the fabric generates its own reset
//   for the APB domain (apb_resetn), so the register bridge and keyboard
//   run independently of the CPU soft reset state.
//============================================================================
wire master_pclk;
wire master_prst;
wire master_penable;
wire [7:0]  master_paddr;
wire master_pwrite;
wire [31:0] master_pwdata;
wire [3:0]  master_pstrb;
wire [2:0]  master_pprot;
wire master_psel1;
wire [31:0] master_prdata1;
wire master_pready1;
wire master_pslverr1;
wire [15:0] gpio_io;

Gowin_EMPU_Top u_empu (
    .sys_clk(clk),
    .gpio(gpio_io),
    .uart0_rxd(uart0_rxd),
    .uart0_txd(uart0_txd),
    .master_pclk(master_pclk),
    .master_prst(master_prst),
    .master_penable(master_penable),
    .master_paddr(master_paddr),
    .master_pwrite(master_pwrite),
    .master_pwdata(master_pwdata),
    .master_pstrb(master_pstrb),
    .master_pprot(master_pprot),
    .master_psel1(master_psel1),
    .master_prdata1(master_prdata1),
    .master_pready1(master_pready1),
    .master_pslverr1(master_pslverr1),
    .reset_n(resetn)
);

//============================================================================
// RESET SYNC (APB master_pclk domain, own fabric reset)
//============================================================================
Reset_Sync reset_sync_apb (
    .resetn(apb_resetn),
    .ext_reset(resetn & pll_lock),
    .clk(master_pclk)
);

//============================================================================
// KEYBOARD (74HC165) - Read 8 keys (master_pclk domain)
//============================================================================
wire [7:0] keys;
wire keys_valid;

keyboard_74hc165 u_keyboard (
    .clk    (master_pclk),
    .resetn (apb_resetn),
    .pl     (keyboard_pl),
    .cp     (keyboard_cp),
    .q7     (keyboard_q7),
    .keys   (keys),
    .valid  (keys_valid)
);

//============================================================================
// APB2 REGISTER BRIDGE (master_pclk domain)
//============================================================================
wire [11:0] p1_paddle, p2_paddle, ball_x, ball_y;
wire [6:0]  score1, score2;
wire [7:0]  ctrl;
wire [13:0] fb_addr;
wire [31:0] fb_data;
wire        fb_req;
wire        fb_ack;

apb_pong_reg u_apb_reg (
    .pclk      (master_pclk),
    .presetn   (apb_resetn),
    .psel      (master_psel1),
    .penable   (master_penable),
    .paddr     (master_paddr),
    .pwrite    (master_pwrite),
    .pwdata    (master_pwdata),
    .prdata    (master_prdata1),
    .pready    (master_pready1),
    .pslverr   (master_pslverr1),
    .keys_raw  (keys),
    .p1_paddle (p1_paddle),
    .p2_paddle (p2_paddle),
    .ball_x    (ball_x),
    .ball_y    (ball_y),
    .score1    (score1),
    .score2    (score2),
    .ctrl      (ctrl),
    .fb_addr   (fb_addr),
    .fb_data   (fb_data),
    .fb_req    (fb_req),
    .fb_ack    (fb_ack)
);

//============================================================================
// FRAMEBUFFER (clk_p domain) - firmware renders every pixel here
//============================================================================
wire fb_tvalid, fb_tready;
wire [SVO_BITS_PER_PIXEL-1:0] fb_tdata;
wire [0:0] fb_tuser;

framebuffer #( `SVO_PASS_PARAMS ) u_framebuffer (
    .clk   (clk_p),
    .resetn(sys_resetn),
    .wr_req (fb_req),
    .wr_addr(fb_addr),
    .wr_data(fb_data),
    .ack    (fb_ack),
    .out_axis_tvalid(fb_tvalid),
    .out_axis_tready(fb_tready),
    .out_axis_tdata (fb_tdata),
    .out_axis_tuser (fb_tuser)
);

//============================================================================
// SCORE-BLINK + WHOLE-SCREEN DIM (clk_p domain)
//   flash: 2-flop sync of ctrl[0] AND a ~0.75 Hz blink phase.
//   The final svo_dim stage halves every pixel when NOT flashing, so the
//   screen is half bright during play and blinks full bright on game over.
//============================================================================
reg fl_s, fl_ss;
always @(posedge clk_p) begin
    if (!sys_resetn) begin
        fl_s <= 0; fl_ss <= 0;
    end else begin
        fl_s  <= ctrl[0];
        fl_ss <= fl_s;
    end
end

reg [24:0] blink_cnt;
always @(posedge clk_p)
    blink_cnt <= blink_cnt + 1'b1;

wire flash = fl_ss && blink_cnt[23];

wire dim_tvalid, dim_tready;
wire [SVO_BITS_PER_PIXEL-1:0] dim_tdata;
wire [0:0] dim_tuser;

svo_dim #( `SVO_PASS_PARAMS ) dim_inst (
    .clk   (clk_p),
    .resetn(sys_resetn),
    .enable(!flash),
    .in_axis_tvalid(fb_tvalid),
    .in_axis_tready(fb_tready),
    .in_axis_tdata (fb_tdata),
    .in_axis_tuser (fb_tuser),
    .out_axis_tvalid(dim_tvalid),
    .out_axis_tready(dim_tready),
    .out_axis_tdata (dim_tdata),
    .out_axis_tuser (dim_tuser)
);

//============================================================================
// VIDEO ENCODER (timing HSync/VSync)
//============================================================================
wire enc_tvalid, enc_tready;
wire [SVO_BITS_PER_PIXEL-1:0] enc_tdata;
wire [3:0] enc_tuser;

svo_enc #( `SVO_PASS_PARAMS ) enc_inst (
    .clk(clk_p),
    .resetn(sys_resetn),
    .in_axis_tvalid(dim_tvalid),
    .in_axis_tready(dim_tready),
    .in_axis_tdata(dim_tdata),
    .in_axis_tuser(dim_tuser),
    .out_axis_tvalid(enc_tvalid),
    .out_axis_tready(enc_tready),
    .out_axis_tdata(enc_tdata),
    .out_axis_tuser(enc_tuser)
);
assign enc_tready = 1;

//============================================================================
// TMDS ENCODER (3 channels)
//============================================================================
wire [2:0] tmds_d;
wire [2:0] tmds_d0, tmds_d1, tmds_d2, tmds_d3, tmds_d4;
wire [2:0] tmds_d5, tmds_d6, tmds_d7, tmds_d8, tmds_d9;

// Channel 0: Blue + control
svo_tmds tmds_0 (
    .clk(clk_p),
    .resetn(sys_resetn),
    .de(!enc_tuser[3]),
    .ctrl(enc_tuser[2:1]),
    .din(enc_tdata[23:16]),
    .dout({tmds_d9[0], tmds_d8[0], tmds_d7[0], tmds_d6[0], tmds_d5[0],
           tmds_d4[0], tmds_d3[0], tmds_d2[0], tmds_d1[0], tmds_d0[0]})
);

// Channel 1: Green
svo_tmds tmds_1 (
    .clk(clk_p),
    .resetn(sys_resetn),
    .de(!enc_tuser[3]),
    .ctrl(2'b0),
    .din(enc_tdata[15:8]),
    .dout({tmds_d9[1], tmds_d8[1], tmds_d7[1], tmds_d6[1], tmds_d5[1],
           tmds_d4[1], tmds_d3[1], tmds_d2[1], tmds_d1[1], tmds_d0[1]})
);

// Channel 2: Red
svo_tmds tmds_2 (
    .clk(clk_p),
    .resetn(sys_resetn),
    .de(!enc_tuser[3]),
    .ctrl(2'b0),
    .din(enc_tdata[7:0]),
    .dout({tmds_d9[2], tmds_d8[2], tmds_d7[2], tmds_d6[2], tmds_d5[2],
           tmds_d4[2], tmds_d3[2], tmds_d2[2], tmds_d1[2], tmds_d0[2]})
);

//============================================================================
// SERIALIZER 10:1
//============================================================================
OSER10 tmds_serdes [2:0] (
    .Q(tmds_d),
    .D0(tmds_d0), .D1(tmds_d1), .D2(tmds_d2), .D3(tmds_d3), .D4(tmds_d4),
    .D5(tmds_d5), .D6(tmds_d6), .D7(tmds_d7), .D8(tmds_d8), .D9(tmds_d9),
    .PCLK(clk_p),
    .FCLK(clk_p5),
    .RESET(~sys_resetn)
);

//============================================================================
// OUTPUT BUFFER DIFFERENTIAL
//============================================================================
ELVDS_OBUF tmds_bufds [3:0] (
    .I({clk_p, tmds_d}),
    .O({tmds_clk_p, tmds_d_p}),
    .OB({tmds_clk_n, tmds_d_n})
);

endmodule


//============================================================================
// RESET SYNC
//============================================================================
module Reset_Sync (
    input clk,
    input ext_reset,
    output resetn
);
    reg [3:0] reset_cnt = 0;
    always @(posedge clk or negedge ext_reset) begin
        if (~ext_reset)
            reset_cnt <= 4'b0;
        else
            reset_cnt <= reset_cnt + !resetn;
    end
    assign resetn = &reset_cnt;
endmodule
