module oled_i2c(

    input wire clk,
    input wire rst_n,


    input wire start,

    input wire [7:0] data,

    output reg busy,

    output reg done,


    output reg scl,

    output reg sda


);


reg [7:0] data_reg;

reg [3:0] state;

reg [15:0] cnt;

reg [3:0] bit_cnt;



parameter

IDLE  = 4'd0,
START = 4'd1,
SEND  = 4'd2,
STOP  = 4'd3;



//27MHz分频

//约100kHz I2C


always @(posedge clk or negedge rst_n)

begin


if(!rst_n)

begin

    scl<=1;

    sda<=1;

    busy<=0;

    done<=0;

    state<=IDLE;

    cnt<=0;

end


else

begin


done<=0;



case(state)



//--------------------------------

IDLE:

begin

    scl<=1;
    sda<=1;


    if(start)

    begin

        busy<=1;

        data_reg<=data;

        bit_cnt<=0;

        state<=START;

    end

end



//--------------------------------

START:

begin

    sda<=0;

    scl<=1;


    state<=SEND;


end



//--------------------------------

SEND:

begin



    scl<=0;


    sda<=data_reg[7-bit_cnt];



    cnt<=cnt+1;


    if(cnt==16'd135)

    begin

        cnt<=0;


        scl<=1;


        if(bit_cnt==7)

        begin

            state<=STOP;

        end


        else

        begin

            bit_cnt<=bit_cnt+1;

        end


    end


end




//--------------------------------

STOP:

begin


    scl<=1;

    sda<=0;


    cnt<=cnt+1;


    if(cnt==16'd135)

    begin

        sda<=1;

        busy<=0;

        done<=1;

        cnt<=0;

        state<=IDLE;

    end


end



default:

state<=IDLE;



endcase


end


end


endmodule