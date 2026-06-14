`timescale 1 ns / 1 ps

module instruction_memory #(
    parameter int AWIDTH = 10,
    parameter int DWIDTH = 64
)(
    input  logic                 CLK,

    // Port A (From Arbiter / Host Write Path)
    input  logic                 arbiter_IM_wvalid_i,
    input  logic [AWIDTH-1:0]    arbiter_IM_waddr_i,
    input  logic [DWIDTH-1:0]    arbiter_IM_wdata_i,

    // Port B (From Controller / Fetch Path)
    input  logic                 ctrl_rd_en_i,
    input  logic [AWIDTH-1:0]    ctrl_addr_i,

    // Outputs to Controller
    output logic [DWIDTH-1:0]    instruction_o,
    output logic                 instruction_valid_o
);

    // Dout wire from Port B of BRAM
    logic [DWIDTH-1:0]           instruction_dout_w;

    // Register to delay the read enable signal by 1 cycle to match BRAM latency
    logic                         ctrl_rd_en_r;

    assign instruction_o       = ctrl_rd_en_r ? instruction_dout_w : {DWIDTH{1'b0}};
    assign instruction_valid_o = ctrl_rd_en_r;

    // Delay line matching the read cycle latency
    always_ff @(posedge CLK) begin
        ctrl_rd_en_r <= ctrl_rd_en_i;
    end

    // TDP SRAM Instantiation
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_instruction_mem (
        .clka (CLK),
        .ena  (arbiter_IM_wvalid_i),
        .wea  (arbiter_IM_wvalid_i),
        .addra(arbiter_IM_waddr_i),
        .dina (arbiter_IM_wdata_i),
        .douta(),

        .clkb (CLK),
        .enb  (ctrl_rd_en_i),
        .web  (1'b0),
        .addrb(ctrl_addr_i),
        .dinb ({DWIDTH{1'b0}}),
        .doutb(instruction_dout_w)
    );

endmodule
