module lcd_driver(
input pixel_clock,           //像素的时钟
input reset_n,               //复位的信号
input [15:0]lcd_id,          //HDMI型号(分辨率)的信号
input [23:0]pixel_data,      //传入的像素的数据
input en_cnt,                //h_cnt 和 v_cnt 计数器使能信号
//rgb888转DVI接口的信号
output reg lcd_de,           //HDMI 数据使能信号
output reg lcd_hs,           //HDMI 行同步信号
output reg lcd_vs,           //HDMI 场同步信号
output [23:0]lcd_rgb,        //HDMI RGB888 颜色数据
//给psram写数据的指引信号
output reg vs_begin,         //场有效数据开始信号
//用于fifo读数据的标记信号
output reg fifo_read_go      //从fifo申请32个24位宽的数据的信号
);

//parameter define 


//适用于480p 60hz的一些处理rgb888数据的重要参数
//关系:H_TOTAL_480p = H_SYNC_480p + H_BACK_480p + H_DISP_480p + H_FRONT_480p
parameter H_SYNC_480p = 11'd96;    //行同步        (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
parameter H_BACK_480p = 11'd48;   //行显示后沿     (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
parameter H_DISP_480p = 11'd640;  //行有效数据     (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
parameter H_FRONT_480p = 11'd16;  //行显示前沿     (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
parameter H_TOTAL_480p = 11'd800; //行扫描的总周期  (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
 
//关系:
parameter V_SYNC_480p = 11'd2;     //场同步        (单位为行扫描的总周期,比如说40就是40个行同步的总周期)
parameter V_BACK_480p = 11'd33;    //场显示后沿     (单位为行扫描的总周期,比如说40就是40个行同步的总周期)
parameter V_DISP_480p = 11'd480;   //场有效数据     (单位为行扫描的总周期,比如说40就是40个行同步的总周期) 
parameter V_FRONT_480p = 11'd10;    //场显示前沿     (单位为行扫描的总周期,比如说40就是40个行同步的总周期) 
parameter V_TOTAL_480p = 11'd525;  //场扫描总周期     (单位为行扫描的总周期,比如说40就是40个行同步的总周期) 



//reg define
//对于rgb888数据定义的重要参数的reg型的变量（根据hdmi不同的分辨率会不同）
reg [10:0] h_sync ;         //行同步        (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
reg [10:0] h_back ;         //行显示后沿     (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
reg [10:0] h_total;         //行扫描的总周期  (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
reg [10:0] h_disp;          //行有效数据     (单位为像素的时钟周期,比如说40就是40个像素时钟周期)    //LCD 屏水平分辨率
reg [10:0] v_sync ;         //场同步        (单位为行扫描的总周期,比如说40就是40个行同步的总周期)
reg [10:0] v_back ;         //场显示后沿     (单位为行扫描的总周期,比如说40就是40个行同步的总周期)
reg [10:0] v_total;         //场扫描总周期     (单位为行扫描的总周期,比如说40就是40个行同步的总周期) 
reg [10:0] v_disp;          //场有效数据     (单位为行扫描的总周期,比如说40就是40个行同步的总周期)   //LCD 屏垂直分辨率
reg [10:0] h_cnt ;          //对于行扫描的周期的计数器(以像素时钟为单位)
reg [10:0] v_cnt ;          //对于场扫描的周期的计数器(以行扫描的总周期为单位)

//reg en_cnt;    



//#############################
//***  main code  ************
//#############################

//行场时序参数
always @(*) begin
//根据不同的分辨率让参数变量赋不同的值的逻辑
case(lcd_id)
    //hdmi的720p分辨率的赋值逻辑
    16'h480: begin
        h_sync = H_SYNC_480p;   //行同步        (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
        h_back = H_BACK_480p;   //行显示后沿     (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
        h_disp = H_DISP_480p;   //行有效数据     (单位为像素的时钟周期,比如说40就是40个像素时钟周期)    //LCD 屏水平分辨率
        h_total = H_TOTAL_480p; //行扫描的总周期  (单位为像素的时钟周期,比如说40就是40个像素时钟周期)
        v_sync = V_SYNC_480p;   //场同步        (单位为行扫描的总周期,比如说40就是40个行同步的总周期)
        v_back = V_BACK_480p;   //场显示后沿     (单位为行扫描的总周期,比如说40就是40个行同步的总周期)
        v_disp = V_DISP_480p;   //场有效数据     (单位为行扫描的总周期,比如说40就是40个行同步的总周期)   //LCD 屏垂直分辨率
        v_total = V_TOTAL_480p; //场扫描总周期     (单位为行扫描的总周期,比如说40就是40个行同步的总周期) 
    end
    //默认值(和上述赋值一样)
    default: begin
        h_sync = H_SYNC_480p;
        h_back = H_BACK_480p;
        h_disp = H_DISP_480p;
        h_total = H_TOTAL_480p;
        v_sync = V_SYNC_480p;
        v_back = V_BACK_480p;
        v_disp = V_DISP_480p;
        v_total = V_TOTAL_480p; 
    end
