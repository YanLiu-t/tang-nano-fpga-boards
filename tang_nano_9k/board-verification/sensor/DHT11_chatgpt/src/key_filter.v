module key_filter(

    input  wire clk,       //27MHz
    input  wire rst_n,

    input  wire key_in,

    output reg  key_out

);


reg key_reg1;
reg key_reg2;


reg [19:0] cnt;


//------------------------------------------------
// 两级同步
//------------------------------------------------

always @(posedge clk or negedge rst_n)
begin

    if(!rst_n)
    begin
        key_reg1 <= 1'b1;
        key_reg2 <= 1'b1;
    end

    else
    begin

        key_reg1 <= key_in;
        key_reg2 <= key_reg1;

    end

end



//------------------------------------------------
// 消抖
// 27MHz
// 20bit计数约38ms
//------------------------------------------------


always @(posedge clk or negedge rst_n)
begin

    if(!rst_n)
    begin

        cnt <= 0;
        key_out <= 0;

    end


    else
    begin


        key_out <= 0;



        //检测按下
        if(key_reg2 == 1'b0)
        begin

            if(cnt < 20'd1000000)

                cnt <= cnt + 1;


            else
            begin

                cnt <= cnt;


                //产生一次脉冲
                key_out <= 1'b1;

            end

        end


        else
        begin

            cnt <= 0;

        end


    end


end


endmodule