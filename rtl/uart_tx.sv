`timescale 1 ns / 1 ps

module uart_tx #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115200
)(
    input  logic       CLK,
    input  logic       RST, // Active-low asynchronous reset
    input  logic [7:0] tx_data_i,
    input  logic       tx_start_i,
    output logic       txd_o,
    output logic       tx_busy_o
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

    // Shift register for data
    logic [7:0] tx_shift_r;
    logic       txd_r;
    logic       tx_busy_r;

    assign txd_o     = txd_r;
    assign tx_busy_o = tx_busy_r;

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            state_r    <= s_IDLE;
            clk_cnt_r  <= 16'd0;
            bit_cnt_r  <= 3'd0;
            tx_shift_r <= 8'd0;
            txd_r      <= 1'b1; // Idle state is high
            tx_busy_r  <= 1'b0;
        end else begin
            case (state_r)
                s_IDLE: begin
                    txd_r     <= 1'b1;
                    tx_busy_r <= 1'b0;
                    clk_cnt_r <= 16'd0;
                    bit_cnt_r <= 3'd0;
                    
                    if (tx_start_i) begin
                        tx_shift_r <= tx_data_i;
                        tx_busy_r  <= 1'b1;
                        txd_r      <= 1'b0; // Start bit is low
                        state_r    <= s_START;
                    end
                end

                s_START: begin
                    txd_r <= 1'b0;
                    if (clk_cnt_r == CLK_PER_BIT - 1) begin
                        clk_cnt_r <= 16'd0;
                        txd_r     <= tx_shift_r[0]; // send LSB
                        state_r   <= s_DATA;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 16'd1;
                    end
                end

                s_DATA: begin
                    txd_r <= tx_shift_r[0];
                    if (clk_cnt_r == CLK_PER_BIT - 1) begin
                        clk_cnt_r <= 16'd0;
                        tx_shift_r <= {1'b0, tx_shift_r[7:1]};
                        
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
                    txd_r <= 1'b1; // Stop bit is high
                    if (clk_cnt_r == CLK_PER_BIT - 1) begin
                        clk_cnt_r <= 16'd0;
                        state_r   <= s_IDLE;
                    end else begin
                        clk_cnt_r <= clk_cnt_r + 16'd1;
                    end
                end

                default: state_r <= s_IDLE;
            endcase
        end
    end

endmodule
