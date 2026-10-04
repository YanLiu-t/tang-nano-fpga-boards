module key_filter(
    Clk,
    Reset_n,
    Key,
    Key_P_Flag,
    Key_R_Flag,
    key_state
);

    input Reset_n;
    input Clk;
    input Key;
    output reg Key_P_Flag;
    output reg Key_R_Flag;
    output reg key_state;

    reg r_Key;
    reg sync_d0_Key;
    reg sync_d1_Key;

    wire pedge_Key;
    wire nedge_Key;
    wire time_20ms_reached;

    reg [2:0]state;
    reg [29:0]cnt;

    localparam IDLE=0;
    localparam P_FILTER=1;
    localparam WAIT_R=2;
    localparam R_FILTER=3;

    parameter MCNT=1000_000-1;

//
    always@(posedge Clk)
        sync_d0_Key<=Key;

    always@(posedge Clk)
        sync_d1_Key<=sync_d0_Key;

   always@(posedge Clk)
        r_Key<=sync_d1_Key;

    assign nedge_Key=(sync_d1_Key==0)&&(r_Key==1);

    assign pedge_Key=(sync_d1_Key==1)&&(r_Key==0);

//    always@(posedge Clk or negedge Reset_n)
//    if(!Reset_n)
//        cnt<=0;
//    else if((state==P_FILTER)||(state==R_FILTER))
//        cnt<=cnt+1'd1;
//    else
//        cnt<=0;

    assign time_20ms_reached=cnt>=MCNT;
//
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        begin
            state<=IDLE;
            Key_P_Flag<=1'd0;
            Key_R_Flag<=1'd0;
            cnt<=1'd0;
            key_state<=1;
        end
    else begin
        case(state)
            IDLE:
            begin
                Key_R_Flag=1'd0;
                if(nedge_Key)
                    state<=P_FILTER;
            end
            P_FILTER:
                if(time_20ms_reached) begin
                    state<=WAIT_R;
                    Key_P_Flag<=1'd1;
                    key_state<=0;
                    cnt<=0;
                    end
                else if(pedge_Key) begin
                    state<=IDLE;
                    cnt<=0;
                end
                else
                    state<=state;
            WAIT_R:
                begin
                    Key_P_Flag=1'd0;
                if(pedge_Key)
                    state<=R_FILTER;
                end
            R_FILTER:
                if(time_20ms_reached) begin
                    state<=IDLE;
                    Key_R_Flag=1'd1;
                    key_state<=1;
                    cnt<=0;
                    end
                else if(nedge_Key) begin
                    state<=WAIT_R;
                    cnt<=0;
                    end
                else begin
                    state<=state;
                    cnt<=cnt+1'b1;
                end
        endcase
    end
endmodule