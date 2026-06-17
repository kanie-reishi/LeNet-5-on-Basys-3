`timescale 1 ns / 1 ps

module Dual_Port_BRAM
#(
    parameter AWIDTH = 10,
    parameter DWIDTH = 32
)
(
    input  wire                 clka,

    //================================//
    //             Port A             //
    //================================//
    input  wire                 ena,
    input  wire                 wea,
    input  wire [AWIDTH-1:0]    addra,
    input  wire [DWIDTH-1:0]    dina,
    output reg  [DWIDTH-1:0]    douta,

    //================================//
    //             Port B             //
    //================================//
    input  wire                 clkb,
    input  wire                 enb,
    input  wire                 web,
    input  wire [AWIDTH-1:0]    addrb,
    input  wire [DWIDTH-1:0]    dinb,
    output reg  [DWIDTH-1:0]    doutb
);

    //-------------------------------------//
    //         Register Declarations       //
    //-------------------------------------//
    (* ram_style = "block" *) reg [DWIDTH-1:0] mem [0:(1 << AWIDTH)-1];

    integer init_idx_r;

    //-------------------------------------//
    //            Initialization           //
    //-------------------------------------//
    initial begin
        for (init_idx_r = 0; init_idx_r < (1 << AWIDTH); init_idx_r = init_idx_r + 1) begin
            mem[init_idx_r] = {DWIDTH{1'b0}};
        end
        douta = {DWIDTH{1'b0}};
        doutb = {DWIDTH{1'b0}};
    end

    //-------------------------------------//
    //              Port A                //
    //-------------------------------------//
    always @(posedge clka) begin
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

    //-------------------------------------//
    //              Port B                //
    //-------------------------------------//
    always @(posedge clkb) begin
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
