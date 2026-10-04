module i2c_ov5640_rgb565_cfg
(
input        clk ,                     //时钟信号
input        rst_n ,                   //复位信号，低电平有效

input [7:0]  i2c_data_r,               //I2C 读出的数据
input        i2c_done ,                //I2C 寄存器配置完成信号
input [12:0] cmos_h_pixel ,
input [12:0] cmos_v_pixel ,
input [12:0] total_h_pixel,            //水平总像素大小
input [12:0] total_v_pixel,            //垂直总像素大小
input [12:0] y_addr_st,
input [12:0] y_addr_end,
output reg   i2c_exec ,                //I2C 触发执行信号
output reg [23:0] i2c_data ,           //I2C 要配置的地址与数据(高 16 位地址,低 8 位数据)
output reg   i2c_rh_wl,                //I2C 读写控制信号
output reg   init_done                 //初始化完成信号
);

//parameter define
localparam REG_NUM = 8'd250 ;           //总共需要配置的寄存器个数

//reg define
reg [12:0] start_init_cnt;              //等待延时计数器
reg [7:0]  init_reg_cnt ;               //寄存器配置个数计数器

//*****************************************************
//** main code
//*****************************************************

//clk 时钟配置成 250khz,周期为 4us 5000*4us = 20ms
//OV5640 上电到开始配置 IIC 至少等待 20ms
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        start_init_cnt <= 13'b0;
    else if(start_init_cnt < 13'd5000) begin
        start_init_cnt <= start_init_cnt + 1'b1;
    end
end

//寄存器配置个数计数
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        init_reg_cnt <= 8'd0;
    else if(i2c_exec)
        init_reg_cnt <= init_reg_cnt + 8'b1;
end

//i2c 触发执行信号
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        i2c_exec <= 1'b0;
    else if(start_init_cnt == 13'd4999)
        i2c_exec <= 1'b1;
    else if(i2c_done && (init_reg_cnt < REG_NUM))
        i2c_exec <= 1'b1;
    else
        i2c_exec <= 1'b0;
end

//配置 I2C 读写控制信号
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        i2c_rh_wl <= 1'b1;
    else if(init_reg_cnt == 8'd2)
        i2c_rh_wl <= 1'b0;
end

//初始化完成信号
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        init_done <= 1'b0;
    else if((init_reg_cnt == REG_NUM) && i2c_done)
        init_done <= 1'b1;
end

//配置寄存器地址与数据
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        i2c_data <= 24'b0;
    else begin
        case(init_reg_cnt)
        //先对寄存器进行软件复位，使寄存器恢复初始值
        //寄存器软件复位后，需要延时 1ms 才能配置其它寄存器
        8'd0 : i2c_data <= {16'h300a,8'h0};
        8'd1 : i2c_data <= {16'h300b,8'h0};
        8'd2 : i2c_data <= {16'h3008,8'h82}; //Bit[7]:复位 Bit[6]:电源休眠
        8'd3 : i2c_data <= {16'h3008,8'h02}; //正常工作模式
        8'd4 : i2c_data <= {16'h3103,8'h02}; //Bit[1]:1 PLL Clock
        //引脚输入/输出控制 FREX/VSYNC/HREF/PCLK/D[9:6]
        8'd5 : i2c_data <= {8'h30,8'h17,8'hff};
        //引脚输入/输出控制 D[5:0]/GPIO1/GPIO0
        8'd6 : i2c_data <= {16'h3018,8'hff};
        8'd7 : i2c_data <= {16'h3037,8'h13}; //PLL 分频控制
        8'd8 : i2c_data <= {16'h3108,8'h01}; //系统根分频器

//----------------此处省略中间大量寄存器配置case项----------------

        //系统时钟分频 Bit[7:4]:系统时钟分频 input clock =24Mhz, PCLK = 48Mhz
        8'd205: i2c_data <= {16'h3035,8'h11};
        8'd206: i2c_data <= {16'h3036,8'h3c}; //PLL 倍频
        8'd207: i2c_data <= {16'h3c07,8'h08};
        //时序控制 16'h3800~16'h3821
        8'd208: i2c_data <= {16'h3820,8'h46};
        8'd209: i2c_data <= {16'h3821,8'h01};
        8'd210: i2c_data <= {16'h3814,8'h31};
        8'd211: i2c_data <= {16'h3815,8'h31};
        //预缩放开窗口水平起始地址高 8 位
        8'd212: i2c_data <= {16'h3800,8'h00};
        //预缩放开窗口水平起始地址低 8 位
        8'd213: i2c_data <= {16'h3801,8'h00};
        //预缩放开窗口垂直起始地址高 8 位
        8'd214: i2c_data <= {16'h3802,{3'd0,y_addr_st[12:8]}};
        //预缩放开窗口垂直起始地址低 8 位
        8'd215: i2c_data <= {16'h3803,y_addr_st[7:0]};
        //预缩放开窗口水平截止地址高 8 位
        8'd216: i2c_data <= {16'h3804,8'h0a};
        //预缩放开窗口水平截止地址低 8 位
        8'd217: i2c_data <= {16'h3805,8'h3f};
        //预缩放开窗口垂直截止地址高 8 位
        8'd218: i2c_data <= {16'h3806,{3'd0,y_addr_end[12:8]}};
        //预缩放开窗口垂直截止地址低 8 位
        8'd219: i2c_data <= {16'h3807,y_addr_end[7:0]};
        //设置输出像素个数
        //DVP 输出水平像素点数高 4 位
        8'd220: i2c_data <= {16'h3808,{4'd0,cmos_h_pixel[11:8]}};
        //DVP 输出水平像素点数低 8 位
        8'd221: i2c_data <= {16'h3809,cmos_h_pixel[7:0]};
        //DVP 输出垂直像素点数高 3 位
        8'd222: i2c_data <= {16'h380a,{5'd0,cmos_v_pixel[10:8]}};
        //DVP 输出垂直像素点数低 8 位
        8'd223: i2c_data <= {16'h380b,cmos_v_pixel[7:0]};
        //水平总像素大小高 5 位
        8'd224: i2c_data <= {16'h380c,{3'd0,total_h_pixel[12:8]}};
        //水平总像素大小低 8 位
        8'd225: i2c_data <= {16'h380d,total_h_pixel[7:0]};
        //垂直总像素大小高 5 位
        8'd226: i2c_data <= {16'h380e,{3'd0,total_v_pixel[12:8]}};
        //垂直总像素大小低 8 位
        8'd227: i2c_data <= {16'h380f,total_v_pixel[7:0]};

//----------------此处省略中间寄存器配置case项----------------

        //彩条测试使能
        8'd245: i2c_data <= {16'h503d,8'h00}; //8'h00:正常模式 8'h80:彩条显示
        //测试闪光灯功能
        8'd246: i2c_data <= {16'h3016,8'h02};
        8'd247: i2c_data <= {16'h301c,8'h02};
        8'd248: i2c_data <= {16'h3019,8'h02}; //打开闪光灯
        8'd249: i2c_data <= {16'h3019,8'h00}; //关闭闪光灯
        //只读存储器,防止在 case 中没有列举的情况，之前的寄存器被重复改写
        default : i2c_data <= {16'h300a,8'h00}; //器件 ID 高 8 位
        endcase
    end
end

endmodule
