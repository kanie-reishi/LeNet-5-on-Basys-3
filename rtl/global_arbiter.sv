`timescale 1 ns / 1 ps

module global_arbiter #(
    parameter int AWIDTH           = 10,
    parameter int INST_DWIDTH      = 64,
    parameter int AXI_WADDR_WIDTH  = 13,
    parameter int AXI_RADDR_WIDTH  = 13,
    parameter int AXI_WDATA_DWIDTH = 80,
    parameter int AXI_RDATA_DWIDTH = 80
)(
    input  logic                            CLK,
    input  logic                            RST, // Active-low asynchronous reset

    //================================//
    //          AXI-Lite Like         //
    //================================//
    input  logic [AXI_WADDR_WIDTH-1:0]      axi_waddr_i,
    input  logic [AXI_WDATA_DWIDTH-1:0]     axi_wdata_i,
    input  logic                            axi_wvalid_i,

    input  logic [AXI_RADDR_WIDTH-1:0]      axi_raddr_i,
    input  logic                            axi_arvalid_i,
    output logic [AXI_RDATA_DWIDTH-1:0]     axi_rdata_o,

    //================================//
    //        Direct Control Path      //
    //================================//
    input  logic                            direct_load_i,
    input  logic                            direct_start_i,
    input  logic                            direct_done_i,

    //================================//
    //         From Controller        //
    //================================//
    input  logic [2:0]                      state_i,
    input  logic                            completed_i,

    //================================//
    //         To Controller          //
    //================================//
    output logic                            load_flag_o,
    output logic                            start_flag_o,
    output logic                            done_flag_o,
    output logic [AWIDTH-1:0]               max_IM_addr_o,

    //================================//
    //        To Instruction Mem      //
    //================================//
    output logic                            arbiter_IM_wvalid_o,
    output logic [AWIDTH-1:0]               arbiter_IM_waddr_o,
    output logic [INST_DWIDTH-1:0]          arbiter_IM_wdata_o,

    //================================//
    //         To Ping FM Mem         //
    //================================//
    output logic                            arbiter_Ping_FM_wvalid_o,
    output logic [AWIDTH-1:0]               arbiter_Ping_FM_waddr_o,
    output logic [AXI_WDATA_DWIDTH-1:0]     arbiter_Ping_FM_wdata_o,

    output logic                            arbiter_Ping_FM_arvalid_o,
    output logic [AWIDTH-1:0]               arbiter_Ping_FM_raddr_o,
    input  logic [AXI_RDATA_DWIDTH-1:0]     arbiter_Ping_FM_rdata_i,

    //================================//
    //         To Pong FM Mem         //
    //================================//
    output logic                            arbiter_Pong_FM_wvalid_o,
    output logic [AWIDTH-1:0]               arbiter_Pong_FM_waddr_o,
    output logic [AXI_WDATA_DWIDTH-1:0]     arbiter_Pong_FM_wdata_o,

    output logic                            arbiter_Pong_FM_arvalid_o,
    output logic [AWIDTH-1:0]               arbiter_Pong_FM_raddr_o,
    input  logic [AXI_RDATA_DWIDTH-1:0]     arbiter_Pong_FM_rdata_i,

    //================================//
    //        To Weight Memory        //
    //================================//
    output logic                            arbiter_WM_wvalid_o,
    output logic [AWIDTH-1:0]               arbiter_WM_waddr_o,
    output logic [AXI_WDATA_DWIDTH-1:0]     arbiter_WM_wdata_o,

    //================================//
    //         To Bias Memory         //
    //================================//
    output logic                            arbiter_BM_wvalid_o,
    output logic [AWIDTH-1:0]               arbiter_BM_waddr_o,
    output logic [AXI_WDATA_DWIDTH-1:0]     arbiter_BM_wdata_o
);

    //-------------------------------------//
    //            Localparams              //
    //-------------------------------------//
    typedef enum logic [2:0] {
        s_IDLE   = 3'd0,
        s_LOAD   = 3'd1,
        s_FETCH  = 3'd2,
        s_DECODE = 3'd3,
        s_EXEC   = 3'd4,
        s_READ   = 3'd5
    } state_t;

    localparam [2:0] AXI_WADDR_LOAD      = 3'd0;
    localparam [2:0] AXI_WADDR_START     = 3'd1;
    localparam [2:0] AXI_WADDR_DONE      = 3'd2;
    localparam [2:0] AXI_WADDR_PING_FMAP = 3'd3;
    localparam [2:0] AXI_WADDR_PONG_FMAP = 3'd4;
    localparam [2:0] AXI_WADDR_WEIGHT    = 3'd5;
    localparam [2:0] AXI_WADDR_BIAS      = 3'd6;
    localparam [2:0] AXI_WADDR_INST      = 3'd7;

    localparam [2:0] AXI_RADDR_COMPLETE  = 3'd0;
    localparam [2:0] AXI_RADDR_PING_FMAP = 3'd1;
    localparam [2:0] AXI_RADDR_PONG_FMAP = 3'd2;
    localparam [2:0] AXI_RADDR_STATE     = 3'd3;

    //-------------------------------------//
    //          Wire Declarations          //
    //-------------------------------------//
    logic [2:0]                             axi_waddr_sel_w;
    logic [2:0]                             axi_raddr_sel_w;
    logic [2:0]                             axi_raddr_sel_delay_w;

    logic                                   axi_load_flag_w;
    logic                                   axi_start_flag_w;
    logic                                   axi_done_flag_w;

    logic                                   load_state_w;
    logic                                   read_state_w;

    logic [AXI_RADDR_WIDTH-1:0]             axi_raddr_r;
    logic [AWIDTH-1:0]                      max_IM_addr_r;

    //-------------------------------------//
    //               Decode               //
    //-------------------------------------//
    assign axi_waddr_sel_w        = axi_waddr_i[AXI_WADDR_WIDTH-1:AWIDTH];
    assign axi_raddr_sel_w        = axi_raddr_i[AXI_RADDR_WIDTH-1:AWIDTH];
    assign axi_raddr_sel_delay_w  = axi_raddr_r[AXI_RADDR_WIDTH-1:AWIDTH];
 
    assign axi_load_flag_w        = axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_LOAD)  && axi_wdata_i[0];
    assign axi_start_flag_w       = axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_START) && axi_wdata_i[0];
    assign axi_done_flag_w        = axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_DONE)  && axi_wdata_i[0];

    assign load_flag_o            = direct_load_i  | axi_load_flag_w;
    assign start_flag_o           = direct_start_i | axi_start_flag_w;
    assign done_flag_o            = direct_done_i  | axi_done_flag_w;

    assign load_state_w           = (state_i == 3'd1); // s_LOAD
    assign read_state_w           = (state_i == 3'd6); // s_READ

    //-------------------------------------//
    //         Write Decode Path           //
    //-------------------------------------//
    assign arbiter_BM_wvalid_o      = load_state_w && axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_BIAS);
    assign arbiter_BM_waddr_o       = axi_waddr_i[AWIDTH-1:0];
    assign arbiter_BM_wdata_o       = axi_wdata_i;

    assign arbiter_WM_wvalid_o      = load_state_w && axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_WEIGHT);
    assign arbiter_WM_waddr_o       = axi_waddr_i[AWIDTH-1:0];
    assign arbiter_WM_wdata_o       = axi_wdata_i;

    assign arbiter_IM_wvalid_o      = load_state_w && axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_INST);
    assign arbiter_IM_waddr_o       = axi_waddr_i[AWIDTH-1:0];
    assign arbiter_IM_wdata_o       = axi_wdata_i[INST_DWIDTH-1:0];

    assign arbiter_Ping_FM_wvalid_o = load_state_w && axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_PING_FMAP);
    assign arbiter_Ping_FM_waddr_o  = axi_waddr_i[AWIDTH-1:0];
    assign arbiter_Ping_FM_wdata_o  = axi_wdata_i;

    assign arbiter_Pong_FM_wvalid_o = load_state_w && axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_PONG_FMAP);
    assign arbiter_Pong_FM_waddr_o  = axi_waddr_i[AWIDTH-1:0];
    assign arbiter_Pong_FM_wdata_o  = axi_wdata_i;

    //-------------------------------------//
    //           Read Decode Path          //
    //-------------------------------------//
    assign arbiter_Ping_FM_arvalid_o = read_state_w && axi_arvalid_i && (axi_raddr_sel_w == AXI_RADDR_PING_FMAP);
    assign arbiter_Ping_FM_raddr_o   = axi_raddr_i[AWIDTH-1:0];

    assign arbiter_Pong_FM_arvalid_o = read_state_w && axi_arvalid_i && (axi_raddr_sel_w == AXI_RADDR_PONG_FMAP);
    assign arbiter_Pong_FM_raddr_o   = axi_raddr_i[AWIDTH-1:0];

    //-------------------------------------//
    //           Max IM Address            //
    //-------------------------------------//
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            max_IM_addr_r <= {AWIDTH{1'b0}};
            axi_raddr_r   <= {AXI_RADDR_WIDTH{1'b0}};
        end
        else begin
            axi_raddr_r   <= axi_raddr_i;
            if (arbiter_IM_wvalid_o) begin
                if (arbiter_IM_waddr_o >= max_IM_addr_r) begin
                    max_IM_addr_r <= arbiter_IM_waddr_o;
                end
            end
        end
    end

    assign max_IM_addr_o = max_IM_addr_r;

    //-------------------------------------//
    //             AXI Read                //
    //-------------------------------------//
    always_comb begin
        case (axi_raddr_sel_delay_w)
            AXI_RADDR_COMPLETE:  axi_rdata_o = {{(AXI_RDATA_DWIDTH-1){1'b0}}, completed_i};
            AXI_RADDR_PING_FMAP: axi_rdata_o = arbiter_Ping_FM_rdata_i;
            AXI_RADDR_PONG_FMAP: axi_rdata_o = arbiter_Pong_FM_rdata_i;
            AXI_RADDR_STATE:     axi_rdata_o = {{(AXI_RDATA_DWIDTH-3){1'b0}}, state_i};
            default:             axi_rdata_o = {AXI_RDATA_DWIDTH{1'b0}};
        endcase
    end

endmodule
