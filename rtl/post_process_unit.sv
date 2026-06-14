`timescale 1 ns / 1 ps

module post_process_unit #(
    parameter int DWIDTH = 16
)(
    // Layer Configuration
    input  logic [3:0]               layer_type_i,
    input  logic [11:0]              in_channels_i,
    input  logic [11:0]              out_channels_i,
    input  logic [7:0]               activation_i,

    // Inputs from PE Array (16-bit signed)
    input  logic signed [DWIDTH-1:0] bank0_mem_ofmap_i,
    input  logic                     bank0_mem_ofmap_valid_i,
    input  logic signed [DWIDTH-1:0] bank1_mem_ofmap_i,
    input  logic                     bank1_mem_ofmap_valid_i,
    input  logic signed [DWIDTH-1:0] bank2_mem_ofmap_i,
    input  logic                     bank2_mem_ofmap_valid_i,
    input  logic signed [DWIDTH-1:0] bank3_mem_ofmap_i,
    input  logic                     bank3_mem_ofmap_valid_i,
    input  logic signed [DWIDTH-1:0] bank4_mem_ofmap_i,
    input  logic                     bank4_mem_ofmap_valid_i,

    // Outputs to BRAM write path
    output logic [DWIDTH-1:0]        bank0_mem_ofmap_o,
    output logic                     bank0_mem_ofmap_valid_o,
    output logic [DWIDTH-1:0]        bank1_mem_ofmap_o,
    output logic                     bank1_mem_ofmap_valid_o,
    output logic [DWIDTH-1:0]        bank2_mem_ofmap_o,
    output logic                     bank2_mem_ofmap_valid_o,
    output logic [DWIDTH-1:0]        bank3_mem_ofmap_o,
    output logic                     bank3_mem_ofmap_valid_o,
    output logic [DWIDTH-1:0]        bank4_mem_ofmap_o,
    output logic                     bank4_mem_ofmap_valid_o
);

    // Helper function for ReLU and clamp
    function automatic logic [DWIDTH-1:0] process_channel(
        input logic signed [DWIDTH-1:0] val_i,
        input logic [7:0]                act_i
    );
        logic signed [31:0] val_32;
        logic signed [31:0] relu_out;
        logic signed [31:0] clamped_out;

        val_32 = $signed({{16{val_i[DWIDTH-1]}}, val_i});

        // ReLU Activation
        if (act_i == 8'd1) begin
            relu_out = (val_32 < 32'sd0) ? 32'sd0 : val_32;
            // Clamp to [0, 127]
            clamped_out = (relu_out > 32'sd127) ? 32'sd127 : relu_out;
        end else begin
            // No activation -> keep raw value
            clamped_out = val_32;
        end

        return clamped_out[DWIDTH-1:0];
    endfunction

    // Process each bank output
    assign bank0_mem_ofmap_o       = process_channel(bank0_mem_ofmap_i, activation_i);
    assign bank0_mem_ofmap_valid_o = bank0_mem_ofmap_valid_i;

    assign bank1_mem_ofmap_o       = process_channel(bank1_mem_ofmap_i, activation_i);
    assign bank1_mem_ofmap_valid_o = bank1_mem_ofmap_valid_i;

    assign bank2_mem_ofmap_o       = process_channel(bank2_mem_ofmap_i, activation_i);
    assign bank2_mem_ofmap_valid_o = bank2_mem_ofmap_valid_i;

    assign bank3_mem_ofmap_o       = process_channel(bank3_mem_ofmap_i, activation_i);
    assign bank3_mem_ofmap_valid_o = bank3_mem_ofmap_valid_i;

    assign bank4_mem_ofmap_o       = process_channel(bank4_mem_ofmap_i, activation_i);
    assign bank4_mem_ofmap_valid_o = bank4_mem_ofmap_valid_i;

endmodule
