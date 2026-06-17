`timescale 1 ns / 1 ps
module ArgMax_4Bank #(
    parameter DATA_DWIDTH  = 16,
    parameter INDEX_DWIDTH = 4
)(
    input  wire                              CLK,
    input  wire                              RST,
    input  wire                              clear_i,
    input  wire [3:0]                        data_valid_i,
    input  wire [(4*DATA_DWIDTH)-1:0]        data_i,
    input  wire                              last_i,
    output reg  [INDEX_DWIDTH-1:0]           max_index_o,
    output reg  signed [DATA_DWIDTH-1:0]     max_value_o,
    output reg                               max_valid_o
);
    //----------------------------------------------------------------//
    // Stage 1: Level 1 comparisons and registration
    //----------------------------------------------------------------//
    wire signed [DATA_DWIDTH-1:0] d0_w = $signed(data_i[(0*DATA_DWIDTH) +: DATA_DWIDTH]);
    wire signed [DATA_DWIDTH-1:0] d1_w = $signed(data_i[(1*DATA_DWIDTH) +: DATA_DWIDTH]);
    wire signed [DATA_DWIDTH-1:0] d2_w = $signed(data_i[(2*DATA_DWIDTH) +: DATA_DWIDTH]);
    wire signed [DATA_DWIDTH-1:0] d3_w = $signed(data_i[(3*DATA_DWIDTH) +: DATA_DWIDTH]);
    reg [INDEX_DWIDTH-1:0] index_base_r;
    // Precompute absolute index offsets from index_base_r
    wire [INDEX_DWIDTH-1:0] idx0_w = index_base_r;
    wire [INDEX_DWIDTH-1:0] idx1_w = index_base_r + INDEX_DWIDTH'(1);
    wire [INDEX_DWIDTH-1:0] idx2_w = index_base_r + INDEX_DWIDTH'(2);
    wire [INDEX_DWIDTH-1:0] idx3_w = index_base_r + INDEX_DWIDTH'(3);
    // Level 1: Parallel pairwise comparison of input banks
    wire take01_w = data_valid_i[1] && (!data_valid_i[0] || (d1_w > d0_w));
    wire signed [DATA_DWIDTH-1:0] max01_w = take01_w ? d1_w : d0_w;
    wire [INDEX_DWIDTH-1:0] idx01_w = take01_w ? idx1_w : idx0_w;
    wire valid01_w = data_valid_i[0] || data_valid_i[1];
    wire take23_w = data_valid_i[3] && (!data_valid_i[2] || (d3_w > d2_w));
    wire signed [DATA_DWIDTH-1:0] max23_w = take23_w ? d3_w : d2_w;
    wire [INDEX_DWIDTH-1:0] idx23_w = take23_w ? idx3_w : idx2_w;
    wire valid23_w = data_valid_i[2] || data_valid_i[3];
    // Stage 1 pipeline registers
    reg signed [DATA_DWIDTH-1:0] max01_r;
    reg                          valid01_r;
    reg [INDEX_DWIDTH-1:0]       idx01_r;
    reg signed [DATA_DWIDTH-1:0] max23_r;
    reg                          valid23_r;
    reg [INDEX_DWIDTH-1:0]       idx23_r;
    reg                          last_s1_r;
    reg                          valid_in_s1_r;
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            max01_r       <= {DATA_DWIDTH{1'b0}};
            valid01_r     <= 1'b0;
            idx01_r       <= {INDEX_DWIDTH{1'b0}};
            max23_r       <= {DATA_DWIDTH{1'b0}};
            valid23_r     <= 1'b0;
            idx23_r       <= {INDEX_DWIDTH{1'b0}};
            last_s1_r     <= 1'b0;
            valid_in_s1_r <= 1'b0;
        end
        else if (clear_i) begin
            max01_r       <= {DATA_DWIDTH{1'b0}};
            valid01_r     <= 1'b0;
            idx01_r       <= {INDEX_DWIDTH{1'b0}};
            max23_r       <= {DATA_DWIDTH{1'b0}};
            valid23_r     <= 1'b0;
            idx23_r       <= {INDEX_DWIDTH{1'b0}};
            last_s1_r     <= 1'b0;
            valid_in_s1_r <= 1'b0;
        end
        else begin
            if (|data_valid_i) begin
                max01_r       <= max01_w;
                valid01_r     <= valid01_w;
                idx01_r       <= idx01_w;
                max23_r       <= max23_w;
                valid23_r     <= valid23_w;
                idx23_r       <= idx23_w;
                last_s1_r     <= last_i;
                valid_in_s1_r <= 1'b1;
            end
            else begin
                valid01_r     <= 1'b0;
                valid23_r     <= 1'b0;
                last_s1_r     <= 1'b0;
                valid_in_s1_r <= 1'b0;
            end
        end
    end
    //----------------------------------------------------------------//
    // Stage 2: Level 2 & Level 3 comparisons
    //----------------------------------------------------------------//
    // Level 2: Compare the two registered local maxes
    wire take_in_w = valid23_r && (!valid01_r || (max23_r > max01_r));
    wire signed [DATA_DWIDTH-1:0] max_in_w = take_in_w ? max23_r : max01_r;
    wire [INDEX_DWIDTH-1:0] idx_in_w = take_in_w ? idx23_r : idx01_r;
    wire valid_in_w = valid01_r || valid23_r;
    reg                    found_r;
    reg                    last_pending_r;
    // Level 3: Compare with the registered global max
    wire take_global_w = valid_in_w && (!found_r || (max_in_w > max_value_o));
    wire signed [DATA_DWIDTH-1:0] value3_w = take_global_w ? max_in_w : max_value_o;
    wire [INDEX_DWIDTH-1:0] index3_w = take_global_w ? idx_in_w : max_index_o;
    wire found3_w = found_r || valid_in_w;
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            index_base_r   <= {INDEX_DWIDTH{1'b0}};
            found_r        <= 1'b0;
            last_pending_r <= 1'b0;
            max_index_o    <= {INDEX_DWIDTH{1'b0}};
            max_value_o    <= {DATA_DWIDTH{1'b0}};
            max_valid_o    <= 1'b0;
        end
        else begin
            max_valid_o <= last_pending_r;
            last_pending_r <= 1'b0;
            if (clear_i) begin
                index_base_r   <= {INDEX_DWIDTH{1'b0}};
                found_r        <= 1'b0;
                last_pending_r <= 1'b0;
                max_index_o    <= {INDEX_DWIDTH{1'b0}};
                max_value_o    <= {DATA_DWIDTH{1'b0}};
                max_valid_o    <= 1'b0;
            end
            else begin
                if (|data_valid_i) begin
                    index_base_r <= index_base_r + INDEX_DWIDTH'(4);
                end
                if (valid_in_s1_r) begin
                    found_r     <= found3_w;
                    max_value_o <= value3_w;
                    max_index_o <= index3_w;
                    if (last_s1_r) begin
                        last_pending_r <= 1'b1;
                    end
                end
            end
        end
    end
endmodule