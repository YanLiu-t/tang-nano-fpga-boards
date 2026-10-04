// mdio_slave_interface.v  -- ONLY FOR SIMULATION, DO NOT SYNTHESIS
module mdio_slave_interface
#(
    parameter PHY_ADDR = 5'b00001
)(
    input        mdc,
    inout        mdio
);

reg [4:0]  reg_addr;
reg [4:0]  phy_addr;
reg [15:0] reg_mem [0:31];
reg        mdio_out_en;
reg        mdio_out;

initial begin
    // PHY寄存器初始值，简单模拟PHY
    reg_mem[0]  = 16'h1140; // BMCR
    reg_mem[1]  = 16'h7849; // BMSR
    reg_mem[2]  = 16'h0000;
    reg_mem[3]  = 16'h0000;
    reg_mem[4]  = 16'h0de1;
    reg_mem[5]  = 16'h0000;
    reg_mem[6]  = 16'h0000;
    reg_mem[7]  = 16'h0000;
end

assign mdio = mdio_out_en ? mdio_out : 1'bz;

localparam IDLE     = 0;
localparam PREAMBLE = 1;
localparam START    = 2;
localparam OP       = 3;
localparam PHYAD    = 4;
localparam REGAD    = 5;
localparam TA       = 6;
localparam DATA     = 7;

reg [3:0] state;
reg [5:0] bit_cnt;
reg [1:0] op_code;

always @(posedge mdc) begin
    if(state == IDLE) begin
        mdio_out_en <= 1'b0;
        bit_cnt <= 0;
        if(mdio === 1'b1) begin
            state <= PREAMBLE;
        end
    end
    else if(state == PREAMBLE) begin
        bit_cnt <= bit_cnt + 1'b1;
        if(bit_cnt >= 31) begin
            bit_cnt <= 0;
            state <= START;
        end
    end
    else if(state == START) begin
        bit_cnt <= bit_cnt + 1'b1;
        if(bit_cnt == 1) begin
            bit_cnt <= 0;
            op_code[1] <= mdio;
            state <= OP;
        end
    end
    else if(state == OP) begin
        op_code[0] <= mdio;
        bit_cnt <= 0;
        state <= PHYAD;
    end
    else if(state == PHYAD) begin
        phy_addr[4 - bit_cnt] <= mdio;
        bit_cnt <= bit_cnt + 1'b1;
        if(bit_cnt == 4) begin
            bit_cnt <= 0;
            state <= REGAD;
        end
    end
    else if(state == REGAD) begin
        reg_addr[4 - bit_cnt] <= mdio;
        bit_cnt <= bit_cnt + 1'b1;
        if(bit_cnt == 4) begin
            bit_cnt <= 0;
            state <= TA;
        end
    end
    else if(state == TA) begin
        if(op_code == 2'b10) begin // read
            mdio_out_en <= 1'b1;
            mdio_out <= 1'b0;
        end else begin // write
            mdio_out_en <= 1'b0;
        end
        bit_cnt <= 0;
        state <= DATA;
    end
    else if(state == DATA) begin
        bit_cnt <= bit_cnt + 1'b1;
        if(op_code == 2'b01) begin // write
            reg_mem[reg_addr][15-bit_cnt] <= mdio;
            mdio_out_en <= 1'b0;
        end
        else begin // read
            mdio_out_en <= 1'b1;
            mdio_out <= reg_mem[reg_addr][15-bit_cnt];
        end
        if(bit_cnt == 15) begin
            state <= IDLE;
            mdio_out_en <= 1'b0;
        end
    end
end

endmodule
