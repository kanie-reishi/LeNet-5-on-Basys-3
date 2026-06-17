`timescale 1 ns / 1 ps
module PE #(
    parameter DATA_DWIDTH = 16
)(
    input  wire                              CLK,
    input  wire                              RST,
    input  wire                              weight_load_i,
    input  wire signed [DATA_DWIDTH-1:0]     weight_i,
    input  wire signed [DATA_DWIDTH-1:0]     PREV_PE_ifmap_i,
    input  wire                              PREV_PE_ifmap_valid_i,
    output wire signed [DATA_DWIDTH-1:0]     NEXT_PE_ifmap_o,
    output wire                              NEXT_PE_ifmap_valid_o,
    input  wire                              execute_i,
    output wire signed [DATA_DWIDTH-1:0]     product_o
);
    //-------------------------------------//
    // Local Parameters
    //-------------------------------------//
    localparam signed [DATA_DWIDTH-1:0] Q16_MAX = 16'sh7FFF;
    localparam signed [DATA_DWIDTH-1:0] Q16_MIN = 16'sh8000;
    //-------------------------------------//
    // Register/Wire Declarations
    //-------------------------------------//
    reg signed [DATA_DWIDTH-1:0] weight_r;
    reg signed [DATA_DWIDTH-1:0] ifmap_r;
    reg                          ifmap_valid_r;
    wire signed [DATA_DWIDTH-1:0] ifm_w;
    wire signed [DATA_DWIDTH-1:0] weight_w;
    (* use_dsp = "yes" *) wire signed [(2*DATA_DWIDTH)-1:0] product_full_w;
    wire signed [(2*DATA_DWIDTH)-1:0] product_q8_w;
    wire signed [DATA_DWIDTH-1:0]     product_sat_w;
    //-------------------------------------//
    // Weight Storage
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            weight_r <= {DATA_DWIDTH{1'b0}};
        end
        else if (weight_load_i) begin
            weight_r <= weight_i;
        end
    end
    //-------------------------------------//
    // IFMap Shift Register
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            ifmap_r       <= {DATA_DWIDTH{1'b0}};
            ifmap_valid_r <= 1'b0;
        end
        else begin
            ifmap_r       <= PREV_PE_ifmap_i;
            ifmap_valid_r <= PREV_PE_ifmap_valid_i;
        end
    end
    assign NEXT_PE_ifmap_o       = ifmap_r;
    assign NEXT_PE_ifmap_valid_o = ifmap_valid_r;

    //-------------------------------------//
    // Signed Multiply
    // Q8.8 * Q8.8 = Q16.16. Shift each product
    // back to Q8.8 here to match the Python/C reference:
    //     acc += floor((ifmap_q16 * weight_q16) / 256)
    //-------------------------------------//
    assign ifm_w    = PREV_PE_ifmap_i;
    assign weight_w = weight_load_i ? weight_i : weight_r;

    // Explicit 16x16 signed multiplication yielding 32-bit product
    assign product_full_w = $signed(ifm_w) * $signed(weight_w);
    assign product_q8_w   = product_full_w >>> 8;

    // Keep the PE output in Q8.8 / 16-bit.
    // The adder tree sign-extends these 16-bit products to a wider
    // accumulator and performs final saturation after adding bias/psum.
    assign product_sat_w  = (product_q8_w > 32'sd32767) ? Q16_MAX :
                            (product_q8_w < -32'sd32768) ? Q16_MIN :
                            product_q8_w[DATA_DWIDTH-1:0];

    assign product_o = (execute_i && PREV_PE_ifmap_valid_i) ? product_sat_w : {DATA_DWIDTH{1'b0}};
	
endmodule