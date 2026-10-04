module dht11_ctrl(

    input wire clk,
    input wire rst_n,

    inout wire dht11,


    output reg [7:0] temperature,
    output reg [7:0] humidity,

    output reg valid

);


//27MHz
//一个周期约37ns


reg dht_out;
reg dht_dir;


assign dht11 = dht_dir ? dht_out : 1'bz;



reg [2:0] state;


reg [21:0] cnt;


reg [5:0] bit_cnt;


reg [39:0] data_buf;



parameter

IDLE  = 3'd0,
START = 3'd1,
WAIT  = 3'd2,
READ  = 3'd3,
DONE  = 3'd4;



//下降沿检测

reg dht_reg1;
reg dht_reg2;

wire dht_negedge;


always @(posedge clk)
begin

    dht_reg1 <= dht11;
    dht_reg2 <= dht_reg1;

end


assign dht_negedge =
        dht_reg2 & (~dht_reg1);





always @(posedge clk or negedge rst_n)
begin


if(!rst_n)
begin

    state <= IDLE;

    dht_dir <= 1'b1;

    dht_out <= 1'b1;


    cnt <=0;

    bit_cnt<=0;


    data_buf<=0;


    temperature<=0;

    humidity<=0;

    valid<=0;

end



else
begin


valid<=0;



case(state)



//--------------------------------
// 空闲
//--------------------------------

IDLE:
begin

    dht_dir<=1;
    dht_out<=1;


    cnt<=cnt+1;



    //约1秒采一次

    if(cnt>22'd27000000)

    begin

        cnt<=0;

        state<=START;

    end


end



//--------------------------------
// 发送18ms低电平
//--------------------------------

START:
begin


    dht_dir<=1;

    dht_out<=0;



    cnt<=cnt+1;



    if(cnt>22'd486000)

    begin

        cnt<=0;

        dht_dir<=0;

        state<=WAIT;

    end


end




//--------------------------------
// 等待DHT响应
//--------------------------------

WAIT:

begin


    if(dht_negedge)

    begin

        bit_cnt<=0;

        cnt<=0;

        state<=READ;

    end


end




//--------------------------------
// 读取数据
//--------------------------------

READ:

begin


    if(dht_negedge)

    begin


        //判断高电平时间

        if(cnt > 22'd1100)

        begin

            data_buf <=

            {data_buf[38:0],1'b1};

        end


        else

        begin

            data_buf <=

            {data_buf[38:0],1'b0};

        end



        bit_cnt<=bit_cnt+1;

        cnt<=0;



        if(bit_cnt==6'd39)

        begin

            state<=DONE;

        end


    end


    else

    begin

        cnt<=cnt+1;

    end



end





//--------------------------------
// 数据完成
//--------------------------------


DONE:

begin



humidity <= data_buf[39:32];


temperature <= data_buf[23:16];


valid<=1;


state<=IDLE;



end



default:

state<=IDLE;



endcase



end



end


endmodule