`timescale 1 ns / 1 ps

module Ping_Pong_FM_Memory #(
    parameter AWIDTH       = 10,
    parameter DWIDTH       = 16,
    parameter NBANKS       = 5,
    parameter TOTAL_DWIDTH = NBANKS * DWIDTH
)(
    input  wire                         CLK,

    //================================//
    //          From Arbiter          //
    //================================//
    input  wire                         arbiter_FM_wvalid_i,
    input  wire [AWIDTH-1:0]            arbiter_FM_waddr_i,
    input  wire [TOTAL_DWIDTH-1:0]      arbiter_FM_wdata_i,

    input  wire                         arbiter_FM_arvalid_i,
    input  wire [AWIDTH-1:0]            arbiter_FM_raddr_i,
    output wire [TOTAL_DWIDTH-1:0]      arbiter_FM_rdata_o,

    //================================//
    //        From Controller         //
    //================================//
    input  wire                         ctrl_bank_rd_en_i,
    input  wire [(NBANKS*AWIDTH)-1:0]   ctrl_bank_raddr_i,
    input  wire [NBANKS-1:0]            ctrl_bank_wr_en_i,
    input  wire [(NBANKS*AWIDTH)-1:0]   ctrl_bank_waddr_i,

    //================================//
    //       From Datapath Writeback   //
    //================================//
    input  wire [TOTAL_DWIDTH-1:0]      pea_mem_ofmap_i,
    input  wire [NBANKS-1:0]            pea_mem_ofmap_valid_i,

    //================================//
    //      To Datapath / PEA / Pool   //
    //================================//
    output wire [TOTAL_DWIDTH-1:0]      mem_pea_ifmap_o,
    output wire [NBANKS-1:0]            mem_pea_ifmap_valid_o
);

    wire [DWIDTH-1:0] arbiter_dout_w  [0:NBANKS-1];
    wire [DWIDTH-1:0] bank_dout_w     [0:NBANKS-1];
    wire [DWIDTH-1:0] arbiter_wdata_w [0:NBANKS-1];
    wire [DWIDTH-1:0] pea_ofmap_w     [0:NBANKS-1];

    wire [NBANKS-1:0] ctrl_bank_we_w;
    wire [AWIDTH-1:0] ctrl_bank_raddr_w [0:NBANKS-1];
    wire [AWIDTH-1:0] ctrl_bank_waddr_w [0:NBANKS-1];

    reg ctrl_bank_rd_en_r;

    genvar b;

    generate
        for (b = 0; b < NBANKS; b = b + 1) begin : UNPACK_PACK
            assign arbiter_wdata_w[b] =
                arbiter_FM_wdata_i[(b*DWIDTH) +: DWIDTH];

            assign pea_ofmap_w[b] =
                pea_mem_ofmap_i[(b*DWIDTH) +: DWIDTH];

            assign arbiter_FM_rdata_o[(b*DWIDTH) +: DWIDTH] =
                arbiter_dout_w[b];

            assign mem_pea_ifmap_o[(b*DWIDTH) +: DWIDTH] =
                ctrl_bank_rd_en_r ? arbiter_dout_w[b] : {DWIDTH{1'b0}};

            assign mem_pea_ifmap_valid_o[b] =
                ctrl_bank_rd_en_r;

            assign ctrl_bank_raddr_w[b] =
                ctrl_bank_raddr_i[(b*AWIDTH) +: AWIDTH];

            assign ctrl_bank_waddr_w[b] =
                ctrl_bank_waddr_i[(b*AWIDTH) +: AWIDTH];

            assign ctrl_bank_we_w[b] =
                ctrl_bank_wr_en_i[b];
        end
    endgenerate

    always @(posedge CLK) begin
        ctrl_bank_rd_en_r <= ctrl_bank_rd_en_i;
    end

    generate
        for (b = 0; b < NBANKS; b = b + 1) begin : FM_BANK
            Dual_Port_BRAM #(
                .AWIDTH(AWIDTH),
                .DWIDTH(DWIDTH)
            ) u_fm_bank (
                .clka  (CLK),
                .ena   (arbiter_FM_wvalid_i | arbiter_FM_arvalid_i | ctrl_bank_rd_en_i),
                .wea   (arbiter_FM_wvalid_i),
                .addra (arbiter_FM_wvalid_i  ? arbiter_FM_waddr_i :
                        arbiter_FM_arvalid_i ? arbiter_FM_raddr_i :
                                               ctrl_bank_raddr_w[b]),
                .dina  (arbiter_wdata_w[b]),
                .douta (arbiter_dout_w[b]),

                .clkb  (CLK),
                .enb   (ctrl_bank_we_w[b]),
                .web   (ctrl_bank_we_w[b]),
                .addrb (ctrl_bank_waddr_w[b]),
                .dinb  (pea_ofmap_w[b]),
                .doutb (bank_dout_w[b])
            );
        end
    endgenerate

endmodule
