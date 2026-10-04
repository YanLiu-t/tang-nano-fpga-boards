module led_twinkle_4(
  Clk,
  Reset_n,
  Led

);
   input Clk;
   input Reset_n;
   output [3:0]Led;
led_twinkle led_twinkle_inst0(
    .Clk(Clk),
    .Reset_n(Reset_n), 
    .Led(Led[0])
);

led_twinkle#(.MCNT(12_499_999)
)
    led_twinkle_instl(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Led(Led[1])
);

led_twinkle led_twinkle_inst2 (
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Led (Led[2])
);

    defparam led_twinkle_inst2.MCNT = 6250000 - 1;

    led_twinkle led_twinkle_inst3(
    .Clk(Clk),
    .Reset_n(Reset_n),
    .Led(Led[3])
);
    defparam led_twinkle_inst3.MCNT = 2500000 - 1;


endmodule