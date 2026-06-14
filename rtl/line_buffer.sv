`timescale 1 ns / 1 ps

module line_buffer #(
    parameter int DWIDTH = 16
)(
    input  logic                     CLK,
    input  logic                     RST, // Active-low asynchronous reset

    // Control Signals
    input  logic                     load_i,
    input  logic                     shift_en_i,

    // Parallel IFM Input
    input  logic [DWIDTH-1:0]        ifm_bank0_i,
    input  logic [DWIDTH-1:0]        ifm_bank1_i,
    input  logic [DWIDTH-1:0]        ifm_bank2_i,
    input  logic [DWIDTH-1:0]        ifm_bank3_i,
    input  logic [DWIDTH-1:0]        ifm_bank4_i,

    input  logic                     ifm_bank0_valid_i,
    input  logic                     ifm_bank1_valid_i,
    input  logic                     ifm_bank2_valid_i,
    input  logic                     ifm_bank3_valid_i,
    input  logic                     ifm_bank4_valid_i,

    // Serial East Output
    output logic [DWIDTH-1:0]        east_ifmap_o,
    output logic                     east_ifmap_valid_o
);

    // Register Declarations (buf0 to buf3 shift registers)
    logic [DWIDTH-1:0]                buf0_r;
    logic [DWIDTH-1:0]                buf1_r;
    logic [DWIDTH-1:0]                buf2_r;
    logic [DWIDTH-1:0]                buf3_r;

    logic                             buf0_valid_r;
    logic                             buf1_valid_r;
    logic                             buf2_valid_r;
    logic                             buf3_valid_r;

    // Output Assignment
    assign east_ifmap_o       = shift_en_i ? buf0_r       : {DWIDTH{1'b0}};
    assign east_ifmap_valid_o = shift_en_i ? buf0_valid_r : 1'b0;

    // Sequential Shift Register Logic
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            buf0_r       <= {DWIDTH{1'b0}};
            buf1_r       <= {DWIDTH{1'b0}};
            buf2_r       <= {DWIDTH{1'b0}};
            buf3_r       <= {DWIDTH{1'b0}};
            buf0_valid_r <= 1'b0;
            buf1_valid_r <= 1'b0;
            buf2_valid_r <= 1'b0;
            buf3_valid_r <= 1'b0;
        end
        else begin
            if (load_i) begin
                // bank0 is bypassed directly at top-level.
                // line buffer stores and serializes the remaining 4 lanes: bank1 -> bank2 -> bank3 -> bank4
                buf0_r       <= ifm_bank1_i;
                buf1_r       <= ifm_bank2_i;
                buf2_r       <= ifm_bank3_i;
                buf3_r       <= ifm_bank4_i;
                buf0_valid_r <= ifm_bank1_valid_i;
                buf1_valid_r <= ifm_bank2_valid_i;
                buf2_valid_r <= ifm_bank3_valid_i;
                buf3_valid_r <= ifm_bank4_valid_i;
            end
            else if (shift_en_i) begin
                buf0_r       <= buf1_r;
                buf1_r       <= buf2_r;
                buf2_r       <= buf3_r;
                buf3_r       <= {DWIDTH{1'b0}};

                buf0_valid_r <= buf1_valid_r;
                buf1_valid_r <= buf2_valid_r;
                buf2_valid_r <= buf3_valid_r;
                buf3_valid_r <= 1'b0;
            end
        end
    end

endmodule
