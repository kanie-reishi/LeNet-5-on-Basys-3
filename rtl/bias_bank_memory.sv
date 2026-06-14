`timescale 1 ns / 1 ps

module bias_bank_memory #(
    parameter int AWIDTH       = 10,
    parameter int DWIDTH       = 16,
    parameter int NBANKS       = 5,
    parameter int TOTAL_DWIDTH = NBANKS * DWIDTH
)(
    input  logic                         CLK,

    // From Arbiter
    input  logic                         arbiter_BM_wvalid_i,
    input  logic [AWIDTH-1:0]            arbiter_BM_waddr_i,
    input  logic [TOTAL_DWIDTH-1:0]      arbiter_BM_wdata_i,

    // From Controller
    input  logic                         ctrl_bank0_rd_en_i,
    input  logic                         ctrl_bank1_rd_en_i,
    input  logic                         ctrl_bank2_rd_en_i,
    input  logic                         ctrl_bank3_rd_en_i,
    input  logic                         ctrl_bank4_rd_en_i,

    input  logic [AWIDTH-1:0]            ctrl_bank0_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank1_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank2_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank3_addr_i,
    input  logic [AWIDTH-1:0]            ctrl_bank4_addr_i,

    // To PEA
    output logic [DWIDTH-1:0]            bank0_mem_bias_o,
    output logic [DWIDTH-1:0]            bank1_mem_bias_o,
    output logic [DWIDTH-1:0]            bank2_mem_bias_o,
    output logic [DWIDTH-1:0]            bank3_mem_bias_o,
    output logic [DWIDTH-1:0]            bank4_mem_bias_o,

    output logic                         bank0_mem_bias_valid_o,
    output logic                         bank1_mem_bias_valid_o,
    output logic                         bank2_mem_bias_valid_o,
    output logic                         bank3_mem_bias_valid_o,
    output logic                         bank4_mem_bias_valid_o
);

    // Dout wires from each BRAM bank
    logic [DWIDTH-1:0]                   bank0_dout_w;
    logic [DWIDTH-1:0]                   bank1_dout_w;
    logic [DWIDTH-1:0]                   bank2_dout_w;
    logic [DWIDTH-1:0]                   bank3_dout_w;
    logic [DWIDTH-1:0]                   bank4_dout_w;

    // Split input AXI write data for each bank
    logic [DWIDTH-1:0]                   arbiter_BM_wdata0_w;
    logic [DWIDTH-1:0]                   arbiter_BM_wdata1_w;
    logic [DWIDTH-1:0]                   arbiter_BM_wdata2_w;
    logic [DWIDTH-1:0]                   arbiter_BM_wdata3_w;
    logic [DWIDTH-1:0]                   arbiter_BM_wdata4_w;

    // Registers to pipeline the read enable signals (matching block RAM read latency)
    logic                                 ctrl_bank0_rd_en_r;
    logic                                 ctrl_bank1_rd_en_r;
    logic                                 ctrl_bank2_rd_en_r;
    logic                                 ctrl_bank3_rd_en_r;
    logic                                 ctrl_bank4_rd_en_r;

    // Split concatenated write data
    assign arbiter_BM_wdata0_w = arbiter_BM_wdata_i[DWIDTH*1-1:DWIDTH*0];
    assign arbiter_BM_wdata1_w = arbiter_BM_wdata_i[DWIDTH*2-1:DWIDTH*1];
    assign arbiter_BM_wdata2_w = arbiter_BM_wdata_i[DWIDTH*3-1:DWIDTH*2];
    assign arbiter_BM_wdata3_w = arbiter_BM_wdata_i[DWIDTH*4-1:DWIDTH*3];
    assign arbiter_BM_wdata4_w = arbiter_BM_wdata_i[DWIDTH*5-1:DWIDTH*4];

    // Pipeline read enables
    always_ff @(posedge CLK) begin
        ctrl_bank0_rd_en_r <= ctrl_bank0_rd_en_i;
        ctrl_bank1_rd_en_r <= ctrl_bank1_rd_en_i;
        ctrl_bank2_rd_en_r <= ctrl_bank2_rd_en_i;
        ctrl_bank3_rd_en_r <= ctrl_bank3_rd_en_i;
        ctrl_bank4_rd_en_r <= ctrl_bank4_rd_en_i;
    end

    // Assign valid outputs
    assign bank0_mem_bias_valid_o = ctrl_bank0_rd_en_r;
    assign bank1_mem_bias_valid_o = ctrl_bank1_rd_en_r;
    assign bank2_mem_bias_valid_o = ctrl_bank2_rd_en_r;
    assign bank3_mem_bias_valid_o = ctrl_bank3_rd_en_r;
    assign bank4_mem_bias_valid_o = ctrl_bank4_rd_en_r;

    // Assign output biases
    assign bank0_mem_bias_o = ctrl_bank0_rd_en_r ? bank0_dout_w : {DWIDTH{1'b0}};
    assign bank1_mem_bias_o = ctrl_bank1_rd_en_r ? bank1_dout_w : {DWIDTH{1'b0}};
    assign bank2_mem_bias_o = ctrl_bank2_rd_en_r ? bank2_dout_w : {DWIDTH{1'b0}};
    assign bank3_mem_bias_o = ctrl_bank3_rd_en_r ? bank3_dout_w : {DWIDTH{1'b0}};
    assign bank4_mem_bias_o = ctrl_bank4_rd_en_r ? bank4_dout_w : {DWIDTH{1'b0}};

    // Bank Instantiations
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank0 (
        .clka (CLK),
        .ena  (arbiter_BM_wvalid_i),
        .wea  (arbiter_BM_wvalid_i),
        .addra(arbiter_BM_waddr_i),
        .dina (arbiter_BM_wdata0_w),
        .douta(),

        .clkb (CLK),
        .enb  (ctrl_bank0_rd_en_i),
        .web  (1'b0),
        .addrb(ctrl_bank0_addr_i),
        .dinb ({DWIDTH{1'b0}}),
        .doutb(bank0_dout_w)
    );

    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank1 (
        .clka (CLK),
        .ena  (arbiter_BM_wvalid_i),
        .wea  (arbiter_BM_wvalid_i),
        .addra(arbiter_BM_waddr_i),
        .dina (arbiter_BM_wdata1_w),
        .douta(),

        .clkb (CLK),
        .enb  (ctrl_bank1_rd_en_i),
        .web  (1'b0),
        .addrb(ctrl_bank1_addr_i),
        .dinb ({DWIDTH{1'b0}}),
        .doutb(bank1_dout_w)
    );

    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank2 (
        .clka (CLK),
        .ena  (arbiter_BM_wvalid_i),
        .wea  (arbiter_BM_wvalid_i),
        .addra(arbiter_BM_waddr_i),
        .dina (arbiter_BM_wdata2_w),
        .douta(),

        .clkb (CLK),
        .enb  (ctrl_bank2_rd_en_i),
        .web  (1'b0),
        .addrb(ctrl_bank2_addr_i),
        .dinb ({DWIDTH{1'b0}}),
        .doutb(bank2_dout_w)
    );

    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank3 (
        .clka (CLK),
        .ena  (arbiter_BM_wvalid_i),
        .wea  (arbiter_BM_wvalid_i),
        .addra(arbiter_BM_waddr_i),
        .dina (arbiter_BM_wdata3_w),
        .douta(),

        .clkb (CLK),
        .enb  (ctrl_bank3_rd_en_i),
        .web  (1'b0),
        .addrb(ctrl_bank3_addr_i),
        .dinb ({DWIDTH{1'b0}}),
        .doutb(bank3_dout_w)
    );

    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bank4 (
        .clka (CLK),
        .ena  (arbiter_BM_wvalid_i),
        .wea  (arbiter_BM_wvalid_i),
        .addra(arbiter_BM_waddr_i),
        .dina (arbiter_BM_wdata4_w),
        .douta(),

        .clkb (CLK),
        .enb  (ctrl_bank4_rd_en_i),
        .web  (1'b0),
        .addrb(ctrl_bank4_addr_i),
        .dinb ({DWIDTH{1'b0}}),
        .doutb(bank4_dout_w)
    );

endmodule
