`timescale 1 ns / 1 ps

module mac_pe #(
    parameter int DATA_DWIDTH = 16,
    parameter int FRAC_BITS   = 8
)(
    input  logic                             CLK,
    input  logic                             RST, // Active-low asynchronous reset

    // Control
    input  logic                             first_ifmap_i,
    input  logic                             last_ifmap_i,
    input  logic                             execute_i,

    // North IFMAP
    input  logic signed [DATA_DWIDTH-1:0]    north_ifmap_i,
    input  logic                             north_ifmap_valid_i,

    // East IFMAP
    input  logic signed [DATA_DWIDTH-1:0]    east_ifmap_i,
    input  logic                             east_ifmap_valid_i,

    // Forward Outputs
    output logic signed [DATA_DWIDTH-1:0]    south_ifmap_o,
    output logic                             south_ifmap_valid_o,

    output logic signed [DATA_DWIDTH-1:0]    west_ifmap_o,
    output logic                             west_ifmap_valid_o,

    // Weight / Bias
    input  logic signed [DATA_DWIDTH-1:0]    mem_weight_i,
    input  logic                             mem_weight_valid_i,

    input  logic signed [DATA_DWIDTH-1:0]    mem_bias_i,
    input  logic                             mem_bias_valid_i,

    // Shift
    input  logic [3:0]                       shift_i,

    // OFMAP
    output logic signed [DATA_DWIDTH-1:0]    mem_ofmap_o,
    output logic                             mem_ofmap_valid_o
);

    // Saturation Logic function (Q16 saturation)
    function automatic logic signed [DATA_DWIDTH-1:0] sat_q16(input logic signed [31:0] value_i);
        if (value_i > 32'sd32767) begin
            return 16'sh7FFF;
        end
        else if (value_i < -32'sd32768) begin
            return 16'sh8000;
        end
        else begin
            return value_i[DATA_DWIDTH-1:0];
        end
    endfunction

    // Wire Declarations
    logic signed [DATA_DWIDTH-1:0]           ifmap_in_w;
    logic                                    ifmap_valid_w;

    logic signed [(2*DATA_DWIDTH)-1:0]       mult_full_w;
    logic signed [31:0]                      mult_q_w;
    logic signed [31:0]                      accumulator_w;

    // Register Declarations
    logic signed [31:0]                      accumulator_r;

    // Input Select (North has priority over East)
    assign ifmap_in_w = north_ifmap_valid_i ? north_ifmap_i : 
                        east_ifmap_valid_i  ? east_ifmap_i  : {DATA_DWIDTH{1'b0}};

    assign ifmap_valid_w = north_ifmap_valid_i | east_ifmap_valid_i;

    // Multiply / MAC
    assign mult_full_w = (ifmap_valid_w && mem_weight_valid_i) ?
                         ($signed(ifmap_in_w) * $signed(mem_weight_i)) :
                         {((2*DATA_DWIDTH)){1'b0}};

    assign mult_q_w    = $signed(mult_full_w) >>> FRAC_BITS;

    // Accumulator Logic (Bias is loaded on mem_bias_valid_i)
    assign accumulator_w = mem_bias_valid_i ?
                           ($signed({{16{mem_bias_i[DATA_DWIDTH-1]}}, mem_bias_i}) + mult_q_w) :
                           (accumulator_r + mult_q_w);

    // Rounded Arithmetic Right Shift of Accumulator
    logic signed [31:0] shifted_accumulator_w;
    always_comb begin
        if (shift_i == 4'd0) begin
            shifted_accumulator_w = accumulator_w;
        end else begin
            shifted_accumulator_w = (accumulator_w + (32'sd1 << (shift_i - 4'd1))) >>> shift_i;
        end
    end

    // Sequential Blocks
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            accumulator_r       <= 32'sd0;
            south_ifmap_o       <= {DATA_DWIDTH{1'b0}};
            south_ifmap_valid_o <= 1'b0;
            west_ifmap_o        <= {DATA_DWIDTH{1'b0}};
            west_ifmap_valid_o  <= 1'b0;
            mem_ofmap_o         <= {DATA_DWIDTH{1'b0}};
            mem_ofmap_valid_o   <= 1'b0;
        end
        else begin
            if (execute_i) begin
                if (ifmap_valid_w) begin
                    accumulator_r <= accumulator_w;
                end
                else begin
                    accumulator_r <= accumulator_r;
                end

                south_ifmap_o       <= ifmap_in_w;
                south_ifmap_valid_o <= ifmap_valid_w;

                west_ifmap_o        <= ifmap_in_w;
                west_ifmap_valid_o  <= ifmap_valid_w;

                if (last_ifmap_i && ifmap_valid_w) begin
                    mem_ofmap_o       <= sat_q16(shifted_accumulator_w);
                    mem_ofmap_valid_o <= 1'b1;
                end
                else begin
                    mem_ofmap_o       <= {DATA_DWIDTH{1'b0}};
                    mem_ofmap_valid_o <= 1'b0;
                end
            end
            else begin
                accumulator_r       <= 32'sd0;
                south_ifmap_o       <= {DATA_DWIDTH{1'b0}};
                south_ifmap_valid_o <= 1'b0;
                west_ifmap_o        <= {DATA_DWIDTH{1'b0}};
                west_ifmap_valid_o  <= 1'b0;
                mem_ofmap_o         <= {DATA_DWIDTH{1'b0}};
                mem_ofmap_valid_o   <= 1'b0;
            end
        end
    end

endmodule
