`timescale 1 ns / 1 ps

module sram_tdp #(
    parameter int AWIDTH = 10,
    parameter int DWIDTH = 32
)(
    // Port A
    input  logic                 clka,
    input  logic                 ena,
    input  logic                 wea,
    input  logic [AWIDTH-1:0]    addra,
    input  logic [DWIDTH-1:0]    dina,
    output logic [DWIDTH-1:0]    douta,

    // Port B
    input  logic                 clkb,
    input  logic                 enb,
    input  logic                 web,
    input  logic [AWIDTH-1:0]    addrb,
    input  logic [DWIDTH-1:0]    dinb,
    output logic [DWIDTH-1:0]    doutb
);

    // BRAM memory block style declaration
    (* ram_style = "block" *) 
    logic [DWIDTH-1:0] mem [0:(1 << AWIDTH)-1];

    // Initialization for simulation
    initial begin
        for (int i = 0; i < (1 << AWIDTH); i = i + 1) begin
            mem[i] = {DWIDTH{1'b0}};
        end
        douta = {DWIDTH{1'b0}};
        doutb = {DWIDTH{1'b0}};
    end

    // Port A (Read-First)
    always_ff @(posedge clka) begin
        if (ena) begin
            if (wea) begin
                mem[addra] <= dina;
            end
            douta <= mem[addra];
        end
        else begin
            douta <= {DWIDTH{1'b0}};
        end
    end

    // Port B (Read-First)
    always_ff @(posedge clkb) begin
        if (enb) begin
            if (web) begin
                mem[addrb] <= dinb;
            end
            doutb <= mem[addrb];
        end
        else begin
            doutb <= {DWIDTH{1'b0}};
        end
    end

endmodule
