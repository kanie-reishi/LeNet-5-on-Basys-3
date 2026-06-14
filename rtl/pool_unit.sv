`timescale 1 ns / 1 ps

module pool_unit #(
    parameter int DWIDTH = 16
)(
    input  logic                     CLK,
    input  logic                     RST, // Active-low asynchronous reset

    // Control
    input  logic [2:0]               pool_step_i, // 0 to 4 from Controller

    // Parallel BRAM Read Data inputs (1 cycle latency relative to pool_read_addr_w)
    input  logic [DWIDTH-1:0]        bank0_rd_data_i,
    input  logic [DWIDTH-1:0]        bank1_rd_data_i,
    input  logic [DWIDTH-1:0]        bank2_rd_data_i,
    input  logic [DWIDTH-1:0]        bank3_rd_data_i,
    input  logic [DWIDTH-1:0]        bank4_rd_data_i,

    // Parallel BRAM Write Data outputs
    output logic [DWIDTH-1:0]        bank0_pool_data_o,
    output logic                     bank0_pool_valid_o,
    output logic [DWIDTH-1:0]        bank1_pool_data_o,
    output logic                     bank1_pool_valid_o,
    output logic [DWIDTH-1:0]        bank2_pool_data_o,
    output logic                     bank2_pool_valid_o,
    output logic [DWIDTH-1:0]        bank3_pool_data_o,
    output logic                     bank3_pool_valid_o,
    output logic [DWIDTH-1:0]        bank4_pool_data_o,
    output logic                     bank4_pool_valid_o
);

    // Helper function to find max of two signed 16-bit values
    function automatic logic signed [DWIDTH-1:0] max2(
        input logic signed [DWIDTH-1:0] a,
        input logic signed [DWIDTH-1:0] b
    );
        return (a > b) ? a : b;
    endfunction

    // Registers to store accumulated max values
    logic signed [DWIDTH-1:0] accum_max0_r;
    logic signed [DWIDTH-1:0] accum_max1_r;
    logic signed [DWIDTH-1:0] accum_max2_r;
    logic signed [DWIDTH-1:0] accum_max3_r;
    logic signed [DWIDTH-1:0] accum_max4_r;

    // Latch maximums based on pool_step_i
    // (BRAM data is valid 1 cycle after address is sent, so step 0 data arrives at step 1)
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            accum_max0_r <= {DWIDTH{1'b0}};
            accum_max1_r <= {DWIDTH{1'b0}};
            accum_max2_r <= {DWIDTH{1'b0}};
            accum_max3_r <= {DWIDTH{1'b0}};
            accum_max4_r <= {DWIDTH{1'b0}};
        end else begin
            case (pool_step_i)
                3'd1: begin
                    // Step 0 data is ready
                    // Bank 0 and Bank 1 -> Lane 0
                    // Bank 2 and Bank 3 -> Lane 1
                    // Bank 4            -> Lane 2
                    accum_max0_r <= max2(bank0_rd_data_i, bank1_rd_data_i);
                    accum_max1_r <= max2(bank2_rd_data_i, bank3_rd_data_i);
                    accum_max2_r <= bank4_rd_data_i;
                end
                3'd2: begin
                    // Step 1 data is ready
                    // Bank 0            -> Lane 2
                    // Bank 1 and Bank 2 -> Lane 3
                    // Bank 3 and Bank 4 -> Lane 4
                    accum_max2_r <= max2(accum_max2_r, bank0_rd_data_i);
                    accum_max3_r <= max2(bank1_rd_data_i, bank2_rd_data_i);
                    accum_max4_r <= max2(bank3_rd_data_i, bank4_rd_data_i);
                end
                3'd3: begin
                    // Step 2 data is ready
                    // Bank 0 and Bank 1 -> Lane 0
                    // Bank 2 and Bank 3 -> Lane 1
                    // Bank 4            -> Lane 2
                    accum_max0_r <= max2(accum_max0_r, max2(bank0_rd_data_i, bank1_rd_data_i));
                    accum_max1_r <= max2(accum_max1_r, max2(bank2_rd_data_i, bank3_rd_data_i));
                    accum_max2_r <= max2(accum_max2_r, bank4_rd_data_i);
                end
                3'd4: begin
                    // Step 3 data is ready
                    // Bank 0            -> Lane 2
                    // Bank 1 and Bank 2 -> Lane 3
                    // Bank 3 and Bank 4 -> Lane 4
                    accum_max2_r <= max2(accum_max2_r, bank0_rd_data_i);
                    accum_max3_r <= max2(bank1_rd_data_i, bank2_rd_data_i);
                    accum_max4_r <= max2(bank3_rd_data_i, bank4_rd_data_i);
                end
                default: begin
                    // Keep values
                    accum_max0_r <= accum_max0_r;
                    accum_max1_r <= accum_max1_r;
                    accum_max2_r <= accum_max2_r;
                    accum_max3_r <= accum_max3_r;
                    accum_max4_r <= accum_max4_r;
                end
            endcase
        end
    end

    // Combinational outputs driven during step 4 (write back cycle)
    always_comb begin
        if (pool_step_i == 3'd4) begin
            bank0_pool_data_o  = accum_max0_r;
            bank0_pool_valid_o = 1'b1;

            bank1_pool_data_o  = accum_max1_r;
            bank1_pool_valid_o = 1'b1;

            // Capturing step 3 data for Lanes 2, 3, 4 combinationaly to output on step 4
            bank2_pool_data_o  = max2(accum_max2_r, bank0_rd_data_i);
            bank2_pool_valid_o = 1'b1;

            bank3_pool_data_o  = max2(accum_max3_r, max2(bank1_rd_data_i, bank2_rd_data_i));
            bank3_pool_valid_o = 1'b1;

            bank4_pool_data_o  = max2(accum_max4_r, max2(bank3_rd_data_i, bank4_rd_data_i));
            bank4_pool_valid_o = 1'b1;
        end else begin
            bank0_pool_data_o  = {DWIDTH{1'b0}};
            bank0_pool_valid_o = 1'b0;
            bank1_pool_data_o  = {DWIDTH{1'b0}};
            bank1_pool_valid_o = 1'b0;
            bank2_pool_data_o  = {DWIDTH{1'b0}};
            bank2_pool_valid_o = 1'b0;
            bank3_pool_data_o  = {DWIDTH{1'b0}};
            bank3_pool_valid_o = 1'b0;
            bank4_pool_data_o  = {DWIDTH{1'b0}};
            bank4_pool_valid_o = 1'b0;
        end
    end

endmodule
