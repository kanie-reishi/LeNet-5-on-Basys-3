`timescale 1 ns / 1 ps

module ReLU #(
    parameter DATA_DWIDTH = 16
)(
    input  wire                              CLK,
    input  wire                              RST,

    input  wire signed [DATA_DWIDTH-1:0]     psum_i,
    input  wire                              psum_valid_i,

    input  wire                              last_channel_i,

    output reg  signed [DATA_DWIDTH-1:0]     fm_data_o,
    output reg                               fm_data_valid_o,
    output reg                               relu_applied_o
);

    //-------------------------------------//
    // Wire Declarations
    //-------------------------------------//
    wire signed [DATA_DWIDTH-1:0] relu_data_w;
    wire signed [DATA_DWIDTH-1:0] selected_data_w;

    //-------------------------------------//
    // ReLU Combinational Logic
    //-------------------------------------//
    assign relu_data_w =
        (psum_i[DATA_DWIDTH-1] == 1'b1) ?
        {DATA_DWIDTH{1'b0}} :
        psum_i;

    //-------------------------------------//
    // Output Data Selection
    //-------------------------------------//
    assign selected_data_w =
        last_channel_i ? relu_data_w : psum_i;

    //-------------------------------------//
    // Output Register
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            fm_data_o       <= {DATA_DWIDTH{1'b0}};
            fm_data_valid_o <= 1'b0;
            relu_applied_o  <= 1'b0;
        end
        else begin
            if (psum_valid_i) begin
                fm_data_o <= selected_data_w;
            end
            else begin
                fm_data_o <= {DATA_DWIDTH{1'b0}};
            end

            fm_data_valid_o <= psum_valid_i;
            relu_applied_o  <= psum_valid_i && last_channel_i;
        end
    end

endmodule