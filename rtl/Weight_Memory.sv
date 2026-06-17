`timescale 1 ns / 1 ps

module Weight_Memory #(
    parameter AWIDTH       = 10,
    parameter DWIDTH       = 16,
    parameter NBANKS       = 5,
    parameter TOTAL_DWIDTH = NBANKS * DWIDTH
)(
    input  wire                         CLK,

    //================================//
    //          From Arbiter          //
    //================================//
    input  wire                         arbiter_weight_wvalid_i,
    input  wire [AWIDTH-1:0]            arbiter_weight_waddr_i,
    input  wire [TOTAL_DWIDTH-1:0]      arbiter_weight_wdata_i,

    input  wire                         arbiter_weight_arvalid_i,
    input  wire [AWIDTH-1:0]            arbiter_weight_raddr_i,
    output wire [TOTAL_DWIDTH-1:0]      arbiter_weight_rdata_o,

    //================================//
    //        From Controller         //
    //================================//
    input  wire                         ctrl_weight_rd_en_i,
    input  wire [AWIDTH-1:0]            ctrl_weight_addr_i,

    //================================//
    //           To PE / FC           //
    //================================//
    output wire [TOTAL_DWIDTH-1:0]      weight_data_o,
    output wire [NBANKS-1:0]            weight_valid_o
);

    wire [DWIDTH-1:0] arbiter_dout_w  [0:NBANKS-1];
    wire [DWIDTH-1:0] weight_dout_w   [0:NBANKS-1];
    wire [DWIDTH-1:0] arbiter_wdata_w [0:NBANKS-1];

    reg ctrl_weight_rd_en_r;

    genvar b;

    generate
        for (b = 0; b < NBANKS; b = b + 1) begin : UNPACK_PACK
            assign arbiter_wdata_w[b] =
                arbiter_weight_wdata_i[(b*DWIDTH) +: DWIDTH];

            assign arbiter_weight_rdata_o[(b*DWIDTH) +: DWIDTH] =
                arbiter_dout_w[b];

            assign weight_data_o[(b*DWIDTH) +: DWIDTH] =
                ctrl_weight_rd_en_r ? weight_dout_w[b] : {DWIDTH{1'b0}};

            assign weight_valid_o[b] =
                ctrl_weight_rd_en_r;
        end
    endgenerate

    always @(posedge CLK) begin
        ctrl_weight_rd_en_r <= ctrl_weight_rd_en_i;
    end

    generate
        for (b = 0; b < NBANKS; b = b + 1) begin : WEIGHT_BANK
            Dual_Port_BRAM #(
                .AWIDTH(AWIDTH),
                .DWIDTH(DWIDTH)
            ) u_weight_bank (
                .clka  (CLK),
                .ena   (arbiter_weight_wvalid_i | arbiter_weight_arvalid_i),
                .wea   (arbiter_weight_wvalid_i),
                .addra (arbiter_weight_wvalid_i ? arbiter_weight_waddr_i : arbiter_weight_raddr_i),
                .dina  (arbiter_wdata_w[b]),
                .douta (arbiter_dout_w[b]),

                .clkb  (CLK),
                .enb   (ctrl_weight_rd_en_i),
                .web   (1'b0),
                .addrb (ctrl_weight_addr_i),
                .dinb  ({DWIDTH{1'b0}}),
                .doutb (weight_dout_w[b])
            );
        end
    endgenerate

endmodule
