`timescale 1 ns / 1 ps

module Global_Arbiter #(
    parameter AXI_ADDR_WIDTH    = 13,
    parameter AXI_DATA_DWIDTH   = 16,
    parameter MEM_ADDR_WIDTH    = 10,
    parameter MEM_DATA_DWIDTH   = 80,
    parameter DWIDTH            = 16,
    parameter NBANKS            = 5
)(
    input  wire                         CLK,
    input  wire                         RST,

    input  wire [AXI_ADDR_WIDTH-1:0]    axi_waddr_i,
    input  wire [AXI_DATA_DWIDTH-1:0]   axi_wdata_i,
    input  wire                         axi_wvalid_i,

    input  wire [AXI_ADDR_WIDTH-1:0]    axi_raddr_i,
    input  wire                         axi_arvalid_i,
    output reg  [AXI_DATA_DWIDTH-1:0]   axi_rdata_o,

    input  wire [2:0]                   ctrl_state_i,
    input  wire                         ctrl_done_i,
    input  wire                         predict_valid_i,
    input  wire [3:0]                   predict_value_i,

    output reg                          load_done_o,
    output reg                          start_o,
    output reg                          done_clear_o,

    output reg                          ping_fm_wvalid_o,
    output reg  [MEM_ADDR_WIDTH-1:0]    ping_fm_waddr_o,
    output reg  [MEM_DATA_DWIDTH-1:0]   ping_fm_wdata_o,
    output wire                         ping_fm_arvalid_o,
    output wire [MEM_ADDR_WIDTH-1:0]    ping_fm_raddr_o,
    input  wire [MEM_DATA_DWIDTH-1:0]   ping_fm_rdata_i,

    output reg                          pong_fm_wvalid_o,
    output reg  [MEM_ADDR_WIDTH-1:0]    pong_fm_waddr_o,
    output reg  [MEM_DATA_DWIDTH-1:0]   pong_fm_wdata_o,
    output wire                         pong_fm_arvalid_o,
    output wire [MEM_ADDR_WIDTH-1:0]    pong_fm_raddr_o,
    input  wire [MEM_DATA_DWIDTH-1:0]   pong_fm_rdata_i,

    output reg                          weight_wvalid_o,
    output reg  [MEM_ADDR_WIDTH-1:0]    weight_waddr_o,
    output reg  [MEM_DATA_DWIDTH-1:0]   weight_wdata_o,

    output wire                         bias_wvalid_o,
    output wire [MEM_ADDR_WIDTH-1:0]    bias_waddr_o,
    output wire [DWIDTH-1:0]            bias_wdata_o
);

    //-------------------------------------//
    // Address Map
    //-------------------------------------//
    localparam [2:0] W_LOAD_CTRL = 3'd0;
    localparam [2:0] W_START     = 3'd1;
    localparam [2:0] W_DONE_CLR  = 3'd2;
    localparam [2:0] W_PING_FM   = 3'd3;
    localparam [2:0] W_PONG_FM   = 3'd4;
    localparam [2:0] W_WEIGHT    = 3'd5;
    localparam [2:0] W_BIAS      = 3'd6;

    localparam [2:0] R_STATUS    = 3'd0;
    localparam [2:0] R_PING_FM   = 3'd1;
    localparam [2:0] R_PONG_FM   = 3'd2;

    //-------------------------------------//
    // Wire Declarations
    //-------------------------------------//
    wire [2:0] w_sel_w;
    wire [2:0] r_sel_w;

    localparam AXI_WORD_ADDR_WIDTH = AXI_ADDR_WIDTH - 3;

    wire [AXI_WORD_ADDR_WIDTH-1:0] axi_word_addr_w;
    wire [MEM_ADDR_WIDTH-1:0] mem_pack_addr_w;
    wire [2:0]                bank_sel_w;

    wire write_ping_w;
    wire write_pong_w;
    wire write_weight_w;

    wire read_ping_w;
    wire read_pong_w;

    //-------------------------------------//
    // Register Declarations
    //-------------------------------------//
    reg [MEM_DATA_DWIDTH-1:0] ping_pack_r;
    reg [MEM_DATA_DWIDTH-1:0] pong_pack_r;
    reg [MEM_DATA_DWIDTH-1:0] weight_pack_r;

    reg [2:0]                 r_sel_d1_r;
    reg [2:0]                 r_bank_d1_r;

    //-------------------------------------//
    // Decode
    //-------------------------------------//
    // Address format is {3-bit region select, AXI_WORD_ADDR_WIDTH-bit linear word address}.
    // MEM_ADDR_WIDTH is the packed memory address width, not the AXI word-address width.
    assign w_sel_w         = axi_waddr_i[AXI_ADDR_WIDTH-1:AXI_WORD_ADDR_WIDTH];
    assign r_sel_w         = axi_raddr_i[AXI_ADDR_WIDTH-1:AXI_WORD_ADDR_WIDTH];

    assign axi_word_addr_w = axi_waddr_i[AXI_WORD_ADDR_WIDTH-1:0];
    assign mem_pack_addr_w = axi_word_addr_w / NBANKS;
    assign bank_sel_w      = axi_word_addr_w % NBANKS;

    assign write_ping_w    = axi_wvalid_i && (w_sel_w == W_PING_FM);
    assign write_pong_w    = axi_wvalid_i && (w_sel_w == W_PONG_FM);
    assign write_weight_w  = axi_wvalid_i && (w_sel_w == W_WEIGHT);

    assign bias_wvalid_o   = axi_wvalid_i && (w_sel_w == W_BIAS);
    assign bias_waddr_o    = axi_word_addr_w[MEM_ADDR_WIDTH-1:0];
    assign bias_wdata_o    = axi_wdata_i;

    assign read_ping_w     = 1'b0;
    assign read_pong_w     = 1'b0;

    //-------------------------------------//
    // Pulse Flags To Controller
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            load_done_o  <= 1'b0;
            start_o      <= 1'b0;
            done_clear_o <= 1'b0;
        end
        else begin
            if (axi_wvalid_i && (w_sel_w == W_LOAD_CTRL)) begin
                load_done_o <= axi_wdata_i[0];
            end
            else begin
                load_done_o <= 1'b0;
            end

            if (axi_wvalid_i && (w_sel_w == W_START)) begin
                start_o <= axi_wdata_i[0];
            end
            else begin
                start_o <= 1'b0;
            end

            if (axi_wvalid_i && (w_sel_w == W_DONE_CLR)) begin
                done_clear_o <= axi_wdata_i[0];
            end
            else begin
                done_clear_o <= 1'b0;
            end
        end
    end

    //-------------------------------------//
    // 16-bit AXI Write Packing To 5 Banks
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            ping_pack_r      <= {MEM_DATA_DWIDTH{1'b0}};
            pong_pack_r      <= {MEM_DATA_DWIDTH{1'b0}};
            weight_pack_r    <= {MEM_DATA_DWIDTH{1'b0}};

            ping_fm_wvalid_o <= 1'b0;
            ping_fm_waddr_o  <= {MEM_ADDR_WIDTH{1'b0}};
            ping_fm_wdata_o  <= {MEM_DATA_DWIDTH{1'b0}};

            pong_fm_wvalid_o <= 1'b0;
            pong_fm_waddr_o  <= {MEM_ADDR_WIDTH{1'b0}};
            pong_fm_wdata_o  <= {MEM_DATA_DWIDTH{1'b0}};

            weight_wvalid_o  <= 1'b0;
            weight_waddr_o   <= {MEM_ADDR_WIDTH{1'b0}};
            weight_wdata_o   <= {MEM_DATA_DWIDTH{1'b0}};
        end
        else begin
            ping_fm_wvalid_o <= 1'b0;
            pong_fm_wvalid_o <= 1'b0;
            weight_wvalid_o  <= 1'b0;

            if (write_ping_w) begin
                ping_pack_r[(bank_sel_w*DWIDTH) +: DWIDTH] <= axi_wdata_i;

                if (bank_sel_w == NBANKS-1) begin
                    ping_fm_wvalid_o <= 1'b1;
                    ping_fm_waddr_o  <= mem_pack_addr_w;
                    ping_fm_wdata_o  <= {axi_wdata_i,
                                          ping_pack_r[(3*DWIDTH) +: DWIDTH],
                                          ping_pack_r[(2*DWIDTH) +: DWIDTH],
                                          ping_pack_r[(1*DWIDTH) +: DWIDTH],
                                          ping_pack_r[(0*DWIDTH) +: DWIDTH]};
                end
            end

            if (write_pong_w) begin
                pong_pack_r[(bank_sel_w*DWIDTH) +: DWIDTH] <= axi_wdata_i;

                if (bank_sel_w == NBANKS-1) begin
                    pong_fm_wvalid_o <= 1'b1;
                    pong_fm_waddr_o  <= mem_pack_addr_w;
                    pong_fm_wdata_o  <= {axi_wdata_i,
                                          pong_pack_r[(3*DWIDTH) +: DWIDTH],
                                          pong_pack_r[(2*DWIDTH) +: DWIDTH],
                                          pong_pack_r[(1*DWIDTH) +: DWIDTH],
                                          pong_pack_r[(0*DWIDTH) +: DWIDTH]};
                end
            end

            if (write_weight_w) begin
                weight_pack_r[(bank_sel_w*DWIDTH) +: DWIDTH] <= axi_wdata_i;

                if (bank_sel_w == NBANKS-1) begin
                    weight_wvalid_o <= 1'b1;
                    weight_waddr_o  <= mem_pack_addr_w;
                    weight_wdata_o  <= {axi_wdata_i,
                                         weight_pack_r[(3*DWIDTH) +: DWIDTH],
                                         weight_pack_r[(2*DWIDTH) +: DWIDTH],
                                         weight_pack_r[(1*DWIDTH) +: DWIDTH],
                                         weight_pack_r[(0*DWIDTH) +: DWIDTH]};
                end
            end
        end
    end

    //-------------------------------------//
    // 16-bit AXI Read: prediction result only
    //-------------------------------------//
    // Any AXI read returns:
    //   bit [0]   : predict_valid_i
    //   bit [4:1] : predict_value_i
    // Other bits are zero.
    // The prediction registers are held in CNN_Core after ArgMax finishes.
    assign ping_fm_arvalid_o = 1'b0;
    assign pong_fm_arvalid_o = 1'b0;

    assign ping_fm_raddr_o   = {MEM_ADDR_WIDTH{1'b0}};
    assign pong_fm_raddr_o   = {MEM_ADDR_WIDTH{1'b0}};

    // Any AXI read returns (combinational — UART bridge samples after pipeline delay):
    //   bit [0]   : predict_valid_i
    //   bit [4:1] : predict_value_i
    always_comb begin
        axi_rdata_o        = {AXI_DATA_DWIDTH{1'b0}};
        axi_rdata_o[0]     = predict_valid_i;
        axi_rdata_o[4:1]   = predict_value_i;
    end

endmodule
