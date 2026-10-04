module oled_font(

    input  wire [7:0] ascii,

    input  wire [3:0] row,

    output reg [7:0] data


);


always @(*)

begin


case(ascii)



//====================
// 数字0
//====================

8'h30:

case(row)

0:data=8'b00111100;
1:data=8'b01100110;
2:data=8'b01100110;
3:data=8'b01100110;
4:data=8'b01100110;
5:data=8'b01100110;
6:data=8'b01100110;
7:data=8'b00111100;

8:data=8'b00000000;
9:data=8'b00000000;
10:data=8'b00000000;
11:data=8'b00000000;
12:data=8'b00000000;
13:data=8'b00000000;
14:data=8'b00000000;
15:data=8'b00000000;

default:data=0;

endcase




//====================
// 数字1
//====================

8'h31:

case(row)

0:data=8'b00011000;
1:data=8'b00111000;
2:data=8'b00011000;
3:data=8'b00011000;
4:data=8'b00011000;
5:data=8'b00011000;
6:data=8'b00011000;
7:data=8'b01111110;

8:data=0;
9:data=0;
10:data=0;
11:data=0;
12:data=0;
13:data=0;
14:data=0;
15:data=0;

default:data=0;

endcase





//====================
// 数字2
//====================

8'h32:

case(row)

0:data=8'b00111100;
1:data=8'b01100110;
2:data=8'b00000110;
3:data=8'b00001100;
4:data=8'b00110000;
5:data=8'b01100000;
6:data=8'b01100110;
7:data=8'b01111110;

8:data=0;
9:data=0;
10:data=0;
11:data=0;
12:data=0;
13:data=0;
14:data=0;
15:data=0;

default:data=0;

endcase



//====================
// 数字3
//====================

8'h33:

case(row)

0:data=8'b00111100;
1:data=8'b01100110;
2:data=8'b00000110;
3:data=8'b00011100;
4:data=8'b00000110;
5:data=8'b00000110;
6:data=8'b01100110;
7:data=8'b00111100;

8:data=0;
9:data=0;
10:data=0;
11:data=0;
12:data=0;
13:data=0;
14:data=0;
15:data=0;

default:data=0;

endcase




//====================
// T
//====================

"T":

case(row)

0:data=8'b11111111;
1:data=8'b00011000;
2:data=8'b00011000;
3:data=8'b00011000;
4:data=8'b00011000;
5:data=8'b00011000;
6:data=8'b00011000;
7:data=8'b00011000;

8:data=0;
9:data=0;
10:data=0;
11:data=0;
12:data=0;
13:data=0;
14:data=0;
15:data=0;

default:data=0;

endcase



//====================
// E
//====================

"E":

case(row)

0:data=8'b11111110;
1:data=8'b11000000;
2:data=8'b11000000;
3:data=8'b11111100;
4:data=8'b11000000;
5:data=8'b11000000;
6:data=8'b11000000;
7:data=8'b11111110;

default:data=0;

endcase

8'h4D:      // M
case(row)

0:data=8'b11000011;
1:data=8'b11100111;
2:data=8'b11111111;
3:data=8'b11011011;
4:data=8'b11000011;
5:data=8'b11000011;
6:data=8'b11000011;
7:data=8'b11000011;

default:data=0;

endcase

8'h50:      // P
case(row)

0:data=8'b11111100;
1:data=8'b11000110;
2:data=8'b11000110;
3:data=8'b11111100;
4:data=8'b11000000;
5:data=8'b11000000;
6:data=8'b11000000;
7:data=8'b11000000;

default:data=0;

endcase

8'h48:      // H
case(row)

0:data=8'b11000011;
1:data=8'b11000011;
2:data=8'b11000011;
3:data=8'b11111111;
4:data=8'b11000011;
5:data=8'b11000011;
6:data=8'b11000011;
7:data=8'b11000011;

default:data=0;

endcase

8'h55:      // U
case(row)

0:data=8'b11000011;
1:data=8'b11000011;
2:data=8'b11000011;
3:data=8'b11000011;
4:data=8'b11000011;
5:data=8'b11000011;
6:data=8'b01100110;
7:data=8'b00111100;

default:data=0;

endcase

8'h49:      // I
case(row)

0:data=8'b11111111;
1:data=8'b00011000;
2:data=8'b00011000;
3:data=8'b00011000;
4:data=8'b00011000;
5:data=8'b00011000;
6:data=8'b00011000;
7:data=8'b11111111;

default:data=0;

endcase

8'h3A:

case(row)

0:data=0;
1:data=0;
2:data=8'b00011000;
3:data=8'b00011000;
4:data=0;
5:data=0;
6:data=8'b00011000;
7:data=8'b00011000;

default:data=0;

endcase

8'h43:

case(row)

0:data=8'b00111110;
1:data=8'b01100000;
2:data=8'b11000000;
3:data=8'b11000000;
4:data=8'b11000000;
5:data=8'b11000000;
6:data=8'b01100000;
7:data=8'b00111110;

default:data=0;

endcase
8'h25:

case(row)

0:data=8'b11000001;
1:data=8'b11000010;
2:data=8'b00000100;
3:data=8'b00001000;
4:data=8'b00010000;
5:data=8'b00100000;
6:data=8'b01000011;
7:data=8'b10000011;

default:data=0;

endcase
//====================
// 空白
//====================

default:

data=8'b00000000;



endcase


end


endmodule