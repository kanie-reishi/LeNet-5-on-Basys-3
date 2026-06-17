`timescale 1 ns / 1 ps

module Bias_Memory #(
    parameter AWIDTH = 10,
    parameter DWIDTH = 16
)(
    input  wire                  CLK,

    //================================//
    //          From Arbiter          //
    //================================//
    input  wire                  arbiter_bias_wvalid_i,
    input  wire [AWIDTH-1:0]     arbiter_bias_waddr_i,
    input  wire [DWIDTH-1:0]     arbiter_bias_wdata_i,

    input  wire                  arbiter_bias_arvalid_i,
    input  wire [AWIDTH-1:0]     arbiter_bias_raddr_i,
    output wire [DWIDTH-1:0]     arbiter_bias_rdata_o,

    //================================//
    //         From Controller        //
    //================================//
    input  wire                  ctrl_bias_rd_en_i,
    input  wire [AWIDTH-1:0]     ctrl_bias_addr_i,

    //================================//
    //          To Adder / FC         //
    //================================//
    output wire [DWIDTH-1:0]     bias_data_o,
    output wire                  bias_valid_o
);

    //-------------------------------------//
    // Wire Declarations
    //-------------------------------------//
    wire [DWIDTH-1:0] bias_dout_w;

    //-------------------------------------//
    // Register Declarations
    //-------------------------------------//
    reg ctrl_bias_rd_en_r;

    //-------------------------------------//
    // Read Valid Delay
    //-------------------------------------//
    always @(posedge CLK) begin
        ctrl_bias_rd_en_r <= ctrl_bias_rd_en_i;
    end

    //-------------------------------------//
    // Output
    //-------------------------------------//
    assign bias_valid_o = ctrl_bias_rd_en_r;
    assign bias_data_o  = ctrl_bias_rd_en_r ? bias_dout_w : {DWIDTH{1'b0}};

    //-------------------------------------//
    // 1 Bias Bank
    //-------------------------------------//
    Dual_Port_BRAM #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bias_bank (
        .clka  (CLK),
        .ena   (arbiter_bias_wvalid_i | arbiter_bias_arvalid_i),
        .wea   (arbiter_bias_wvalid_i),
        .addra (arbiter_bias_wvalid_i ? arbiter_bias_waddr_i : arbiter_bias_raddr_i),
        .dina  (arbiter_bias_wdata_i),
        .douta (arbiter_bias_rdata_o),

        .clkb  (CLK),
        .enb   (ctrl_bias_rd_en_i),
        .web   (1'b0),
        .addrb (ctrl_bias_addr_i),
        .dinb  ({DWIDTH{1'b0}}),
        .doutb (bias_dout_w)
    );

endmodule