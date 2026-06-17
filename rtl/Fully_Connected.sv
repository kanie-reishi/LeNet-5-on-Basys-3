`timescale 1 ns / 1 ps

module Fully_Connected #(
    parameter DATA_DWIDTH = 16,
    parameter NBANKS      = 5
)(
    input  wire                                      CLK,
    input  wire                                      RST,

    input  wire signed [DATA_DWIDTH-1:0]             bias_i,
    input  wire                                      bias_valid_i,

    input  wire signed [(NBANKS*DATA_DWIDTH)-1:0]    ifm_data_i,
    input  wire        [NBANKS-1:0]                  ifm_valid_i,

    input  wire signed [(NBANKS*DATA_DWIDTH)-1:0]    weight_data_i,
    input  wire        [NBANKS-1:0]                  weight_valid_i,

    input  wire                                      data_valid_i,
    input  wire                                      last_chunk_i,
    input  wire                                      relu_en_i,

    output reg  signed [DATA_DWIDTH-1:0]             fc_data_o,
    output reg                                       fc_data_valid_o
);

    localparam FRAC_BITS = 8;

    localparam signed [DATA_DWIDTH-1:0] Q16_MAX = 16'sh7FFF;
    localparam signed [DATA_DWIDTH-1:0] Q16_MIN = 16'sh8000;

    // FC consumes only bank 0..3. Bank 4 is intentionally ignored because
    // Pool2 stores only four rows/banks (0..3), and FC weights are packed as
    // four useful values plus a zero pad in bank 4.
    wire signed [DATA_DWIDTH-1:0] ifm_w    [0:3];
    wire signed [DATA_DWIDTH-1:0] weight_w [0:3];

    wire signed [(2*DATA_DWIDTH)-1:0] mul_w [0:3];
    wire signed [31:0] contrib_w [0:3];

    wire data_fire_w;
    wire signed [DATA_DWIDTH-1:0] acc_base_w;
    wire signed [DATA_DWIDTH-1:0] acc_next_w;
    wire signed [DATA_DWIDTH-1:0] fc_out_w;

    reg signed [DATA_DWIDTH-1:0] acc_r;

    // Pipeline registers
    reg signed [31:0] contrib_sum_r;
    reg signed [DATA_DWIDTH-1:0] bias_r;
    reg                          bias_valid_r;
    reg                          data_valid_r;
    reg                          last_chunk_r;
    reg                          relu_en_r;
    reg        [3:0]             ifm_valid_r;
    reg        [3:0]             weight_valid_r;

    // Parallel adder tree in Cycle 1
    wire signed [31:0] contrib_sum_w = $signed(contrib_w[0]) + $signed(contrib_w[1]) + $signed(contrib_w[2]) + $signed(contrib_w[3]);

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            contrib_sum_r  <= 32'sd0;
            bias_r         <= {DATA_DWIDTH{1'b0}};
            bias_valid_r   <= 1'b0;
            data_valid_r   <= 1'b0;
            last_chunk_r   <= 1'b0;
            relu_en_r      <= 1'b0;
            ifm_valid_r    <= 4'b0;
            weight_valid_r <= 4'b0;
        end
        else begin
            contrib_sum_r  <= contrib_sum_w;
            bias_r         <= bias_i;
            bias_valid_r   <= bias_valid_i;
            data_valid_r   <= data_valid_i;
            last_chunk_r   <= last_chunk_i;
            relu_en_r      <= relu_en_i;
            ifm_valid_r    <= ifm_valid_i[3:0];
            weight_valid_r <= weight_valid_i[3:0];
        end
    end

    assign data_fire_w = data_valid_r && (&ifm_valid_r) && (&weight_valid_r);

    assign ifm_w[0] = ifm_data_i[(0*DATA_DWIDTH) +: DATA_DWIDTH];
    assign ifm_w[1] = ifm_data_i[(1*DATA_DWIDTH) +: DATA_DWIDTH];
    assign ifm_w[2] = ifm_data_i[(2*DATA_DWIDTH) +: DATA_DWIDTH];
    assign ifm_w[3] = ifm_data_i[(3*DATA_DWIDTH) +: DATA_DWIDTH];

    assign weight_w[0] = weight_data_i[(0*DATA_DWIDTH) +: DATA_DWIDTH];
    assign weight_w[1] = weight_data_i[(1*DATA_DWIDTH) +: DATA_DWIDTH];
    assign weight_w[2] = weight_data_i[(2*DATA_DWIDTH) +: DATA_DWIDTH];
    assign weight_w[3] = weight_data_i[(3*DATA_DWIDTH) +: DATA_DWIDTH];

    assign mul_w[0] = $signed(ifm_w[0]) * $signed(weight_w[0]);
    assign mul_w[1] = $signed(ifm_w[1]) * $signed(weight_w[1]);
    assign mul_w[2] = $signed(ifm_w[2]) * $signed(weight_w[2]);
    assign mul_w[3] = $signed(ifm_w[3]) * $signed(weight_w[3]);

    // Python equivalent: contrib = mul >> 8
    assign contrib_w[0] = $signed(mul_w[0]) >>> FRAC_BITS;
    assign contrib_w[1] = $signed(mul_w[1]) >>> FRAC_BITS;
    assign contrib_w[2] = $signed(mul_w[2]) >>> FRAC_BITS;
    assign contrib_w[3] = $signed(mul_w[3]) >>> FRAC_BITS;

    function signed [DATA_DWIDTH-1:0] sat16;
        input signed [31:0] x;
        begin
            if (x > 32'sd32767)
                sat16 = Q16_MAX;
            else if (x < -32'sd32768)
                sat16 = Q16_MIN;
            else
                sat16 = x[DATA_DWIDTH-1:0];
        end
    endfunction

    // On chunk 0, bias_valid_r and data_valid_r are allowed to rise together (delayed by 1 cycle).
    // In that cycle, use bias_r as the accumulator base and MAC the first chunk.
    assign acc_base_w = bias_valid_r ? bias_r : acc_r;

    // Single accumulation addition in 32-bit, followed by a single saturation block
    wire signed [31:0] acc_sum_w = $signed(acc_base_w) + contrib_sum_r;
    assign acc_next_w = sat16(acc_sum_w);

    assign fc_out_w =
        (relu_en_r && acc_next_w[DATA_DWIDTH-1]) ?
        {DATA_DWIDTH{1'b0}} :
        acc_next_w;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            acc_r           <= {DATA_DWIDTH{1'b0}};
            fc_data_o       <= {DATA_DWIDTH{1'b0}};
            fc_data_valid_o <= 1'b0;
        end
        else begin
            fc_data_valid_o <= 1'b0;

            if (data_fire_w) begin
                acc_r <= acc_next_w;

                if (last_chunk_r) begin
                    fc_data_o       <= fc_out_w;
                    fc_data_valid_o <= 1'b1;
                end
            end
            else if (bias_valid_r) begin
                acc_r <= bias_r;
            end
        end
    end

endmodule