endcase
end



//开始读27个fifo读数据的数据单位的信号
always@(posedge pixel_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //开始情况下将其复位
        fifo_read_go <= 1'b0;
    end
    //在场有效的区间内
    else if((v_cnt >= v_sync + v_back) & (v_cnt < v_sync + v_back + v_disp))begin
        //根据我设计的时序，在特定的时间打开数据申请信号
        if((((h_cnt - h_sync - h_back + 11'd4) % 32) == 1'b0) & (h_cnt >= (h_sync + h_back - 11'd4)) & (h_cnt < (h_sync + h_back + 11'd630)))begin
            fifo_read_go <= 1'b1;
        end
        else begin
            //一个时钟沿之后关闭
            fifo_read_go <= 1'b0;
        end
    end
    else begin
        //在场无效时就将其置为0
        fifo_read_go <= 1'b0;
    end
end


//场有效数据的开始信号
always@(posedge pixel_clock , negedge reset_n)begin
    if(reset_n == 1'b0)begin
        //复位置零
        vs_begin <= 1'b0;
    end
    //在场有效信号前一段取一个位置，将其拉高
    else if((v_cnt == 11'b0) & (h_cnt == (h_sync + h_back + h_disp - 11'd2)))begin
        vs_begin <= 1'b1;
    end
    //拉高一个时钟周期之后，将其拉低
    else begin
        vs_begin <= 1'b0;
    end
end



//行同步信号的实现逻辑
always@(posedge pixel_clock , negedge reset_n)begin
    if(reset_n == 1'b0)
        //复位时复位为0
        lcd_hs <= 1'b1;
    //当行计数器一旦计满或是开始状态，就使lcd_hs有效
    else if((h_cnt == (h_total - 1)) | (en_cnt == 1'b0))
        lcd_hs <= 1'b0;
    //当行同步计满时，在将其置回无效
    else if(h_cnt == h_sync - 11'b1) 
        lcd_hs <= 1'b1;
    //其他情况下其值不变
    else
        lcd_hs <= lcd_hs;
end

//场同步信号的实现逻辑
always@(posedge pixel_clock , negedge reset_n)begin
    if(reset_n == 1'b0)
        //复位时复位为0
        lcd_vs <= 1'b1;
    //当行和场计数器都计满或是开始状态时，将lcd_vs置为有效
    else if(((h_cnt == (h_total - 1)) & (v_cnt == (v_total - 1))) | (en_cnt == 1'b0))
        lcd_vs <= 1'b0;
    //当场同步计满且行计数器计满时，在将其置回无效
    else if((h_cnt == (h_total - 1)) & (v_cnt == (v_sync - 1)))
        lcd_vs <= 1'b1;
    //其他情况下其值不变
    else 
        lcd_vs <= lcd_vs;
end


//行计数器实现逻辑
always@(posedge pixel_clock , negedge reset_n)begin
    if(reset_n == 1'b0)
        //将行计数器复位为0
        h_cnt <= 11'b0;
    //计数器使能信号打开后在启动行计数器
    else if(en_cnt)begin
        //当行计数器计满到行扫描的总周期时清零
        if(h_cnt == (h_total - 1))
            h_cnt <= 11'b0;
        //否则一直让其加一
        else
            h_cnt <= h_cnt + 11'b1;
    //当使能不打开时，一直为0
    end
    else 
        h_cnt <= 11'b0;
end

//场计数器实现逻辑
always@(posedge pixel_clock , negedge reset_n)begin
    if(reset_n == 1'b0)
        //将场计数器复位为0
        v_cnt <= 1'b0;
    //当行计数器计满到行扫描的总周期时执行一次场扫描计数器
    else if(h_cnt == (h_total - 1))begin
        //当行计数器计满到行扫描的总周期时清零
        if(v_cnt == (v_total - 1))
            v_cnt <= 11'b0;
        //否则就一直给其加一
        else
            v_cnt <= v_cnt + 11'b1;
    end
    //其他情况下默认场计数器不变
    else
        v_cnt <= v_cnt;
end


always@(posedge pixel_clock , negedge reset_n)begin
    if(reset_n == 1'b0)
        //复位时给其复位0
        lcd_de <= 1'b0;
    //在场同步信号的有效数据的范围内，才打开data_req信号
    else if((v_cnt >= v_sync + v_back) & (v_cnt < v_sync + v_back + v_disp))
        //在到行有效数据的前一个周期就把data_req拉高
        if((h_cnt == h_sync + h_back - 1))
            lcd_de <= 1'b1; 
        //在到行有效数据结束的前一个周期就把data_req拉低
        else if((h_cnt == h_sync + h_back + h_disp- 1))
            lcd_de <= 1'b0;
        //其他情况下，让其保持不变
        else
            lcd_de <= lcd_de;
    //不然就将其置为0
    else
        lcd_de <= 1'b0;
end

//根据de有效信号来过滤传进来的数据
assign lcd_rgb = (lcd_de ? pixel_data : 24'bz);


endmodule