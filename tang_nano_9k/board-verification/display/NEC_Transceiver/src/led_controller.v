module led_controller(
    input clk,             
    input rst_n,           
    input [7:0] key_val,   
    input key_valid,       
    
    output reg red_led,    
    output reg green_led   
);

    parameter TIME_300MS = 8_100_000;
    reg [23:0] timer;
    wire tick = (timer == TIME_300MS - 1);

    parameter S_OFF        = 3'd0;
    parameter S_RED_ON     = 3'd1;
    parameter S_GREEN_ON   = 3'd2;
    parameter S_RED_BLINK  = 3'd3;
    parameter S_GREEN_BLINK= 3'd4;
    parameter S_ALT_BLINK  = 3'd5;

    reg [2:0] state;         
    reg [1:0] target_blinks; 
    reg [1:0] blink_cnt;     
    reg led_status;          

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer <= 0;
            state <= S_OFF;
            target_blinks <= 0;
            blink_cnt <= 0;
            led_status <= 0;
        end else if (key_valid) begin
            // 新按键打断一切当前状态
            timer <= 0;
            blink_cnt <= 0;
            led_status <= 1; 
            
            case (key_val)
                8'h19: begin state <= S_RED_ON; end                           
                8'h31: begin state <= S_GREEN_ON; end                         
                8'hbd: begin state <= S_RED_BLINK;   target_blinks <= 1; end  
                8'h11: begin state <= S_GREEN_BLINK; target_blinks <= 1; end  
                8'h39: begin state <= S_RED_BLINK;   target_blinks <= 2; end  
                8'hb5: begin state <= S_GREEN_BLINK; target_blinks <= 2; end  
                8'h85: begin state <= S_RED_BLINK;   target_blinks <= 3; end  
                8'hA5: begin state <= S_GREEN_BLINK; target_blinks <= 3; end  
                8'h95: begin state <= S_ALT_BLINK; end                        
                default: ; 
            endcase
            
        end else begin
            if (state != S_OFF && state != S_RED_ON && state != S_GREEN_ON) begin
                if (tick) begin
                    timer <= 0;
                    if (state == S_RED_BLINK || state == S_GREEN_BLINK) begin
                        if (led_status == 1'b1) begin
                            led_status <= 1'b0; 
                        end else begin
                            if (blink_cnt + 1 >= target_blinks) begin
                                state <= S_OFF; 
                            end else begin
                                blink_cnt <= blink_cnt + 1; 
                                led_status <= 1'b1;         
                            end
                        end
                    end else if (state == S_ALT_BLINK) begin
                        led_status <= ~led_status; 
                    end
                end else begin
                    timer <= timer + 1;
                end
            end else begin
                timer <= 0; 
            end
        end
    end

    always @(*) begin
        red_led = 1'b0;
        green_led = 1'b0;
        case (state)
            S_RED_ON:      red_led = 1'b1;
            S_GREEN_ON:    green_led = 1'b1;
            S_RED_BLINK:   red_led = led_status;
            S_GREEN_BLINK: green_led = led_status;
            S_ALT_BLINK: begin
                red_led = led_status;
                green_led = ~led_status;
            end
            default: ; 
        endcase
    end
endmodule
