module ov5640_dri (
input        clk ,                 //时钟
input        rst_n ,               //复位信号,低电平有效
//摄像头接口
input        cam_pclk ,            //cmos 数据像素时钟
input        cam_vsync ,           //cmos 场同步信号
input        cam_href ,            //cmos 行同步信号
input [7:0]  cam_data ,            //cmos 数据
output reg   cam_rst_n ,           //cmos 复位信号，低电平有效
output reg   cam_pwdn ,            //cmos 电源休眠模式选择信号
output       cam_scl ,             //cmos SCCB_SCL 线
inout        cam_sda ,             //cmos SCCB_SDA 线
//摄像头分辨率配置接口
input [12:0] cmos_h_pixel ,        //水平方向分辨率
input [12:0] cmos_v_pixel ,        //垂直方向分辨率
input [12:0] total_h_pixel ,       //水平总像素大小
input [12:0] total_v_pixel ,       //垂直总像素大小
input [12:0] y_addr_st ,
input [12:0] y_addr_end ,
input        capture_start ,       //图像采集开始信号
output       cam_init_done ,       //摄像头初始化完成
//用户接口
output       cmos_frame_vsync,     //帧有效信号
output       cmos_frame_href ,     //行有效信号
output       cmos_frame_valid,     //数据有效使能信号
output [15:0]cmos_frame_data       //有效数据
);

//parameter define
parameter SLAVE_ADDR  = 7'h3c ;     //OV5640 7位器件地址
parameter BIT_CTRL    = 1'b1 ;      //OV5640 的字节地址为 16 位 0:8 位 1:16 位
parameter CLK_FREQ    = 27'd50_000_000 ; //i2c_dri 模块的驱动时钟频率
parameter I2C_FREQ    = 18'd250_000 ;    //I2C 的 SCL 时钟频率,不超过 400KHz

//wire difine
wire        i2c_exec ;              //I2C 触发执行信号
wire [23:0] i2c_data ;              //I2C 要配置的地址与数据(高 8 位地址,低 8 位数据)
wire        i2c_done ;              //I2C 寄存器配置完成信号
wire        i2c_dri_clk ;           //I2C 操作时钟
wire [ 7:0] i2c_data_r ;            //I2C 读出的数据
wire        i2c_rh_wl ;             //I2C 读写控制信号

reg [15:0] power_cnt;

//*****************************************************
//** main code
//*****************************************************
//OV5640上电复位时序
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        power_cnt <= 16'd0;
        cam_pwdn  <= 1'b1;
        cam_rst_n <= 1'b0;
    end
    else begin
        if(power_cnt < 16'd50000) begin
            power_cnt <= power_cnt + 1'b1;
        end
        else if(power_cnt == 16'd50000) begin
            cam_pwdn <= 1'b0;
            power_cnt <= power_cnt + 1'b1;
        end
        else if(power_cnt == 16'd80000) begin
            cam_rst_n <= 1'b1;
            power_cnt <= power_cnt + 1'b1;
        end
    end
end

//I2C 配置模块
i2c_ov5640_rgb565_cfg u_i2c_cfg(
.clk            (i2c_dri_clk),
.rst_n          (rst_n),
.i2c_exec       (i2c_exec),
.i2c_data       (i2c_data),
.i2c_rh_wl      (i2c_rh_wl),       //I2C 读写控制信号
.i2c_done       (i2c_done),
.i2c_data_r     (i2c_data_r),
.cmos_h_pixel   (cmos_h_pixel),     //CMOS 水平方向像素个数
.cmos_v_pixel   (cmos_v_pixel),     //CMOS 垂直方向像素个数
.total_h_pixel  (total_h_pixel),    //水平总像素大小
.total_v_pixel  (total_v_pixel),    //垂直总像素大小
.y_addr_st      (y_addr_st),
.y_addr_end     (y_addr_end),
.init_done      (cam_init_done)
);

//I2C 驱动模块
i2c_dri #(
.SLAVE_ADDR (SLAVE_ADDR),           //参数传递
.CLK_FREQ   (CLK_FREQ ),
.I2C_FREQ   (I2C_FREQ )
)
u_i2c_dri(
.clk        (clk),
.rst_n      (rst_n ),
.i2c_exec   (i2c_exec ),
.bit_ctrl   (BIT_CTRL ),
.i2c_rh_wl  (i2c_rh_wl),            //固定为 0，只用到了 IIC 驱动的写操作
.i2c_addr   (i2c_data[23:8]),
.i2c_data_w (i2c_data[7:0]),
.i2c_data_r (i2c_data_r),
.i2c_done   (i2c_done ),
.scl        (cam_scl ),
.sda        (cam_sda ),
.dri_clk    (i2c_dri_clk)           //I2C 操作时钟
);

//CMOS 图像数据采集模块
//注意：不再把 capture_start接复位，改为内部使能
cmos_capture_data u_cmos_capture_data(
.rst_n          (rst_n),
//.capture_start  (capture_start),
.cam_pclk       (cam_pclk),
.cam_vsync      (cam_vsync),
.cam_href       (cam_href),
.cam_data       (cam_data),
.cmos_frame_vsync (cmos_frame_vsync),
.cmos_frame_href  (cmos_frame_href ),
.cmos_frame_valid (cmos_frame_valid),
.cmos_frame_data  (cmos_frame_data )
);

endmodule
