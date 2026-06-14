`timescale 1 ns / 1 ps

module seven_segment_controller (
    input  logic       CLK,
    input  logic       RST, // Active-low asynchronous reset
    input  logic [2:0] state_i,
    input  logic [3:0] predicted_digit_i,
    input  logic       predicted_valid_i,
    output logic [6:0] seg_o, // Cathode segments (A..G) - active low
    output logic       dp_o,  // Decimal point - active low
    output logic [3:0] an_o   // Digit anodes - active low
);

    // Refresh rate counter (100 MHz clock divided to ~400 Hz for multiplexing)
    // 100 MHz / 400 Hz / 4 digits = 62,500 cycles per digit.
    // 16-bit counter is sufficient (62,500 < 65,536).
    logic [15:0] refresh_cnt_r;
    logic [1:0]  active_digit_r;

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            refresh_cnt_r  <= 16'd0;
            active_digit_r <= 2'd0;
        end else begin
            if (refresh_cnt_r == 16'd62499) begin
                refresh_cnt_r  <= 16'd0;
                active_digit_r <= active_digit_r + 2'd1;
            end else begin
                refresh_cnt_r <= refresh_cnt_r + 16'd1;
            end
        end
    end

    // Seven segment character generator (active-low)
    logic [6:0] state_char_w;
    logic [6:0] digit_char_w;

    // Decode state character (Digit 3)
    always_comb begin
        if (predicted_valid_i) begin
            state_char_w = 7'b0100001; // 'd' for DONE
        end else begin
            case (state_i)
                3'd0:    state_char_w = 7'b1111001; // 'I' for IDLE (segments B, C)
                3'd1:    state_char_w = 7'b1100011; // 'L' for LOAD
                3'd2:    state_char_w = 7'b0001110; // 'F' for FETCH
                3'd3:    state_char_w = 7'b0001100; // 'P' for DECODE/PROCESSING
                3'd4:    state_char_w = 7'b0000110; // 'E' for EXECUTE
                3'd5:    state_char_w = 7'b0010010; // 'S' for READ/STATUS (like 'S')
                default: state_char_w = 7'b1111111; // Blank
            endcase
        end
    end

    // Decode predicted digit display (Digit 0)
    always_comb begin
        if (predicted_valid_i) begin
            case (predicted_digit_i)
                4'd0:    digit_char_w = 7'b1000000; // '0'
                4'd1:    digit_char_w = 7'b1111001; // '1'
                4'd2:    digit_char_w = 7'b0100100; // '2'
                4'd3:    digit_char_w = 7'b0110000; // '3'
                4'd4:    digit_char_w = 7'b0011001; // '4'
                4'd5:    digit_char_w = 7'b0010010; // '5'
                4'd6:    digit_char_w = 7'b0000010; // '6'
                4'd7:    digit_char_w = 7'b1111000; // '7'
                4'd8:    digit_char_w = 7'b0000000; // '8'
                4'd9:    digit_char_w = 7'b0010000; // '9'
                default: digit_char_w = 7'b0111111; // Dash '-'
            endcase
        end else begin
            digit_char_w = 7'b1111111; // Blank
        end
    end

    // Anode and Cathode multiplexer
    always_comb begin
        dp_o = 1'b1; // Decimal points always off (active-low)
        case (active_digit_r)
            2'd0: begin
                an_o  = 4'b0111; // Digit 3 active (leftmost)
                seg_o = state_char_w;
            end
            2'd1: begin
                an_o  = 4'b1011; // Digit 2 active
                seg_o = 7'b0111111; // Dash '-'
            end
            2'd2: begin
                an_o  = 4'b1101; // Digit 1 active
                seg_o = 7'b0111111; // Dash '-'
            end
            2'd3: begin
                an_o  = 4'b1110; // Digit 0 active (rightmost)
                seg_o = digit_char_w;
            end
            default: begin
                an_o  = 4'b1111;
                seg_o = 7'b1111111;
            end
        endcase
    end

endmodule
