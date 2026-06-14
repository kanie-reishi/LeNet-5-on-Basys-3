`timescale 1 ns / 1 ps

module uart_rx #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115200
)(
    input  logic       CLK,
    input  logic       RST, // Active-low asynchronous reset
    input  logic       rxd_i,
    output logic [7:0] rx_data_o,
    output logic       rx_valid_o
);

    // Divisor for Baud Rate (rounded to nearest integer)
    localparam int CLK_PER_BIT = (CLK_FREQ_HZ + BAUD_RATE/2) / BAUD_RATE;

    // FSM States
    typedef enum logic [1:0] {
        s_IDLE  = 2'd0,
        s_START = 2'd1,
        s_DATA  = 2'd2,
        s_STOP  = 2'd3
    } state_t;

    state_t state_r;
    
    // Counters
    logic [15:0] clk_cnt_r;
    logic [2:0]  bit_cnt_r;
    
    // Sync RXD to local clock (double registers to prevent metastability)
    logic rxd_sync0_r;
    logic rxd_sync1_r;
    
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            rxd_sync0_r <= 1'b1;
            rxd_sync1_r <= 1'b1;
        end else begin
            rxd_sync0_r <= rxd_i;
            rxd_sync1_r <= rxd_sync0_r;
        end
    end

    // Shift register for data
    logic [7:0] rx_shift_r;

    // Output Registers
    logic [7:0] rx_data_r;
    logic       rx_valid_r;

    assign rx_data_o  = rx_data_r;
    assign rx_valid_o = rx_valid_r;

    // Main FSM
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            state_r      <= s_IDLE;
            clk_cnt_r    <= 16'd0;
            bit_cnt_r    <= 3'd0;
            rx_shift_r   <= 8'd0;
            rx_data_r    <= 8'd0;
            rx_valid_r   <= 1'b0;
        end else begin
            rx_valid_r <= 1'b0; // default pulse

            case (state_r)
                s_IDLE: begin
                    clk_cnt_r <= 16'd0;
                    bit_cnt_r <= 3'd0;
                    // Detect falling edge of start bit
                    if (rxd_sync1_r == 1'b0) begin
                        state_r <= s_START;
                    end
                end

                s_START: begin
                    if (clk_cnt_r == (CLK_PER_BIT / 2) - 1) begin
                        // Check if rxd is still low (valid start bit)
                        if (rxd_sync1_r == 1'b0) begin
                            clk_cnt_r <= 16'd0;
                            state_r   <= s_DATA;
                        end else begin
                            state_r   <= s_IDLE; // False start bit
                        end
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 16'd1;
                    end
                end

                s_DATA: begin
                    if (clk_cnt_r == CLK_PER_BIT - 1) begin
                        clk_cnt_r  <= 16'd0;
                        rx_shift_r <= {rxd_sync1_r, rx_shift_r[7:1]}; // LSB first
                        
                        if (bit_cnt_r == 3'd7) begin
                            state_r <= s_STOP;
                        end else begin
                            bit_cnt_r <= bit_cnt_r + 3'd1;
                        end
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 16'd1;
                    end
                end

                s_STOP: begin
                    if (clk_cnt_r == CLK_PER_BIT - 1) begin
                        // Valid stop bit is high
                        if (rxd_sync1_r == 1'b1) begin
                            rx_data_r  <= rx_shift_r;
                            rx_valid_r <= 1'b1;
                        end
                        state_r <= s_IDLE;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 16'd1;
                    end
                end

                default: state_r <= s_IDLE;
            endcase
        end
    end

endmodule
