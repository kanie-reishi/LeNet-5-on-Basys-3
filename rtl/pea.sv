`timescale 1 ns / 1 ps

module pea #(
    parameter int DATA_DWIDTH = 16,
    parameter int FRAC_BITS   = 8
)(
    input  logic                             CLK,
    input  logic                             RST, // Active-low asynchronous reset

    // Control
    input  logic                             first_ifmap_i,
    input  logic                             last_ifmap_i,
    input  logic                             execute_i,
    input  logic                             ifm_from_north_i,

    // North Inputs
    input  logic signed [DATA_DWIDTH-1:0]    bank0_mem_ifmap_i,
    input  logic                             bank0_mem_ifmap_valid_i,

    input  logic signed [DATA_DWIDTH-1:0]    bank1_mem_ifmap_i,
    input  logic                             bank1_mem_ifmap_valid_i,

    input  logic signed [DATA_DWIDTH-1:0]    bank2_mem_ifmap_i,
    input  logic                             bank2_mem_ifmap_valid_i,

    input  logic signed [DATA_DWIDTH-1:0]    bank3_mem_ifmap_i,
    input  logic                             bank3_mem_ifmap_valid_i,

    input  logic signed [DATA_DWIDTH-1:0]    bank4_mem_ifmap_i,
    input  logic                             bank4_mem_ifmap_valid_i,

    // External East Input
    input  logic signed [DATA_DWIDTH-1:0]    east_ifmap_i,
    input  logic                             east_ifmap_valid_i,

    // Row Weights/Biases
    input  logic signed [DATA_DWIDTH-1:0]    row0_mem_weight_i,
    input  logic                             row0_mem_weight_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row1_mem_weight_i,
    input  logic                             row1_mem_weight_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row2_mem_weight_i,
    input  logic                             row2_mem_weight_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row3_mem_weight_i,
    input  logic                             row3_mem_weight_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row4_mem_weight_i,
    input  logic                             row4_mem_weight_valid_i,

    input  logic signed [DATA_DWIDTH-1:0]    row0_mem_bias_i,
    input  logic                             row0_mem_bias_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row1_mem_bias_i,
    input  logic                             row1_mem_bias_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row2_mem_bias_i,
    input  logic                             row2_mem_bias_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row3_mem_bias_i,
    input  logic                             row3_mem_bias_valid_i,
    input  logic signed [DATA_DWIDTH-1:0]    row4_mem_bias_i,
    input  logic                             row4_mem_bias_valid_i,

    // OFMAP Output
    output logic signed [DATA_DWIDTH-1:0]    bank0_mem_ofmap_o,
    output logic                             bank0_mem_ofmap_valid_o,

    output logic signed [DATA_DWIDTH-1:0]    bank1_mem_ofmap_o,
    output logic                             bank1_mem_ofmap_valid_o,

    output logic signed [DATA_DWIDTH-1:0]    bank2_mem_ofmap_o,
    output logic                             bank2_mem_ofmap_valid_o,

    output logic signed [DATA_DWIDTH-1:0]    bank3_mem_ofmap_o,
    output logic                             bank3_mem_ofmap_valid_o,

    output logic signed [DATA_DWIDTH-1:0]    bank4_mem_ofmap_o,
    output logic                             bank4_mem_ofmap_valid_o,

    // Shift
    input  logic [3:0]                       shift_i
);

    // Pipelined control and East inputs for row delay matching (4 stages for rows 1 to 4)
    logic                                    first_ifmap_r [0:3];
    logic                                    last_ifmap_r  [0:3];
    logic                                    execute_r     [0:3];

    logic signed [DATA_DWIDTH-1:0]          east_ifmap_delay_r [0:3];
    logic                                    east_ifmap_valid_delay_r [0:3];

    // Systolic PE Array local interconnection wires
    // Indices: row_g * 5 + col_g
    logic signed [DATA_DWIDTH-1:0]          south_data_w [0:24];
    logic                                    south_valid_w[0:24];

    logic signed [DATA_DWIDTH-1:0]          west_data_w  [0:24];
    logic                                    west_valid_w [0:24];

    logic signed [DATA_DWIDTH-1:0]          mem_ofmap_w  [0:24];
    logic                                    mem_ofmap_valid_w [0:24];

    logic signed [DATA_DWIDTH-1:0]          row0_north_ifmap_w [0:4];
    logic                                    row0_north_ifmap_valid_w [0:4];

    // Pipeline delay matching block
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            first_ifmap_r[0] <= 1'b0;
            first_ifmap_r[1] <= 1'b0;
            first_ifmap_r[2] <= 1'b0;
            first_ifmap_r[3] <= 1'b0;

            last_ifmap_r[0]  <= 1'b0;
            last_ifmap_r[1]  <= 1'b0;
            last_ifmap_r[2]  <= 1'b0;
            last_ifmap_r[3]  <= 1'b0;

            execute_r[0]     <= 1'b0;
            execute_r[1]     <= 1'b0;
            execute_r[2]     <= 1'b0;
            execute_r[3]     <= 1'b0;

            east_ifmap_delay_r[0] <= {DATA_DWIDTH{1'b0}};
            east_ifmap_delay_r[1] <= {DATA_DWIDTH{1'b0}};
            east_ifmap_delay_r[2] <= {DATA_DWIDTH{1'b0}};
            east_ifmap_delay_r[3] <= {DATA_DWIDTH{1'b0}};

            east_ifmap_valid_delay_r[0] <= 1'b0;
            east_ifmap_valid_delay_r[1] <= 1'b0;
            east_ifmap_valid_delay_r[2] <= 1'b0;
            east_ifmap_valid_delay_r[3] <= 1'b0;
        end
        else begin
            first_ifmap_r[0] <= first_ifmap_i;
            first_ifmap_r[1] <= first_ifmap_r[0];
            first_ifmap_r[2] <= first_ifmap_r[1];
            first_ifmap_r[3] <= first_ifmap_r[2];

            last_ifmap_r[0]  <= last_ifmap_i;
            last_ifmap_r[1]  <= last_ifmap_r[0];
            last_ifmap_r[2]  <= last_ifmap_r[1];
            last_ifmap_r[3]  <= last_ifmap_r[2];

            execute_r[0]     <= execute_i;
            execute_r[1]     <= execute_r[0];
            execute_r[2]     <= execute_r[1];
            execute_r[3]     <= execute_r[2];

            east_ifmap_delay_r[0]       <= east_ifmap_i;
            east_ifmap_delay_r[1]       <= east_ifmap_delay_r[0];
            east_ifmap_delay_r[2]       <= east_ifmap_delay_r[1];
            east_ifmap_delay_r[3]       <= east_ifmap_delay_r[2];

            east_ifmap_valid_delay_r[0] <= east_ifmap_valid_i;
            east_ifmap_valid_delay_r[1] <= east_ifmap_valid_delay_r[0];
            east_ifmap_valid_delay_r[2] <= east_ifmap_valid_delay_r[1];
            east_ifmap_valid_delay_r[3] <= east_ifmap_valid_delay_r[2];
        end
    end

    // Row0 North Gating (North IFMAP enters array only if gated by control signal)
    assign row0_north_ifmap_w[0]       = bank0_mem_ifmap_i;
    assign row0_north_ifmap_w[1]       = bank1_mem_ifmap_i;
    assign row0_north_ifmap_w[2]       = bank2_mem_ifmap_i;
    assign row0_north_ifmap_w[3]       = bank3_mem_ifmap_i;
    assign row0_north_ifmap_w[4]       = bank4_mem_ifmap_i;

    assign row0_north_ifmap_valid_w[0] = ifm_from_north_i && bank0_mem_ifmap_valid_i;
    assign row0_north_ifmap_valid_w[1] = ifm_from_north_i && bank1_mem_ifmap_valid_i;
    assign row0_north_ifmap_valid_w[2] = ifm_from_north_i && bank2_mem_ifmap_valid_i;
    assign row0_north_ifmap_valid_w[3] = ifm_from_north_i && bank3_mem_ifmap_valid_i;
    assign row0_north_ifmap_valid_w[4] = ifm_from_north_i && bank4_mem_ifmap_valid_i;

    // PE Array Instantiations
    generate
        genvar row_g, col_g;
        for (row_g = 0; row_g < 5; row_g = row_g + 1) begin : gen_row
            for (col_g = 0; col_g < 5; col_g = col_g + 1) begin : gen_col
                localparam int PE_IDX    = (row_g * 5) + col_g;
                localparam int NORTH_IDX = (row_g == 0) ? 0 : (((row_g - 1) * 5) + col_g);
                localparam int EAST_IDX  = (PE_IDX < 24) ? (PE_IDX + 1) : PE_IDX;

                mac_pe #(
                    .DATA_DWIDTH(DATA_DWIDTH),
                    .FRAC_BITS  (FRAC_BITS)
                ) u_pe (
                    .CLK                (CLK),
                    .RST                (RST),
                    .shift_i            (shift_i),

                    .first_ifmap_i      ((row_g == 0) ? first_ifmap_i :
                                         (row_g == 1) ? first_ifmap_r[0] :
                                         (row_g == 2) ? first_ifmap_r[1] :
                                         (row_g == 3) ? first_ifmap_r[2] :
                                                        first_ifmap_r[3]),

                    .last_ifmap_i       ((row_g == 0) ? last_ifmap_i :
                                         (row_g == 1) ? last_ifmap_r[0] :
                                         (row_g == 2) ? last_ifmap_r[1] :
                                         (row_g == 3) ? last_ifmap_r[2] :
                                                        last_ifmap_r[3]),

                    .execute_i          ((row_g == 0) ? execute_i :
                                         (row_g == 1) ? execute_r[0] :
                                         (row_g == 2) ? execute_r[1] :
                                         (row_g == 3) ? execute_r[2] :
                                                        execute_r[3]),

                    .north_ifmap_i      ((row_g == 0) ?
                                         row0_north_ifmap_w[col_g] :
                                         south_data_w[NORTH_IDX]),

                    .north_ifmap_valid_i((row_g == 0) ?
                                         row0_north_ifmap_valid_w[col_g] :
                                         south_valid_w[NORTH_IDX]),

                    .east_ifmap_i       ((col_g == 4) ?
                                         ((row_g == 0) ? east_ifmap_i :
                                          (row_g == 1) ? east_ifmap_delay_r[0] :
                                          (row_g == 2) ? east_ifmap_delay_r[1] :
                                          (row_g == 3) ? east_ifmap_delay_r[2] :
                                                         east_ifmap_delay_r[3]) :
                                         west_data_w[EAST_IDX]),

                    .east_ifmap_valid_i ((col_g == 4) ?
                                         ((row_g == 0) ? east_ifmap_valid_i :
                                          (row_g == 1) ? east_ifmap_valid_delay_r[0] :
                                          (row_g == 2) ? east_ifmap_valid_delay_r[1] :
                                          (row_g == 3) ? east_ifmap_valid_delay_r[2] :
                                                         east_ifmap_valid_delay_r[3]) :
                                         west_valid_w[EAST_IDX]),

                    .south_ifmap_o      (south_data_w[PE_IDX]),
                    .south_ifmap_valid_o(south_valid_w[PE_IDX]),
                    .west_ifmap_o       (west_data_w[PE_IDX]),
                    .west_ifmap_valid_o (west_valid_w[PE_IDX]),

                    .mem_weight_i       ((row_g == 0) ? row0_mem_weight_i :
                                         (row_g == 1) ? row1_mem_weight_i :
                                         (row_g == 2) ? row2_mem_weight_i :
                                         (row_g == 3) ? row3_mem_weight_i :
                                                        row4_mem_weight_i),

                    .mem_weight_valid_i ((row_g == 0) ? row0_mem_weight_valid_i :
                                         (row_g == 1) ? row1_mem_weight_valid_i :
                                         (row_g == 2) ? row2_mem_weight_valid_i :
                                         (row_g == 3) ? row3_mem_weight_valid_i :
                                                        row4_mem_weight_valid_i),

                    .mem_bias_i         ((row_g == 0) ? row0_mem_bias_i :
                                         (row_g == 1) ? row1_mem_bias_i :
                                         (row_g == 2) ? row2_mem_bias_i :
                                         (row_g == 3) ? row3_mem_bias_i :
                                                        row4_mem_bias_i),

                    .mem_bias_valid_i   ((row_g == 0) ? row0_mem_bias_valid_i :
                                         (row_g == 1) ? row1_mem_bias_valid_i :
                                         (row_g == 2) ? row2_mem_bias_valid_i :
                                         (row_g == 3) ? row3_mem_bias_valid_i :
                                                        row4_mem_bias_valid_i),

                    .mem_ofmap_o        (mem_ofmap_w[PE_IDX]),
                    .mem_ofmap_valid_o  (mem_ofmap_valid_w[PE_IDX])
                );
            end
        end
    endgenerate

    // OFMAP Output Mapping (Multiplex column-wise PE outputs)
    assign bank0_mem_ofmap_o       = mem_ofmap_valid_w[0]  ? mem_ofmap_w[0]  :
                                     mem_ofmap_valid_w[5]  ? mem_ofmap_w[5]  :
                                     mem_ofmap_valid_w[10] ? mem_ofmap_w[10] :
                                     mem_ofmap_valid_w[15] ? mem_ofmap_w[15] :
                                                             mem_ofmap_w[20];
    assign bank0_mem_ofmap_valid_o = mem_ofmap_valid_w[0]  |
                                     mem_ofmap_valid_w[5]  |
                                     mem_ofmap_valid_w[10] |
                                     mem_ofmap_valid_w[15] |
                                     mem_ofmap_valid_w[20];

    assign bank1_mem_ofmap_o       = mem_ofmap_valid_w[1]  ? mem_ofmap_w[1]  :
                                     mem_ofmap_valid_w[6]  ? mem_ofmap_w[6]  :
                                     mem_ofmap_valid_w[11] ? mem_ofmap_w[11] :
                                     mem_ofmap_valid_w[16] ? mem_ofmap_w[16] :
                                                             mem_ofmap_w[21];
    assign bank1_mem_ofmap_valid_o = mem_ofmap_valid_w[1]  |
                                     mem_ofmap_valid_w[6]  |
                                     mem_ofmap_valid_w[11] |
                                     mem_ofmap_valid_w[16] |
                                     mem_ofmap_valid_w[21];

    assign bank2_mem_ofmap_o       = mem_ofmap_valid_w[2]  ? mem_ofmap_w[2]  :
                                     mem_ofmap_valid_w[7]  ? mem_ofmap_w[7]  :
                                     mem_ofmap_valid_w[12] ? mem_ofmap_w[12] :
                                     mem_ofmap_valid_w[17] ? mem_ofmap_w[17] :
                                                             mem_ofmap_w[22];
    assign bank2_mem_ofmap_valid_o = mem_ofmap_valid_w[2]  |
                                     mem_ofmap_valid_w[7]  |
                                     mem_ofmap_valid_w[12] |
                                     mem_ofmap_valid_w[17] |
                                     mem_ofmap_valid_w[22];

    assign bank3_mem_ofmap_o       = mem_ofmap_valid_w[3]  ? mem_ofmap_w[3]  :
                                     mem_ofmap_valid_w[8]  ? mem_ofmap_w[8]  :
                                     mem_ofmap_valid_w[13] ? mem_ofmap_w[13] :
                                     mem_ofmap_valid_w[18] ? mem_ofmap_w[18] :
                                                             mem_ofmap_w[23];
    assign bank3_mem_ofmap_valid_o = mem_ofmap_valid_w[3]  |
                                     mem_ofmap_valid_w[8]  |
                                     mem_ofmap_valid_w[13] |
                                     mem_ofmap_valid_w[18] |
                                     mem_ofmap_valid_w[23];

    assign bank4_mem_ofmap_o       = mem_ofmap_valid_w[4]  ? mem_ofmap_w[4]  :
                                     mem_ofmap_valid_w[9]  ? mem_ofmap_w[9]  :
                                     mem_ofmap_valid_w[14] ? mem_ofmap_w[14] :
                                     mem_ofmap_valid_w[19] ? mem_ofmap_w[19] :
                                                             mem_ofmap_w[24];
    assign bank4_mem_ofmap_valid_o = mem_ofmap_valid_w[4]  |
                                     mem_ofmap_valid_w[9]  |
                                     mem_ofmap_valid_w[14] |
                                     mem_ofmap_valid_w[19] |
                                     mem_ofmap_valid_w[24];

endmodule
