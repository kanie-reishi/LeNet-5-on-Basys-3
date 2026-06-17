`timescale 1 ns / 1 ps

module Maxpooling #(
    parameter DATA_DWIDTH = 16,
    parameter NBANKS      = 5
)(
    input  wire                                      CLK,
    input  wire                                      RST,

    input  wire signed [(NBANKS*DATA_DWIDTH)-1:0]    fm_data_i,
    input  wire [NBANKS-1:0]                         fm_data_valid_i,

    input  wire [NBANKS-1:0]                         pool_wr_en_i,

    output reg  signed [(NBANKS*DATA_DWIDTH)-1:0]    pool_data_o,
    output reg  [NBANKS-1:0]                         pool_data_valid_o
);

    wire signed [DATA_DWIDTH-1:0] fm0_w;
    wire signed [DATA_DWIDTH-1:0] fm1_w;
    wire signed [DATA_DWIDTH-1:0] fm2_w;
    wire signed [DATA_DWIDTH-1:0] fm3_w;
    wire signed [DATA_DWIDTH-1:0] fm4_w;

    reg signed [DATA_DWIDTH-1:0] col0_0_r;
    reg signed [DATA_DWIDTH-1:0] col0_1_r;
    reg signed [DATA_DWIDTH-1:0] col0_2_r;
    reg signed [DATA_DWIDTH-1:0] col0_3_r;
    reg signed [DATA_DWIDTH-1:0] col0_4_r;

    reg [NBANKS-1:0] wr_mask_r;
    reg              col_phase_r;

    wire valid_w;

    wire signed [DATA_DWIDTH-1:0] h0_w;
    wire signed [DATA_DWIDTH-1:0] h1_w;
    wire signed [DATA_DWIDTH-1:0] h2_w;
    wire signed [DATA_DWIDTH-1:0] h3_w;
    wire signed [DATA_DWIDTH-1:0] h4_w;

    wire signed [DATA_DWIDTH-1:0] p01_w;
    wire signed [DATA_DWIDTH-1:0] p23_w;
    wire signed [DATA_DWIDTH-1:0] p40_w;
    wire signed [DATA_DWIDTH-1:0] p12_w;
    wire signed [DATA_DWIDTH-1:0] p34_w;

    wire [NBANKS-1:0] clean_wr_en_w;

    assign fm0_w = fm_data_i[(0*DATA_DWIDTH) +: DATA_DWIDTH];
    assign fm1_w = fm_data_i[(1*DATA_DWIDTH) +: DATA_DWIDTH];
    assign fm2_w = fm_data_i[(2*DATA_DWIDTH) +: DATA_DWIDTH];
    assign fm3_w = fm_data_i[(3*DATA_DWIDTH) +: DATA_DWIDTH];
    assign fm4_w = fm_data_i[(4*DATA_DWIDTH) +: DATA_DWIDTH];

    assign valid_w = |fm_data_valid_i;

    function signed [DATA_DWIDTH-1:0] max2;
        input signed [DATA_DWIDTH-1:0] a_i;
        input signed [DATA_DWIDTH-1:0] b_i;
        begin
            max2 = (a_i > b_i) ? a_i : b_i;
        end
    endfunction

    function [NBANKS-1:0] clean_mask;
        input [NBANKS-1:0] mask_i;
        integer i;
        begin
            clean_mask = {NBANKS{1'b0}};
            for (i = 0; i < NBANKS; i = i + 1) begin
                clean_mask[i] = (mask_i[i] === 1'b1) ? 1'b1 : 1'b0;
            end
        end
    endfunction

    assign clean_wr_en_w = clean_mask(pool_wr_en_i);

    assign h0_w = max2(col0_0_r, fm0_w);
    assign h1_w = max2(col0_1_r, fm1_w);
    assign h2_w = max2(col0_2_r, fm2_w);
    assign h3_w = max2(col0_3_r, fm3_w);
    assign h4_w = max2(col0_4_r, fm4_w);

    assign p01_w = max2(h0_w, h1_w);
    assign p23_w = max2(h2_w, h3_w);
    assign p40_w = max2(h4_w, h0_w);
    assign p12_w = max2(h1_w, h2_w);
    assign p34_w = max2(h3_w, h4_w);

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            col0_0_r          <= {DATA_DWIDTH{1'b0}};
            col0_1_r          <= {DATA_DWIDTH{1'b0}};
            col0_2_r          <= {DATA_DWIDTH{1'b0}};
            col0_3_r          <= {DATA_DWIDTH{1'b0}};
            col0_4_r          <= {DATA_DWIDTH{1'b0}};
            wr_mask_r         <= {NBANKS{1'b0}};
            col_phase_r       <= 1'b0;
            pool_data_o       <= {(NBANKS*DATA_DWIDTH){1'b0}};
            pool_data_valid_o <= {NBANKS{1'b0}};
        end
        else begin
            pool_data_o       <= {(NBANKS*DATA_DWIDTH){1'b0}};
            pool_data_valid_o <= {NBANKS{1'b0}};

            if (!valid_w) begin
                wr_mask_r   <= {NBANKS{1'b0}};
                col_phase_r <= 1'b0;
            end
            else if (!col_phase_r) begin
                col0_0_r    <= fm0_w;
                col0_1_r    <= fm1_w;
                col0_2_r    <= fm2_w;
                col0_3_r    <= fm3_w;
                col0_4_r    <= fm4_w;
                wr_mask_r   <= clean_wr_en_w;
                col_phase_r <= 1'b1;
            end
            else begin
                case (wr_mask_r)
                    5'b00011: begin
                        pool_data_o[(0*DATA_DWIDTH) +: DATA_DWIDTH] <= p01_w;
                        pool_data_o[(1*DATA_DWIDTH) +: DATA_DWIDTH] <= p23_w;
                    end

                    5'b01100: begin
                        pool_data_o[(2*DATA_DWIDTH) +: DATA_DWIDTH] <= p40_w;
                        pool_data_o[(3*DATA_DWIDTH) +: DATA_DWIDTH] <= p12_w;
                    end

                    5'b10001: begin
                        pool_data_o[(4*DATA_DWIDTH) +: DATA_DWIDTH] <= p34_w;
                        pool_data_o[(0*DATA_DWIDTH) +: DATA_DWIDTH] <= p01_w;
                    end

                    5'b00110: begin
                        pool_data_o[(1*DATA_DWIDTH) +: DATA_DWIDTH] <= p23_w;
                        pool_data_o[(2*DATA_DWIDTH) +: DATA_DWIDTH] <= p40_w;
                    end

                    5'b11000: begin
                        pool_data_o[(3*DATA_DWIDTH) +: DATA_DWIDTH] <= p12_w;
                        pool_data_o[(4*DATA_DWIDTH) +: DATA_DWIDTH] <= p34_w;
                    end

                    default: begin
                        pool_data_o <= {(NBANKS*DATA_DWIDTH){1'b0}};
                    end
                endcase

                pool_data_valid_o <= wr_mask_r;
                wr_mask_r         <= {NBANKS{1'b0}};
                col_phase_r       <= 1'b0;
            end
        end
    end

endmodule
