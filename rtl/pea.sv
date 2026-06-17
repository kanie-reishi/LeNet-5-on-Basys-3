`timescale 1 ns / 1 ps

module PEA_5x5 #(
    parameter DATA_DWIDTH = 16
)(
    input  wire                                  CLK,
    input  wire                                  RST,

    input  wire                                  weight_load_i,
    input  wire [2:0]                            row_weight_select_i,
    input  wire signed [(5*DATA_DWIDTH)-1:0]     row_weight_i,

    input  wire signed [(5*DATA_DWIDTH)-1:0]     FM_Bank1_ifmap_i,
    input  wire [4:0]                            FM_Bank1_ifmap_valid_i,

    input  wire                                  execute_i,

    output reg signed [(25*DATA_DWIDTH)-1:0]     product_o,
    output reg                                   product_valid_o
);
	//-------------------------------------//
    // Wire Declarations
    //-------------------------------------//
    wire [4:0] row_weight_load_w;
	wire signed [(25*DATA_DWIDTH)-1:0]    product_o_w;
    wire                                product_valid_w;

	//-------------------------------------//
    // Load Weight
    //-------------------------------------//
    assign row_weight_load_w[0] = weight_load_i && (row_weight_select_i == 3'd0);
    assign row_weight_load_w[1] = weight_load_i && (row_weight_select_i == 3'd1);
    assign row_weight_load_w[2] = weight_load_i && (row_weight_select_i == 3'd2);
    assign row_weight_load_w[3] = weight_load_i && (row_weight_select_i == 3'd3);
    assign row_weight_load_w[4] = weight_load_i && (row_weight_select_i == 3'd4);

    wire signed [DATA_DWIDTH-1:0]       ifmap_w       [0:4][0:5];
    wire                                ifmap_valid_w [0:4][0:5];
    wire signed [DATA_DWIDTH-1:0]       product_w     [0:4][0:4];

    genvar r, c;

    generate
        for (r = 0; r < 5; r = r + 1) begin : ROW_INPUT
            assign ifmap_w[r][5] =
                FM_Bank1_ifmap_i[(r*DATA_DWIDTH) +: DATA_DWIDTH];

            assign ifmap_valid_w[r][5] =
                FM_Bank1_ifmap_valid_i[r];
        end
    endgenerate

	//-------------------------------------//
    // PEA generation
    //-------------------------------------//
	
    generate
        for (r = 0; r < 5; r = r + 1) begin : PE_ROW
            for (c = 0; c < 5; c = c + 1) begin : PE_COL

                PE #(
                    .DATA_DWIDTH(DATA_DWIDTH)
                ) PE_inst (
                    .CLK(CLK),
                    .RST(RST),

                    .weight_load_i(row_weight_load_w[r]),
                    .weight_i(row_weight_i[(c*DATA_DWIDTH) +: DATA_DWIDTH]),

                    .PREV_PE_ifmap_i(ifmap_w[r][c+1]),
                    .PREV_PE_ifmap_valid_i(ifmap_valid_w[r][c+1]),

                    .NEXT_PE_ifmap_o(ifmap_w[r][c]),
                    .NEXT_PE_ifmap_valid_o(ifmap_valid_w[r][c]),

                    .execute_i(execute_i),

                    .product_o(product_w[r][c])
                );

                assign product_o_w[(((r*5+c)*DATA_DWIDTH)) +: DATA_DWIDTH] =
                    product_w[r][c];

            end
        end
    endgenerate


    assign product_valid_w = execute_i &&  ifmap_valid_w[0][1];


    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            product_o       <= {25*DATA_DWIDTH{1'b0}};
            product_valid_o <= 1'b0;
        end
        else begin
            product_o = product_o_w;
            product_valid_o <= product_valid_w;
        end
    end

endmodule