`timescale 1 ns / 1 ps

module Adder_Tree_5x5 #(
    parameter DATA_DWIDTH    = 16,
    parameter PRODUCT_DWIDTH = DATA_DWIDTH,
    parameter ACC_DWIDTH     = 40
)(
    input  wire                                      CLK,
    input  wire                                      RST,

    // Product inputs from PEA
    input  wire                                      product_valid_i,
    input  wire signed [(25*PRODUCT_DWIDTH)-1:0]     product_i,

    // Channel control
    input  wire                                      first_channel_i,

    // Previous partial sum from feature-map memory
    input  wire signed [DATA_DWIDTH-1:0]             prev_psum_i,
    input  wire                                      prev_psum_valid_i,

    // Bias, only used for the first input channel
    input  wire signed [DATA_DWIDTH-1:0]             bias_i,
    input  wire                                      bias_valid_i,

    // Output partial sum
    output reg  signed [DATA_DWIDTH-1:0]             psum_o,
    output reg                                       psum_valid_o
);

    //-------------------------------------//
    // Local Parameters
    //-------------------------------------//
    localparam FRAC_BITS = 8;

    localparam signed [DATA_DWIDTH-1:0] Q16_MAX = 16'sh7FFF;
    localparam signed [DATA_DWIDTH-1:0] Q16_MIN = 16'sh8000;

    //-------------------------------------//
    // Wire Declarations
    //-------------------------------------//
    wire signed [PRODUCT_DWIDTH-1:0] product_w [0:24];
    wire signed [ACC_DWIDTH-1:0]     mac_q8_w  [0:24];

    wire signed [ACC_DWIDTH-1:0] sum_l1_w [0:12];
    wire signed [ACC_DWIDTH-1:0] sum_l2_w [0:6];
    wire signed [ACC_DWIDTH-1:0] sum_l3_w [0:3];
    wire signed [ACC_DWIDTH-1:0] sum_l4_w [0:1];
    wire signed [ACC_DWIDTH-1:0] sum_l5_w;

    wire signed [DATA_DWIDTH-1:0] bias_hold_w;
    wire                         bias_hold_valid_w;
    wire signed [ACC_DWIDTH-1:0] bias_ext_w;
    wire signed [ACC_DWIDTH-1:0] prev_psum_ext_w;
    wire signed [ACC_DWIDTH-1:0] init_add_w;
    wire                         init_valid_w;
    wire                         compute_en_w;

    wire signed [ACC_DWIDTH-1:0] psum_full_w;

    wire signed [ACC_DWIDTH-1:0] q16_max_ext_w;
    wire signed [ACC_DWIDTH-1:0] q16_min_ext_w;

    reg  signed [DATA_DWIDTH-1:0] psum_sat_r;
    reg  signed [DATA_DWIDTH-1:0] bias_r;
    reg                         bias_valid_r;

    // Pipeline registers for Level 3 output and controls
    reg signed [ACC_DWIDTH-1:0] sum_l3_r [0:3];
    reg signed [ACC_DWIDTH-1:0] init_add_r;
    reg                         init_valid_r;
    reg                         product_valid_r;
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            sum_l3_r[0]     <= {ACC_DWIDTH{1'b0}};
            sum_l3_r[1]     <= {ACC_DWIDTH{1'b0}};
            sum_l3_r[2]     <= {ACC_DWIDTH{1'b0}};
            sum_l3_r[3]     <= {ACC_DWIDTH{1'b0}};
            init_add_r      <= {ACC_DWIDTH{1'b0}};
            init_valid_r    <= 1'b0;
            product_valid_r <= 1'b0;
        end
        else begin
            sum_l3_r[0]     <= sum_l3_w[0];
            sum_l3_r[1]     <= sum_l3_w[1];
            sum_l3_r[2]     <= sum_l3_w[2];
            sum_l3_r[3]     <= sum_l3_w[3];
            init_add_r      <= init_add_w;
            init_valid_r    <= init_valid_w;
            product_valid_r <= product_valid_i;
        end
    end
    genvar i;

    //-------------------------------------//
    // Unpack Products
    // PE already converts each Q16.16 product to saturated 16-bit Q8.8.
    // Sign-extend to ACC_DWIDTH here so the tree can detect sum overflow.
    //-------------------------------------//
    generate
        for (i = 0; i < 25; i = i + 1) begin : UNPACK_PRODUCT
            assign product_w[i] =
                product_i[(i*PRODUCT_DWIDTH) +: PRODUCT_DWIDTH];

            assign mac_q8_w[i] =
                {{(ACC_DWIDTH-PRODUCT_DWIDTH){product_w[i][PRODUCT_DWIDTH-1]}},
                 product_w[i]};
        end
    endgenerate

    //-------------------------------------//
    // Balanced Adder Tree
    //-------------------------------------//

    // Level 1: 25 to 13
    assign sum_l1_w[0]  = mac_q8_w[0]  + mac_q8_w[1];
    assign sum_l1_w[1]  = mac_q8_w[2]  + mac_q8_w[3];
    assign sum_l1_w[2]  = mac_q8_w[4]  + mac_q8_w[5];
    assign sum_l1_w[3]  = mac_q8_w[6]  + mac_q8_w[7];
    assign sum_l1_w[4]  = mac_q8_w[8]  + mac_q8_w[9];
    assign sum_l1_w[5]  = mac_q8_w[10] + mac_q8_w[11];
    assign sum_l1_w[6]  = mac_q8_w[12] + mac_q8_w[13];
    assign sum_l1_w[7]  = mac_q8_w[14] + mac_q8_w[15];
    assign sum_l1_w[8]  = mac_q8_w[16] + mac_q8_w[17];
    assign sum_l1_w[9]  = mac_q8_w[18] + mac_q8_w[19];
    assign sum_l1_w[10] = mac_q8_w[20] + mac_q8_w[21];
    assign sum_l1_w[11] = mac_q8_w[22] + mac_q8_w[23];
    assign sum_l1_w[12] = mac_q8_w[24];

    // Level 2: 13 to 7
    assign sum_l2_w[0] = sum_l1_w[0]  + sum_l1_w[1];
    assign sum_l2_w[1] = sum_l1_w[2]  + sum_l1_w[3];
    assign sum_l2_w[2] = sum_l1_w[4]  + sum_l1_w[5];
    assign sum_l2_w[3] = sum_l1_w[6]  + sum_l1_w[7];
    assign sum_l2_w[4] = sum_l1_w[8]  + sum_l1_w[9];
    assign sum_l2_w[5] = sum_l1_w[10] + sum_l1_w[11];
    assign sum_l2_w[6] = sum_l1_w[12];

    // Level 3: 7 to 4
    assign sum_l3_w[0] = sum_l2_w[0] + sum_l2_w[1];
    assign sum_l3_w[1] = sum_l2_w[2] + sum_l2_w[3];
    assign sum_l3_w[2] = sum_l2_w[4] + sum_l2_w[5];
    assign sum_l3_w[3] = sum_l2_w[6];

    // Level 4: 4 to 2 (Uses registered Level 3 sums)
    assign sum_l4_w[0] = sum_l3_r[0] + sum_l3_r[1];
    assign sum_l4_w[1] = sum_l3_r[2] + sum_l3_r[3];
    // Level 5: 2 to 1
    assign sum_l5_w = sum_l4_w[0] + sum_l4_w[1];

    //-------------------------------------//
    // Bias Or Previous Partial Sum Selection
    //-------------------------------------//
    assign bias_hold_w =
        bias_valid_i ? bias_i : bias_r;

    assign bias_hold_valid_w =
        bias_valid_i | bias_valid_r;

    assign bias_ext_w =
        {{(ACC_DWIDTH-DATA_DWIDTH){bias_hold_w[DATA_DWIDTH-1]}}, bias_hold_w};

    assign prev_psum_ext_w =
        {{(ACC_DWIDTH-DATA_DWIDTH){prev_psum_i[DATA_DWIDTH-1]}}, prev_psum_i};

    assign init_add_w =
        first_channel_i ? bias_ext_w : prev_psum_ext_w;

    assign init_valid_w =
        first_channel_i ? bias_hold_valid_w : prev_psum_valid_i;

    assign compute_en_w =
        product_valid_r && init_valid_r;

    assign psum_full_w =
        sum_l5_w + init_add_r;

    //-------------------------------------//
    // Saturation To Signed 16-bit Q8.8
    //-------------------------------------//
    assign q16_max_ext_w =
        {{(ACC_DWIDTH-DATA_DWIDTH){Q16_MAX[DATA_DWIDTH-1]}}, Q16_MAX};

    assign q16_min_ext_w =
        {{(ACC_DWIDTH-DATA_DWIDTH){Q16_MIN[DATA_DWIDTH-1]}}, Q16_MIN};

    always @(*) begin
        if (psum_full_w > q16_max_ext_w) begin
            psum_sat_r = Q16_MAX;
        end
        else if (psum_full_w < q16_min_ext_w) begin
            psum_sat_r = Q16_MIN;
        end
        else begin
            psum_sat_r = psum_full_w[DATA_DWIDTH-1:0];
        end
    end

    //-------------------------------------//
    // Output Register
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            psum_o       <= {DATA_DWIDTH{1'b0}};
            psum_valid_o <= 1'b0;
            bias_r       <= {DATA_DWIDTH{1'b0}};
            bias_valid_r <= 1'b0;
        end
        else begin
            if (bias_valid_i) begin
                bias_r       <= bias_i;
                bias_valid_r <= 1'b1;
            end

            if (compute_en_w) begin
                psum_o <= psum_sat_r;
            end
            else begin
                psum_o <= {DATA_DWIDTH{1'b0}};
            end

            psum_valid_o <= compute_en_w;
        end
    end

endmodule