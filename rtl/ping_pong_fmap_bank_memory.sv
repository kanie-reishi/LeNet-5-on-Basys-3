`timescale 1 ns / 1 ps

module ping_pong_fmap_bank_memory #(
    parameter int AWIDTH       = 10,
    parameter int DWIDTH       = 16,
    parameter int NBANKS       = 5,
    parameter int TOTAL_DWIDTH = NBANKS * DWIDTH
)(
    input  logic                         CLK,

    // From Arbiter
    input  logic                         arbiter_FM_wvalid_i,
    input  logic [AWIDTH-1:0]            arbiter_FM_waddr_i,
    input  logic [TOTAL_DWIDTH-1:0]      arbiter_FM_wdata_i,

    input  logic                         arbiter_FM_arvalid_i,
    input  logic [AWIDTH-1:0]            arbiter_FM_raddr_i,
    output logic [TOTAL_DWIDTH-1:0]      arbiter_FM_rdata_o,

    // From Controller
    input  logic                         ctrl_bank0_rd_en_i,
    input  logic                         ctrl_bank1_rd_en_i,
    input  logic                         ctrl_bank2_rd_en_i,
    input  logic                         ctrl_bank3_rd_en_i,
    input  logic                         ctrl_bank4_rd_en_i,

    input  logic                         ctrl_bank0_wr_en_i,
    input  logic                         ctrl_bank1_wr_en_i,
    input  logic                         ctrl_bank2_wr_en_i,
    input  logic                         ctrl_bank3_wr_en_i,
    input  logic                         ctrl_bank4_wr_en_i,

    input  logic [AWIDTH-1:0]            ctrl_bank0_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank1_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank2_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank3_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank4_addr_i,

    // From PEA
    input  logic [DWIDTH-1:0]            bank0_mem_ofmap_i,
    input  logic [DWIDTH-1:0]            bank1_mem_ofmap_i,
    input  logic [DWIDTH-1:0]            bank2_mem_ofmap_i,
    input  logic [DWIDTH-1:0]            bank3_mem_ofmap_i,
    input  logic [DWIDTH-1:0]            bank4_mem_ofmap_i,

    input  logic                         bank0_mem_ofmap_valid_i,
    input  logic                         bank1_mem_ofmap_valid_i,
    input  logic                         bank2_mem_ofmap_valid_i,
    input  logic                         bank3_mem_ofmap_valid_i,
    input  logic                         bank4_mem_ofmap_valid_i,

    // To PEA
    output logic [DWIDTH-1:0]            bank0_mem_ifmap_o,
    output logic [DWIDTH-1:0]            bank1_mem_ifmap_o,
    output logic [DWIDTH-1:0]            bank2_mem_ifmap_o,
    output logic [DWIDTH-1:0]            bank3_mem_ifmap_o,
    output logic [DWIDTH-1:0]            bank4_mem_ifmap_o,

    output logic                         bank0_mem_ifmap_valid_o,
    output logic                         bank1_mem_ifmap_valid_o,
    output logic                         bank2_mem_ifmap_valid_o,
    output logic                         bank3_mem_ifmap_valid_o,
    output logic                         bank4_mem_ifmap_valid_o
);

    // Arbiter read path output wires
    logic [DWIDTH-1:0]                   arbiter_FM_dout0_w;
    logic [DWIDTH-1:0]                   arbiter_FM_dout1_w;
    logic [DWIDTH-1:0]                   arbiter_FM_dout2_w;
    logic [DWIDTH-1:0]                   arbiter_FM_dout3_w;
    logic [DWIDTH-1:0]                   arbiter_FM_dout4_w;

    // PEA/Controller read path output wires
    logic [DWIDTH-1:0]                   bank0_dout_w;
    logic [DWIDTH-1:0]                   bank1_dout_w;
    logic [DWIDTH-1:0]                   bank2_dout_w;
    logic [DWIDTH-1:0]                   bank3_dout_w;
    logic [DWIDTH-1:0]                   bank4_dout_w;

    // Arbiter split write data
    logic [DWIDTH-1:0]                   arbiter_FM_wdata0_w;
    logic [DWIDTH-1:0]                   arbiter_FM_wdata1_w;
    logic [DWIDTH-1:0]                   arbiter_FM_wdata2_w;
    logic [DWIDTH-1:0]                   arbiter_FM_wdata3_w;
    logic [DWIDTH-1:0]                   arbiter_FM_wdata4_w;

    // Write enables from controller & valid logic
    logic                                ctrl_bank0_we_w;
    logic                                ctrl_bank1_we_w;
    logic                                ctrl_bank2_we_w;
    logic                                ctrl_bank3_we_w;
    logic                                ctrl_bank4_we_w;

    // Total bank enable from controller
    logic                                ctrl_bank0_en_w;
    logic                                ctrl_bank1_en_w;
    logic                                ctrl_bank2_en_w;
    logic                                ctrl_bank3_en_w;
    logic                                ctrl_bank4_en_w;

    // Pipelined read enables for valid indicators
    logic                                ctrl_bank0_rd_en_r;
    logic                                ctrl_bank1_rd_en_r;
    logic                                ctrl_bank2_rd_en_r;
    logic                                ctrl_bank3_rd_en_r;
    logic                                ctrl_bank4_rd_en_r;

    // Split arbiter write data
    assign arbiter_FM_wdata0_w = arbiter_FM_wdata_i[DWIDTH*1-1:DWIDTH*0];
    assign arbiter_FM_wdata1_w = arbiter_FM_wdata_i[DWIDTH*2-1:DWIDTH*1];
    assign arbiter_FM_wdata2_w = arbiter_FM_wdata_i[DWIDTH*3-1:DWIDTH*2];
    assign arbiter_FM_wdata3_w = arbiter_FM_wdata_i[DWIDTH*4-1:DWIDTH*3];
    assign arbiter_FM_wdata4_w = arbiter_FM_wdata_i[DWIDTH*5-1:DWIDTH*4];

    // Combine output data for arbiter read operations
    assign arbiter_FM_rdata_o  = {arbiter_FM_dout4_w,
                                  arbiter_FM_dout3_w,
                                  arbiter_FM_dout2_w,
                                  arbiter_FM_dout1_w,
                                  arbiter_FM_dout0_w};

    // Controller write enable checks (only write if both write enable and data valid are asserted)
    assign ctrl_bank0_we_w     = ctrl_bank0_wr_en_i & bank0_mem_ofmap_valid_i;
    assign ctrl_bank1_we_w     = ctrl_bank1_wr_en_i & bank1_mem_ofmap_valid_i;
    assign ctrl_bank2_we_w     = ctrl_bank2_wr_en_i & bank2_mem_ofmap_valid_i;
    assign ctrl_bank3_we_w     = ctrl_bank3_wr_en_i & bank3_mem_ofmap_valid_i;
    assign ctrl_bank4_we_w     = ctrl_bank4_wr_en_i & bank4_mem_ofmap_valid_i;

    // Total access enable to Port B (either reading or writing)
    assign ctrl_bank0_en_w     = ctrl_bank0_rd_en_i | ctrl_bank0_we_w;
    assign ctrl_bank1_en_w     = ctrl_bank1_rd_en_i | ctrl_bank1_we_w;
    assign ctrl_bank2_en_w     = ctrl_bank2_rd_en_i | ctrl_bank2_we_w;
    assign ctrl_bank3_en_w     = ctrl_bank3_rd_en_i | ctrl_bank3_we_w;
    assign ctrl_bank4_en_w     = ctrl_bank4_rd_en_i | ctrl_bank4_we_w;

    // Pipeline read enables to match BRAM read latency (1 cycle)
    always_ff @(posedge CLK) begin
        ctrl_bank0_rd_en_r <= ctrl_bank0_rd_en_i;
        ctrl_bank1_rd_en_r <= ctrl_bank1_rd_en_i;
        ctrl_bank2_rd_en_r <= ctrl_bank2_rd_en_i;
        ctrl_bank3_rd_en_r <= ctrl_bank3_rd_en_i;
        ctrl_bank4_rd_en_r <= ctrl_bank4_rd_en_i;
    end

    // To PEA Read Path
    assign bank0_mem_ifmap_valid_o = ctrl_bank0_rd_en_r;
    assign bank1_mem_ifmap_valid_o = ctrl_bank1_rd_en_r;
    assign bank2_mem_ifmap_valid_o = ctrl_bank2_rd_en_r;
    assign bank3_mem_ifmap_valid_o = ctrl_bank3_rd_en_r;
    assign bank4_mem_ifmap_valid_o = ctrl_bank4_rd_en_r;

    assign bank0_mem_ifmap_o       = ctrl_bank0_rd_en_r ? bank0_dout_w : {DWIDTH{1'b0}};
    assign bank1_mem_ifmap_o       = ctrl_bank1_rd_en_r ? bank1_dout_w : {DWIDTH{1'b0}};
    assign bank2_mem_ifmap_o       = ctrl_bank2_rd_en_r ? bank2_dout_w : {DWIDTH{1'b0}};
    assign bank3_mem_ifmap_o       = ctrl_bank3_rd_en_r ? bank3_dout_w : {DWIDTH{1'b0}};
    assign bank4_mem_ifmap_o       = ctrl_bank4_rd_en_r ? bank4_dout_w : {DWIDTH{1'b0}};

    // Bank 0 Instantiation
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank0 (
        .clka (CLK),
        .ena  (arbiter_FM_wvalid_i | arbiter_FM_arvalid_i),
        .wea  (arbiter_FM_wvalid_i),
        .addra(arbiter_FM_wvalid_i ? arbiter_FM_waddr_i : arbiter_FM_raddr_i),
        .dina (arbiter_FM_wdata0_w),
        .douta(arbiter_FM_dout0_w),

        .clkb (CLK),
        .enb  (ctrl_bank0_en_w),
        .web  (ctrl_bank0_we_w),
        .addrb(ctrl_bank0_addr_i),
        .dinb (bank0_mem_ofmap_i),
        .doutb(bank0_dout_w)
    );

    // Bank 1 Instantiation
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank1 (
        .clka (CLK),
        .ena  (arbiter_FM_wvalid_i | arbiter_FM_arvalid_i),
        .wea  (arbiter_FM_wvalid_i),
        .addra(arbiter_FM_wvalid_i ? arbiter_FM_waddr_i : arbiter_FM_raddr_i),
        .dina (arbiter_FM_wdata1_w),
        .douta(arbiter_FM_dout1_w),

        .clkb (CLK),
        .enb  (ctrl_bank1_en_w),
        .web  (ctrl_bank1_we_w),
        .addrb(ctrl_bank1_addr_i),
        .dinb (bank1_mem_ofmap_i),
        .doutb(bank1_dout_w)
    );

    // Bank 2 Instantiation
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank2 (
        .clka (CLK),
        .ena  (arbiter_FM_wvalid_i | arbiter_FM_arvalid_i),
        .wea  (arbiter_FM_wvalid_i),
        .addra(arbiter_FM_wvalid_i ? arbiter_FM_waddr_i : arbiter_FM_raddr_i),
        .dina (arbiter_FM_wdata2_w),
        .douta(arbiter_FM_dout2_w),

        .clkb (CLK),
        .enb  (ctrl_bank2_en_w),
        .web  (ctrl_bank2_we_w),
        .addrb(ctrl_bank2_addr_i),
        .dinb (bank2_mem_ofmap_i),
        .doutb(bank2_dout_w)
    );

    // Bank 3 Instantiation
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank3 (
        .clka (CLK),
        .ena  (arbiter_FM_wvalid_i | arbiter_FM_arvalid_i),
        .wea  (arbiter_FM_wvalid_i),
        .addra(arbiter_FM_wvalid_i ? arbiter_FM_waddr_i : arbiter_FM_raddr_i),
        .dina (arbiter_FM_wdata3_w),
        .douta(arbiter_FM_dout3_w),

        .clkb (CLK),
        .enb  (ctrl_bank3_en_w),
        .web  (ctrl_bank3_we_w),
        .addrb(ctrl_bank3_addr_i),
        .dinb (bank3_mem_ofmap_i),
        .doutb(bank3_dout_w)
    );

    // Bank 4 Instantiation
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank4 (
        .clka (CLK),
        .ena  (arbiter_FM_wvalid_i | arbiter_FM_arvalid_i),
        .wea  (arbiter_FM_wvalid_i),
        .addra(arbiter_FM_wvalid_i ? arbiter_FM_waddr_i : arbiter_FM_raddr_i),
        .dina (arbiter_FM_wdata4_w),
        .douta(arbiter_FM_dout4_w),

        .clkb (CLK),
        .enb  (ctrl_bank4_en_w),
        .web  (ctrl_bank4_we_w),
        .addrb(ctrl_bank4_addr_i),
        .dinb (bank4_mem_ofmap_i),
        .doutb(bank4_dout_w)
    );

endmodule
