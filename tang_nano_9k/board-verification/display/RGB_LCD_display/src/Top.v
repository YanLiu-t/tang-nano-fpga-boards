module TOP(
    input clk_27m,
    input nRST,
    output LCD_DE,
    output LCD_HSYNC,
    output LCD_VSYNC,
    output [4:0]LCD_B,
    output [5:0]LCD_G,
    output [4:0]LCD_R,
    output LCD_PCLK
);

wire PixelClk;

Gowin_rPLL u_pll(
    .clkin(clk_27m),
    .clkout(PixelClk)
);

assign LCD_PCLK =PixelClk;

VGA_timing u_timing(
    .PixelClk(PixelClk),
    .nRST(nRST),
    .LCD_DE(LCD_DE),
    .LCD_HSYNC(LCD_HSYNC),
    .LCD_VSYNC(LCD_VSYNC),
    .LCD_B(LCD_B),
    .LCD_G(LCD_G),
    .LCD_R(LCD_R)
);
endmodule