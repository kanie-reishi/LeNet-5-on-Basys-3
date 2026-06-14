`timescale 1 ns / 1 ps

module cnn_core #(
    parameter int AWIDTH           = 10,
    parameter int DWIDTH           = 16,
    parameter int INST_DWIDTH      = 64,
    parameter int AXI_WADDR_WIDTH  = 13,
    parameter int AXI_RADDR_WIDTH  = 13,
    parameter int AXI_WDATA_DWIDTH = 80,
    parameter int AXI_RDATA_DWIDTH = 80,
    parameter int FRAC_BITS        = 8
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
    output logic [AXI_RDATA_DWIDTH-1:0]     axi_rdata_o
);

    //-------------------------------------//
    //          Wire Declarations          //
    //-------------------------------------//
    logic                        load_flag_w;
    logic                        start_flag_w;
    logic                        done_flag_w;
    logic [AWIDTH-1:0]           max_IM_addr_w;
    logic [2:0]                  state_w;
    logic                        complete_w;

    // Instruction Memory
    logic                        arbiter_IM_wvalid_w;
    logic [AWIDTH-1:0]           arbiter_IM_waddr_w;
    logic [INST_DWIDTH-1:0]      arbiter_IM_wdata_w;
    logic                        ctrl_IM_rd_en_w;
    logic [AWIDTH-1:0]           ctrl_IM_addr_w;
    logic [INST_DWIDTH-1:0]      instruction_w;
    logic                        instruction_valid_w;

    // Weight Memory
    logic                        arbiter_WM_wvalid_w;
    logic [AWIDTH-1:0]           arbiter_WM_waddr_w;
    logic [AXI_WDATA_DWIDTH-1:0] arbiter_WM_wdata_w;

    logic                        ctrl_WM_bank0_rd_en_w;
    logic                        ctrl_WM_bank1_rd_en_w;
    logic                        ctrl_WM_bank2_rd_en_w;
    logic                        ctrl_WM_bank3_rd_en_w;
    logic                        ctrl_WM_bank4_rd_en_w;

    logic [AWIDTH-1:0]           ctrl_WM_bank0_addr_w;
    logic [AWIDTH-1:0]           ctrl_WM_bank1_addr_w;
    logic [AWIDTH-1:0]           ctrl_WM_bank2_addr_w;
    logic [AWIDTH-1:0]           ctrl_WM_bank3_addr_w;
    logic [AWIDTH-1:0]           ctrl_WM_bank4_addr_w;

    logic [DWIDTH-1:0]           bank0_mem_weight_w;
    logic [DWIDTH-1:0]           bank1_mem_weight_w;
    logic [DWIDTH-1:0]           bank2_mem_weight_w;
    logic [DWIDTH-1:0]           bank3_mem_weight_w;
    logic [DWIDTH-1:0]           bank4_mem_weight_w;

    logic                        bank0_mem_weight_valid_w;
    logic                        bank1_mem_weight_valid_w;
    logic                        bank2_mem_weight_valid_w;
    logic                        bank3_mem_weight_valid_w;
    logic                        bank4_mem_weight_valid_w;

    // Bias Memory
    logic                        arbiter_BM_wvalid_w;
    logic [AWIDTH-1:0]           arbiter_BM_waddr_w;
    logic [AXI_WDATA_DWIDTH-1:0] arbiter_BM_wdata_w;

    logic                        ctrl_BM_bank0_rd_en_w;
    logic                        ctrl_BM_bank1_rd_en_w;
    logic                        ctrl_BM_bank2_rd_en_w;
    logic                        ctrl_BM_bank3_rd_en_w;
    logic                        ctrl_BM_bank4_rd_en_w;

    logic [AWIDTH-1:0]           ctrl_BM_bank0_addr_w;
    logic [AWIDTH-1:0]           ctrl_BM_bank1_addr_w;
    logic [AWIDTH-1:0]           ctrl_BM_bank2_addr_w;
    logic [AWIDTH-1:0]           ctrl_BM_bank3_addr_w;
    logic [AWIDTH-1:0]           ctrl_BM_bank4_addr_w;

    logic [DWIDTH-1:0]           bank0_mem_bias_w;
    logic [DWIDTH-1:0]           bank1_mem_bias_w;
    logic [DWIDTH-1:0]           bank2_mem_bias_w;
    logic [DWIDTH-1:0]           bank3_mem_bias_w;
    logic [DWIDTH-1:0]           bank4_mem_bias_w;

    logic                        bank0_mem_bias_valid_w;
    logic                        bank1_mem_bias_valid_w;
    logic                        bank2_mem_bias_valid_w;
    logic                        bank3_mem_bias_valid_w;
    logic                        bank4_mem_bias_valid_w;

    // Ping Memory
    logic                        arbiter_Ping_FM_wvalid_w;
    logic [AWIDTH-1:0]           arbiter_Ping_FM_waddr_w;
    logic [AXI_WDATA_DWIDTH-1:0] arbiter_Ping_FM_wdata_w;
    logic                        arbiter_Ping_FM_arvalid_w;
    logic [AWIDTH-1:0]           arbiter_Ping_FM_raddr_w;
    logic [AXI_RDATA_DWIDTH-1:0] arbiter_Ping_FM_rdata_w;

    logic                        ctrl_Ping_FM_bank0_rd_en_w;
    logic                        ctrl_Ping_FM_bank1_rd_en_w;
    logic                        ctrl_Ping_FM_bank2_rd_en_w;
    logic                        ctrl_Ping_FM_bank3_rd_en_w;
    logic                        ctrl_Ping_FM_bank4_rd_en_w;

    logic                        ctrl_Ping_FM_bank0_wr_en_w;
    logic                        ctrl_Ping_FM_bank1_wr_en_w;
    logic                        ctrl_Ping_FM_bank2_wr_en_w;
    logic                        ctrl_Ping_FM_bank3_wr_en_w;
    logic                        ctrl_Ping_FM_bank4_wr_en_w;

    logic [AWIDTH-1:0]           ctrl_Ping_FM_bank0_addr_w;
    logic [AWIDTH-1:0]           ctrl_Ping_FM_bank1_addr_w;
    logic [AWIDTH-1:0]           ctrl_Ping_FM_bank2_addr_w;
    logic [AWIDTH-1:0]           ctrl_Ping_FM_bank3_addr_w;
    logic [AWIDTH-1:0]           ctrl_Ping_FM_bank4_addr_w;

    logic [DWIDTH-1:0]           ping_bank0_ifmap_w;
    logic [DWIDTH-1:0]           ping_bank1_ifmap_w;
    logic [DWIDTH-1:0]           ping_bank2_ifmap_w;
    logic [DWIDTH-1:0]           ping_bank3_ifmap_w;
    logic [DWIDTH-1:0]           ping_bank4_ifmap_w;

    logic                        ping_bank0_ifmap_valid_w;
    logic                        ping_bank1_ifmap_valid_w;
    logic                        ping_bank2_ifmap_valid_w;
    logic                        ping_bank3_ifmap_valid_w;
    logic                        ping_bank4_ifmap_valid_w;

    // Pong Memory
    logic                        arbiter_Pong_FM_wvalid_w;
    logic [AWIDTH-1:0]           arbiter_Pong_FM_waddr_w;
    logic [AXI_WDATA_DWIDTH-1:0] arbiter_Pong_FM_wdata_w;
    logic                        arbiter_Pong_FM_arvalid_w;
    logic [AWIDTH-1:0]           arbiter_Pong_FM_raddr_w;
    logic [AXI_RDATA_DWIDTH-1:0] arbiter_Pong_FM_rdata_w;

    logic                        ctrl_Pong_FM_bank0_rd_en_w;
    logic                        ctrl_Pong_FM_bank1_rd_en_w;
    logic                        ctrl_Pong_FM_bank2_rd_en_w;
    logic                        ctrl_Pong_FM_bank3_rd_en_w;
    logic                        ctrl_Pong_FM_bank4_rd_en_w;

    logic                        ctrl_Pong_FM_bank0_wr_en_w;
    logic                        ctrl_Pong_FM_bank1_wr_en_w;
    logic                        ctrl_Pong_FM_bank2_wr_en_w;
    logic                        ctrl_Pong_FM_bank3_wr_en_w;
    logic                        ctrl_Pong_FM_bank4_wr_en_w;

    logic [AWIDTH-1:0]           ctrl_Pong_FM_bank0_addr_w;
    logic [AWIDTH-1:0]           ctrl_Pong_FM_bank1_addr_w;
    logic [AWIDTH-1:0]           ctrl_Pong_FM_bank2_addr_w;
    logic [AWIDTH-1:0]           ctrl_Pong_FM_bank3_addr_w;
    logic [AWIDTH-1:0]           ctrl_Pong_FM_bank4_addr_w;

    logic [DWIDTH-1:0]           pong_bank0_ifmap_w;
    logic [DWIDTH-1:0]           pong_bank1_ifmap_w;
    logic [DWIDTH-1:0]           pong_bank2_ifmap_w;
    logic [DWIDTH-1:0]           pong_bank3_ifmap_w;
    logic [DWIDTH-1:0]           pong_bank4_ifmap_w;

    logic                        pong_bank0_ifmap_valid_w;
    logic                        pong_bank1_ifmap_valid_w;
    logic                        pong_bank2_ifmap_valid_w;
    logic                        pong_bank3_ifmap_valid_w;
    logic                        pong_bank4_ifmap_valid_w;

    // Feature Map Read Output Muxes (Direct 1-to-1 Mapping)
    logic [DWIDTH-1:0]           ifm_mem_bank0_w;
    logic [DWIDTH-1:0]           ifm_mem_bank1_w;
    logic [DWIDTH-1:0]           ifm_mem_bank2_w;
    logic [DWIDTH-1:0]           ifm_mem_bank3_w;
    logic [DWIDTH-1:0]           ifm_mem_bank4_w;

    logic                        ifm_mem_bank0_valid_w;
    logic                        ifm_mem_bank1_valid_w;
    logic                        ifm_mem_bank2_valid_w;
    logic                        ifm_mem_bank3_valid_w;
    logic                        ifm_mem_bank4_valid_w;

    // Line Buffer outputs
    logic                        lb_load_w;
    logic                        lb_shift_w;
    logic [DWIDTH-1:0]           lb_east_ifmap_w;
    logic                        lb_east_ifmap_valid_w;

    // PEA controls & outputs
    logic                        first_ifmap_w;
    logic                        last_ifmap_w;
    logic                        execute_w;
    logic                        ifm_from_north_w;
    logic [DWIDTH-1:0]           pea_east_ifmap_w;
    logic                        pea_east_ifmap_valid_w;

    logic [DWIDTH-1:0]           pea_bank0_ofmap_w;
    logic [DWIDTH-1:0]           pea_bank1_ofmap_w;
    logic [DWIDTH-1:0]           pea_bank2_ofmap_w;
    logic [DWIDTH-1:0]           pea_bank3_ofmap_w;
    logic [DWIDTH-1:0]           pea_bank4_ofmap_w;

    logic                        pea_bank0_ofmap_valid_w;
    logic                        pea_bank1_ofmap_valid_w;
    logic                        pea_bank2_ofmap_valid_w;
    logic                        pea_bank3_ofmap_valid_w;
    logic                        pea_bank4_ofmap_valid_w;

    // Decoded Layer config from Controller
    logic [3:0]                  layer_type_w;
    logic [11:0]                 in_channels_w;
    logic [11:0]                 out_channels_w;
    logic [7:0]                  activation_w;
    logic [3:0]                  right_shift_w;

    // Decode Right Shift value based on layer configuration
    always_comb begin
        if (layer_type_w == 4'h1) begin // CONV_2D
            if (in_channels_w == 12'd1 && out_channels_w == 12'd6)
                right_shift_w = 4'd12; // C1
            else if (in_channels_w == 12'd6 && out_channels_w == 12'd16)
                right_shift_w = 4'd10; // C3
            else if (in_channels_w == 12'd16 && out_channels_w == 12'd120)
                right_shift_w = 4'd9;  // C5
            else
                right_shift_w = 4'd0;
        end else if (layer_type_w == 4'h3) begin // FULLY_CONNECTED
            if (in_channels_w == 12'd120 && out_channels_w == 12'd84)
                right_shift_w = 4'd7;  // F6
            else
                right_shift_w = 4'd0;  // Output layer (84 -> 10)
        end else begin
            right_shift_w = 4'd0;
        end
    end

    // Post-Processed outputs
    logic [DWIDTH-1:0]           post_proc_bank0_w;
    logic [DWIDTH-1:0]           post_proc_bank1_w;
    logic [DWIDTH-1:0]           post_proc_bank2_w;
    logic [DWIDTH-1:0]           post_proc_bank3_w;
    logic [DWIDTH-1:0]           post_proc_bank4_w;

    logic                        post_proc_bank0_valid_w;
    logic                        post_proc_bank1_valid_w;
    logic                        post_proc_bank2_valid_w;
    logic                        post_proc_bank3_valid_w;
    logic                        post_proc_bank4_valid_w;

    // Pooler outputs
    logic [2:0]                  pool_step_w;
    logic [DWIDTH-1:0]           pool_bank0_w;
    logic [DWIDTH-1:0]           pool_bank1_w;
    logic [DWIDTH-1:0]           pool_bank2_w;
    logic [DWIDTH-1:0]           pool_bank3_w;
    logic [DWIDTH-1:0]           pool_bank4_w;

    logic                        pool_bank0_valid_w;
    logic                        pool_bank1_valid_w;
    logic                        pool_bank2_valid_w;
    logic                        pool_bank3_valid_w;
    logic                        pool_bank4_valid_w;

    // Multiplexed write path to Memories (Ping/Pong)
    logic [DWIDTH-1:0]           wr_bank0_ofmap_w;
    logic [DWIDTH-1:0]           wr_bank1_ofmap_w;
    logic [DWIDTH-1:0]           wr_bank2_ofmap_w;
    logic [DWIDTH-1:0]           wr_bank3_ofmap_w;
    logic [DWIDTH-1:0]           wr_bank4_ofmap_w;

    logic                        wr_bank0_ofmap_valid_w;
    logic                        wr_bank1_ofmap_valid_w;
    logic                        wr_bank2_ofmap_valid_w;
    logic                        wr_bank3_ofmap_valid_w;
    logic                        wr_bank4_ofmap_valid_w;

    //-------------------------------------//
    //           1-to-1 IFM Muxes          //
    //-------------------------------------//
    assign ifm_mem_bank0_w       = ping_bank0_ifmap_valid_w ? ping_bank0_ifmap_w : pong_bank0_ifmap_w;
    assign ifm_mem_bank1_w       = ping_bank1_ifmap_valid_w ? ping_bank1_ifmap_w : pong_bank1_ifmap_w;
    assign ifm_mem_bank2_w       = ping_bank2_ifmap_valid_w ? ping_bank2_ifmap_w : pong_bank2_ifmap_w;
    assign ifm_mem_bank3_w       = ping_bank3_ifmap_valid_w ? ping_bank3_ifmap_w : pong_bank3_ifmap_w;
    assign ifm_mem_bank4_w       = ping_bank4_ifmap_valid_w ? ping_bank4_ifmap_w : pong_bank4_ifmap_w;

    assign ifm_mem_bank0_valid_w = ping_bank0_ifmap_valid_w | pong_bank0_ifmap_valid_w;
    assign ifm_mem_bank1_valid_w = ping_bank1_ifmap_valid_w | pong_bank1_ifmap_valid_w;
    assign ifm_mem_bank2_valid_w = ping_bank2_ifmap_valid_w | pong_bank2_ifmap_valid_w;
    assign ifm_mem_bank3_valid_w = ping_bank3_ifmap_valid_w | pong_bank3_ifmap_valid_w;
    assign ifm_mem_bank4_valid_w = ping_bank4_ifmap_valid_w | pong_bank4_ifmap_valid_w;

    // PEA East Input Select
    assign pea_east_ifmap_w       = lb_load_w   ? ifm_mem_bank0_w :
                                    lb_shift_w  ? lb_east_ifmap_w : 16'sh0000;
    assign pea_east_ifmap_valid_w = lb_load_w   ? ifm_mem_bank0_valid_w :
                                    lb_shift_w  ? lb_east_ifmap_valid_w : 1'b0;

    //-------------------------------------//
    //           2-to-1 OFM Muxes          //
    //-------------------------------------//
    always_comb begin
        if (layer_type_w == 4'h2) begin // MAXPOOL_2D
            wr_bank0_ofmap_w = pool_bank0_w;
            wr_bank1_ofmap_w = pool_bank1_w;
            wr_bank2_ofmap_w = pool_bank2_w;
            wr_bank3_ofmap_w = pool_bank3_w;
            wr_bank4_ofmap_w = pool_bank4_w;

            wr_bank0_ofmap_valid_w = pool_bank0_valid_w;
            wr_bank1_ofmap_valid_w = pool_bank1_valid_w;
            wr_bank2_ofmap_valid_w = pool_bank2_valid_w;
            wr_bank3_ofmap_valid_w = pool_bank3_valid_w;
            wr_bank4_ofmap_valid_w = pool_bank4_valid_w;
        end else begin // CONV_2D or FULLY_CONNECTED
            wr_bank0_ofmap_w = post_proc_bank0_w;
            wr_bank1_ofmap_w = post_proc_bank1_w;
            wr_bank2_ofmap_w = post_proc_bank2_w;
            wr_bank3_ofmap_w = post_proc_bank3_w;
            wr_bank4_ofmap_w = post_proc_bank4_w;

            wr_bank0_ofmap_valid_w = post_proc_bank0_valid_w;
            wr_bank1_ofmap_valid_w = post_proc_bank1_valid_w;
            wr_bank2_ofmap_valid_w = post_proc_bank2_valid_w;
            wr_bank3_ofmap_valid_w = post_proc_bank3_valid_w;
            wr_bank4_ofmap_valid_w = post_proc_bank4_valid_w;
        end
    end

    //-------------------------------------//
    //         Module Instantiations       //
    //-------------------------------------//

    global_arbiter #(
        .AWIDTH          (AWIDTH),
        .INST_DWIDTH     (INST_DWIDTH),
        .AXI_WADDR_WIDTH (AXI_WADDR_WIDTH),
        .AXI_RADDR_WIDTH (AXI_RADDR_WIDTH),
        .AXI_WDATA_DWIDTH(AXI_WDATA_DWIDTH),
        .AXI_RDATA_DWIDTH(AXI_RDATA_DWIDTH)
    ) u_global_arbiter (
        .CLK                      (CLK),
        .RST                      (RST),
        .axi_waddr_i               (axi_waddr_i),
        .axi_wdata_i               (axi_wdata_i),
        .axi_wvalid_i              (axi_wvalid_i),
        .axi_raddr_i               (axi_raddr_i),
        .axi_arvalid_i             (axi_arvalid_i),
        .axi_rdata_o               (axi_rdata_o),
        .direct_load_i             (1'b0),
        .direct_start_i            (1'b0),
        .direct_done_i             (1'b0),
        .state_i                   (state_w),
        .completed_i               (complete_w),
        .load_flag_o               (load_flag_w),
        .start_flag_o              (start_flag_w),
        .done_flag_o               (done_flag_w),
        .max_IM_addr_o             (max_IM_addr_w),
        .arbiter_IM_wvalid_o       (arbiter_IM_wvalid_w),
        .arbiter_IM_waddr_o        (arbiter_IM_waddr_w),
        .arbiter_IM_wdata_o        (arbiter_IM_wdata_w),
        .arbiter_Ping_FM_wvalid_o  (arbiter_Ping_FM_wvalid_w),
        .arbiter_Ping_FM_waddr_o   (arbiter_Ping_FM_waddr_w),
        .arbiter_Ping_FM_wdata_o   (arbiter_Ping_FM_wdata_w),
        .arbiter_Ping_FM_arvalid_o (arbiter_Ping_FM_arvalid_w),
        .arbiter_Ping_FM_raddr_o   (arbiter_Ping_FM_raddr_w),
        .arbiter_Ping_FM_rdata_i   (arbiter_Ping_FM_rdata_w),
        .arbiter_Pong_FM_wvalid_o  (arbiter_Pong_FM_wvalid_w),
        .arbiter_Pong_FM_waddr_o   (arbiter_Pong_FM_waddr_w),
        .arbiter_Pong_FM_wdata_o   (arbiter_Pong_FM_wdata_w),
        .arbiter_Pong_FM_arvalid_o (arbiter_Pong_FM_arvalid_w),
        .arbiter_Pong_FM_raddr_o   (arbiter_Pong_FM_raddr_w),
        .arbiter_Pong_FM_rdata_i   (arbiter_Pong_FM_rdata_w),
        .arbiter_WM_wvalid_o       (arbiter_WM_wvalid_w),
        .arbiter_WM_waddr_o        (arbiter_WM_waddr_w),
        .arbiter_WM_wdata_o        (arbiter_WM_wdata_w),
        .arbiter_BM_wvalid_o       (arbiter_BM_wvalid_w),
        .arbiter_BM_waddr_o        (arbiter_BM_waddr_w),
        .arbiter_BM_wdata_o        (arbiter_BM_wdata_w)
    );

    controller #(
        .AWIDTH     (AWIDTH),
        .DWIDTH     (DWIDTH),
        .INST_DWIDTH(INST_DWIDTH)
    ) u_controller (
        .CLK                        (CLK),
        .RST                        (RST),
        .load_flag_i                (load_flag_w),
        .start_flag_i               (start_flag_w),
        .done_flag_i                (done_flag_w),
        .max_IM_addr_i              (max_IM_addr_w),
        .state_o                    (state_w),
        .complete_o                 (complete_w),
        .ctrl_WM_bank0_rd_en_o      (ctrl_WM_bank0_rd_en_w),
        .ctrl_WM_bank1_rd_en_o      (ctrl_WM_bank1_rd_en_w),
        .ctrl_WM_bank2_rd_en_o      (ctrl_WM_bank2_rd_en_w),
        .ctrl_WM_bank3_rd_en_o      (ctrl_WM_bank3_rd_en_w),
        .ctrl_WM_bank4_rd_en_o      (ctrl_WM_bank4_rd_en_w),
        .ctrl_WM_bank0_addr_o       (ctrl_WM_bank0_addr_w),
        .ctrl_WM_bank1_addr_o       (ctrl_WM_bank1_addr_w),
        .ctrl_WM_bank2_addr_o       (ctrl_WM_bank2_addr_w),
        .ctrl_WM_bank3_addr_o       (ctrl_WM_bank3_addr_w),
        .ctrl_WM_bank4_addr_o       (ctrl_WM_bank4_addr_w),
        .ctrl_BM_bank0_rd_en_o      (ctrl_BM_bank0_rd_en_w),
        .ctrl_BM_bank1_rd_en_o      (ctrl_BM_bank1_rd_en_w),
        .ctrl_BM_bank2_rd_en_o      (ctrl_BM_bank2_rd_en_w),
        .ctrl_BM_bank3_rd_en_o      (ctrl_BM_bank3_rd_en_w),
        .ctrl_BM_bank4_rd_en_o      (ctrl_BM_bank4_rd_en_w),
        .ctrl_BM_bank0_addr_o       (ctrl_BM_bank0_addr_w),
        .ctrl_BM_bank1_addr_o       (ctrl_BM_bank1_addr_w),
        .ctrl_BM_bank2_addr_o       (ctrl_BM_bank2_addr_w),
        .ctrl_BM_bank3_addr_o       (ctrl_BM_bank3_addr_w),
        .ctrl_BM_bank4_addr_o       (ctrl_BM_bank4_addr_w),
        .ctrl_IM_rd_en_o            (ctrl_IM_rd_en_w),
        .ctrl_IM_addr_o             (ctrl_IM_addr_w),
        .instruction_i              (instruction_w),
        .instruction_valid_i        (instruction_valid_w),
        .ctrl_Ping_FM_bank0_rd_en_o (ctrl_Ping_FM_bank0_rd_en_w),
        .ctrl_Ping_FM_bank1_rd_en_o (ctrl_Ping_FM_bank1_rd_en_w),
        .ctrl_Ping_FM_bank2_rd_en_o (ctrl_Ping_FM_bank2_rd_en_w),
        .ctrl_Ping_FM_bank3_rd_en_o (ctrl_Ping_FM_bank3_rd_en_w),
        .ctrl_Ping_FM_bank4_rd_en_o (ctrl_Ping_FM_bank4_rd_en_w),
        .ctrl_Ping_FM_bank0_wr_en_o (ctrl_Ping_FM_bank0_wr_en_w),
        .ctrl_Ping_FM_bank1_wr_en_o (ctrl_Ping_FM_bank1_wr_en_w),
        .ctrl_Ping_FM_bank2_wr_en_o (ctrl_Ping_FM_bank2_wr_en_w),
        .ctrl_Ping_FM_bank3_wr_en_o (ctrl_Ping_FM_bank3_wr_en_w),
        .ctrl_Ping_FM_bank4_wr_en_o (ctrl_Ping_FM_bank4_wr_en_w),
        .ctrl_Ping_FM_bank0_addr_o  (ctrl_Ping_FM_bank0_addr_w),
        .ctrl_Ping_FM_bank1_addr_o  (ctrl_Ping_FM_bank1_addr_w),
        .ctrl_Ping_FM_bank2_addr_o  (ctrl_Ping_FM_bank2_addr_w),
        .ctrl_Ping_FM_bank3_addr_o  (ctrl_Ping_FM_bank3_addr_w),
        .ctrl_Ping_FM_bank4_addr_o  (ctrl_Ping_FM_bank4_addr_w),
        .ctrl_Pong_FM_bank0_rd_en_o (ctrl_Pong_FM_bank0_rd_en_w),
        .ctrl_Pong_FM_bank1_rd_en_o (ctrl_Pong_FM_bank1_rd_en_w),
        .ctrl_Pong_FM_bank2_rd_en_o (ctrl_Pong_FM_bank2_rd_en_w),
        .ctrl_Pong_FM_bank3_rd_en_o (ctrl_Pong_FM_bank3_rd_en_w),
        .ctrl_Pong_FM_bank4_rd_en_o (ctrl_Pong_FM_bank4_rd_en_w),
        .ctrl_Pong_FM_bank0_wr_en_o (ctrl_Pong_FM_bank0_wr_en_w),
        .ctrl_Pong_FM_bank1_wr_en_o (ctrl_Pong_FM_bank1_wr_en_w),
        .ctrl_Pong_FM_bank2_wr_en_o (ctrl_Pong_FM_bank2_wr_en_w),
        .ctrl_Pong_FM_bank3_wr_en_o (ctrl_Pong_FM_bank3_wr_en_w),
        .ctrl_Pong_FM_bank4_wr_en_o (ctrl_Pong_FM_bank4_wr_en_w),
        .ctrl_Pong_FM_bank0_addr_o  (ctrl_Pong_FM_bank0_addr_w),
        .ctrl_Pong_FM_bank1_addr_o  (ctrl_Pong_FM_bank1_addr_w),
        .ctrl_Pong_FM_bank2_addr_o  (ctrl_Pong_FM_bank2_addr_w),
        .ctrl_Pong_FM_bank3_addr_o  (ctrl_Pong_FM_bank3_addr_w),
        .ctrl_Pong_FM_bank4_addr_o  (ctrl_Pong_FM_bank4_addr_w),
        .bank0_mem_ofmap_valid_i    (wr_bank0_ofmap_valid_w),
        .bank1_mem_ofmap_valid_i    (wr_bank1_ofmap_valid_w),
        .bank2_mem_ofmap_valid_i    (wr_bank2_ofmap_valid_w),
        .bank3_mem_ofmap_valid_i    (wr_bank3_ofmap_valid_w),
        .bank4_mem_ofmap_valid_i    (wr_bank4_ofmap_valid_w),
        .first_ifmap_o              (first_ifmap_w),
        .last_ifmap_o               (last_ifmap_w),
        .execute_o                  (execute_w),
        .ifm_from_north_o           (ifm_from_north_w),
        .line_buffer_load_o         (lb_load_w),
        .line_buffer_shift_o        (lb_shift_w),
        .pool_step_o                (pool_step_w),
        .layer_type_o               (layer_type_w),
        .in_channels_o              (in_channels_w),
        .out_channels_o             (out_channels_w),
        .activation_o               (activation_w)
    );

    instruction_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(INST_DWIDTH)
    ) u_instruction_memory (
        .CLK                (CLK),
        .arbiter_IM_wvalid_i(arbiter_IM_wvalid_w),
        .arbiter_IM_waddr_i (arbiter_IM_waddr_w),
        .arbiter_IM_wdata_i (arbiter_IM_wdata_w),
        .ctrl_rd_en_i       (ctrl_IM_rd_en_w),
        .ctrl_addr_i        (ctrl_IM_addr_w),
        .instruction_o      (instruction_w),
        .instruction_valid_o(instruction_valid_w)
    );

    weight_bank_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_weight_bank_memory (
        .CLK                    (CLK),
        .arbiter_WM_wvalid_i     (arbiter_WM_wvalid_w),
        .arbiter_WM_waddr_i      (arbiter_WM_waddr_w),
        .arbiter_WM_wdata_i      (arbiter_WM_wdata_w),
        .ctrl_bank0_rd_en_i      (ctrl_WM_bank0_rd_en_w),
        .ctrl_bank1_rd_en_i      (ctrl_WM_bank1_rd_en_w),
        .ctrl_bank2_rd_en_i      (ctrl_WM_bank2_rd_en_w),
        .ctrl_bank3_rd_en_i      (ctrl_WM_bank3_rd_en_w),
        .ctrl_bank4_rd_en_i      (ctrl_WM_bank4_rd_en_w),
        .ctrl_bank0_addr_i       (ctrl_WM_bank0_addr_w),
        .ctrl_bank1_addr_i       (ctrl_WM_bank1_addr_w),
        .ctrl_bank2_addr_i       (ctrl_WM_bank2_addr_w),
        .ctrl_bank3_addr_i       (ctrl_WM_bank3_addr_w),
        .ctrl_bank4_addr_i       (ctrl_WM_bank4_addr_w),
        .bank0_mem_weight_o      (bank0_mem_weight_w),
        .bank1_mem_weight_o      (bank1_mem_weight_w),
        .bank2_mem_weight_o      (bank2_mem_weight_w),
        .bank3_mem_weight_o      (bank3_mem_weight_w),
        .bank4_mem_weight_o      (bank4_mem_weight_w),
        .bank0_mem_weight_valid_o(bank0_mem_weight_valid_w),
        .bank1_mem_weight_valid_o(bank1_mem_weight_valid_w),
        .bank2_mem_weight_valid_o(bank2_mem_weight_valid_w),
        .bank3_mem_weight_valid_o(bank3_mem_weight_valid_w),
        .bank4_mem_weight_valid_o(bank4_mem_weight_valid_w)
    );

    bias_bank_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bias_bank_memory (
        .CLK                  (CLK),
        .arbiter_BM_wvalid_i  (arbiter_BM_wvalid_w),
        .arbiter_BM_waddr_i   (arbiter_BM_waddr_w),
        .arbiter_BM_wdata_i   (arbiter_BM_wdata_w),
        .ctrl_bank0_rd_en_i    (ctrl_BM_bank0_rd_en_w),
        .ctrl_bank1_rd_en_i    (ctrl_BM_bank1_rd_en_w),
        .ctrl_bank2_rd_en_i    (ctrl_BM_bank2_rd_en_w),
        .ctrl_bank3_rd_en_i    (ctrl_BM_bank3_rd_en_w),
        .ctrl_bank4_rd_en_i    (ctrl_BM_bank4_rd_en_w),
        .ctrl_bank0_addr_i     (ctrl_BM_bank0_addr_w),
        .ctrl_bank1_addr_i     (ctrl_BM_bank1_addr_w),
        .ctrl_bank2_addr_i     (ctrl_BM_bank2_addr_w),
        .ctrl_bank3_addr_i     (ctrl_BM_bank3_addr_w),
        .ctrl_bank4_addr_i     (ctrl_BM_bank4_addr_w),
        .bank0_mem_bias_o      (bank0_mem_bias_w),
        .bank1_mem_bias_o      (bank1_mem_bias_w),
        .bank2_mem_bias_o      (bank2_mem_bias_w),
        .bank3_mem_bias_o      (bank3_mem_bias_w),
        .bank4_mem_bias_o      (bank4_mem_bias_w),
        .bank0_mem_bias_valid_o(bank0_mem_bias_valid_w),
        .bank1_mem_bias_valid_o(bank1_mem_bias_valid_w),
        .bank2_mem_bias_valid_o(bank2_mem_bias_valid_w),
        .bank3_mem_bias_valid_o(bank3_mem_bias_valid_w),
        .bank4_mem_bias_valid_o(bank4_mem_bias_valid_w)
    );

    ping_pong_fmap_bank_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_ping_fmap_memory (
        .CLK                    (CLK),
        .arbiter_FM_wvalid_i    (arbiter_Ping_FM_wvalid_w),
        .arbiter_FM_waddr_i     (arbiter_Ping_FM_waddr_w),
        .arbiter_FM_wdata_i     (arbiter_Ping_FM_wdata_w),
        .arbiter_FM_arvalid_i   (arbiter_Ping_FM_arvalid_w),
        .arbiter_FM_raddr_i     (arbiter_Ping_FM_raddr_w),
        .arbiter_FM_rdata_o     (arbiter_Ping_FM_rdata_w),
        .ctrl_bank0_rd_en_i     (ctrl_Ping_FM_bank0_rd_en_w),
        .ctrl_bank1_rd_en_i     (ctrl_Ping_FM_bank1_rd_en_w),
        .ctrl_bank2_rd_en_i     (ctrl_Ping_FM_bank2_rd_en_w),
        .ctrl_bank3_rd_en_i     (ctrl_Ping_FM_bank3_rd_en_w),
        .ctrl_bank4_rd_en_i     (ctrl_Ping_FM_bank4_rd_en_w),
        .ctrl_bank0_wr_en_i     (ctrl_Ping_FM_bank0_wr_en_w),
        .ctrl_bank1_wr_en_i     (ctrl_Ping_FM_bank1_wr_en_w),
        .ctrl_bank2_wr_en_i     (ctrl_Ping_FM_bank2_wr_en_w),
        .ctrl_bank3_wr_en_i     (ctrl_Ping_FM_bank3_wr_en_w),
        .ctrl_bank4_wr_en_i     (ctrl_Ping_FM_bank4_wr_en_w),
        .ctrl_bank0_addr_i      (ctrl_Ping_FM_bank0_addr_w),
        .ctrl_bank1_addr_i      (ctrl_Ping_FM_bank1_addr_w),
        .ctrl_bank2_addr_i      (ctrl_Ping_FM_bank2_addr_w),
        .ctrl_bank3_addr_i      (ctrl_Ping_FM_bank3_addr_w),
        .ctrl_bank4_addr_i      (ctrl_Ping_FM_bank4_addr_w),
        .bank0_mem_ofmap_i      (wr_bank0_ofmap_w),
        .bank1_mem_ofmap_i      (wr_bank1_ofmap_w),
        .bank2_mem_ofmap_i      (wr_bank2_ofmap_w),
        .bank3_mem_ofmap_i      (wr_bank3_ofmap_w),
        .bank4_mem_ofmap_i      (wr_bank4_ofmap_w),
        .bank0_mem_ofmap_valid_i(wr_bank0_ofmap_valid_w),
        .bank1_mem_ofmap_valid_i(wr_bank1_ofmap_valid_w),
        .bank2_mem_ofmap_valid_i(wr_bank2_ofmap_valid_w),
        .bank3_mem_ofmap_valid_i(wr_bank3_ofmap_valid_w),
        .bank4_mem_ofmap_valid_i(wr_bank4_ofmap_valid_w),
        .bank0_mem_ifmap_o      (ping_bank0_ifmap_w),
        .bank1_mem_ifmap_o      (ping_bank1_ifmap_w),
        .bank2_mem_ifmap_o      (ping_bank2_ifmap_w),
        .bank3_mem_ifmap_o      (ping_bank3_ifmap_w),
        .bank4_mem_ifmap_o      (ping_bank4_ifmap_w),
        .bank0_mem_ifmap_valid_o(ping_bank0_ifmap_valid_w),
        .bank1_mem_ifmap_valid_o(ping_bank1_ifmap_valid_w),
        .bank2_mem_ifmap_valid_o(ping_bank2_ifmap_valid_w),
        .bank3_mem_ifmap_valid_o(ping_bank3_ifmap_valid_w),
        .bank4_mem_ifmap_valid_o(ping_bank4_ifmap_valid_w)
    );

    ping_pong_fmap_bank_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_pong_fmap_memory (
        .CLK                    (CLK),
        .arbiter_FM_wvalid_i    (arbiter_Pong_FM_wvalid_w),
        .arbiter_FM_waddr_i     (arbiter_Pong_FM_waddr_w),
        .arbiter_FM_wdata_i     (arbiter_Pong_FM_wdata_w),
        .arbiter_FM_arvalid_i   (arbiter_Pong_FM_arvalid_w),
        .arbiter_FM_raddr_i     (arbiter_Pong_FM_raddr_w),
        .arbiter_FM_rdata_o     (arbiter_Pong_FM_rdata_w),
        .ctrl_bank0_rd_en_i     (ctrl_Pong_FM_bank0_rd_en_w),
        .ctrl_bank1_rd_en_i     (ctrl_Pong_FM_bank1_rd_en_w),
        .ctrl_bank2_rd_en_i     (ctrl_Pong_FM_bank2_rd_en_w),
        .ctrl_bank3_rd_en_i     (ctrl_Pong_FM_bank3_rd_en_w),
        .ctrl_bank4_rd_en_i     (ctrl_Pong_FM_bank4_rd_en_w),
        .ctrl_bank0_wr_en_i     (ctrl_Pong_FM_bank0_wr_en_w),
        .ctrl_bank1_wr_en_i     (ctrl_Pong_FM_bank1_wr_en_w),
        .ctrl_bank2_wr_en_i     (ctrl_Pong_FM_bank2_wr_en_w),
        .ctrl_bank3_wr_en_i     (ctrl_Pong_FM_bank3_wr_en_w),
        .ctrl_bank4_wr_en_i     (ctrl_Pong_FM_bank4_wr_en_w),
        .ctrl_bank0_addr_i      (ctrl_Pong_FM_bank0_addr_w),
        .ctrl_bank1_addr_i      (ctrl_Pong_FM_bank1_addr_w),
        .ctrl_bank2_addr_i      (ctrl_Pong_FM_bank2_addr_w),
        .ctrl_bank3_addr_i      (ctrl_Pong_FM_bank3_addr_w),
        .ctrl_bank4_addr_i      (ctrl_Pong_FM_bank4_addr_w),
        .bank0_mem_ofmap_i      (wr_bank0_ofmap_w),
        .bank1_mem_ofmap_i      (wr_bank1_ofmap_w),
        .bank2_mem_ofmap_i      (wr_bank2_ofmap_w),
        .bank3_mem_ofmap_i      (wr_bank3_ofmap_w),
        .bank4_mem_ofmap_i      (wr_bank4_ofmap_w),
        .bank0_mem_ofmap_valid_i(wr_bank0_ofmap_valid_w),
        .bank1_mem_ofmap_valid_i(wr_bank1_ofmap_valid_w),
        .bank2_mem_ofmap_valid_i(wr_bank2_ofmap_valid_w),
        .bank3_mem_ofmap_valid_i(wr_bank3_ofmap_valid_w),
        .bank4_mem_ofmap_valid_i(wr_bank4_ofmap_valid_w),
        .bank0_mem_ifmap_o      (pong_bank0_ifmap_w),
        .bank1_mem_ifmap_o      (pong_bank1_ifmap_w),
        .bank2_mem_ifmap_o      (pong_bank2_ifmap_w),
        .bank3_mem_ifmap_o      (pong_bank3_ifmap_w),
        .bank4_mem_ifmap_o      (pong_bank4_ifmap_w),
        .bank0_mem_ifmap_valid_o(pong_bank0_ifmap_valid_w),
        .bank1_mem_ifmap_valid_o(pong_bank1_ifmap_valid_w),
        .bank2_mem_ifmap_valid_o(pong_bank2_ifmap_valid_w),
        .bank3_mem_ifmap_valid_o(pong_bank3_ifmap_valid_w),
        .bank4_mem_ifmap_valid_o(pong_bank4_ifmap_valid_w)
    );

    line_buffer #(
        .DWIDTH(DWIDTH)
    ) u_line_buffer (
        .CLK               (CLK),
        .RST               (RST),
        .load_i            (lb_load_w),
        .shift_en_i        (lb_shift_w),
        .ifm_bank0_i       (ifm_mem_bank0_w),
        .ifm_bank1_i       (ifm_mem_bank1_w),
        .ifm_bank2_i       (ifm_mem_bank2_w),
        .ifm_bank3_i       (ifm_mem_bank3_w),
        .ifm_bank4_i       (ifm_mem_bank4_w),
        .ifm_bank0_valid_i (ifm_mem_bank0_valid_w),
        .ifm_bank1_valid_i (ifm_mem_bank1_valid_w),
        .ifm_bank2_valid_i (ifm_mem_bank2_valid_w),
        .ifm_bank3_valid_i (ifm_mem_bank3_valid_w),
        .ifm_bank4_valid_i (ifm_mem_bank4_valid_w),
        .east_ifmap_o      (lb_east_ifmap_w),
        .east_ifmap_valid_o(lb_east_ifmap_valid_w)
    );

    pea #(
        .DATA_DWIDTH(DWIDTH),
        .FRAC_BITS  (FRAC_BITS)
    ) u_pea (
        .CLK                    (CLK),
        .RST                    (RST),
        .first_ifmap_i          (first_ifmap_w),
        .last_ifmap_i           (last_ifmap_w),
        .execute_i              (execute_w),
        .ifm_from_north_i        (ifm_from_north_w),
        .bank0_mem_ifmap_i       (ifm_mem_bank0_w),
        .bank0_mem_ifmap_valid_i (ifm_mem_bank0_valid_w),
        .bank1_mem_ifmap_i       (ifm_mem_bank1_w),
        .bank1_mem_ifmap_valid_i (ifm_mem_bank1_valid_w),
        .bank2_mem_ifmap_i       (ifm_mem_bank2_w),
        .bank2_mem_ifmap_valid_i (ifm_mem_bank2_valid_w),
        .bank3_mem_ifmap_i       (ifm_mem_bank3_w),
        .bank3_mem_ifmap_valid_i (ifm_mem_bank3_valid_w),
        .bank4_mem_ifmap_i       (ifm_mem_bank4_w),
        .bank4_mem_ifmap_valid_i (ifm_mem_bank4_valid_w),
        .east_ifmap_i            (pea_east_ifmap_w),
        .east_ifmap_valid_i      (pea_east_ifmap_valid_w),
        .row0_mem_weight_i       (bank0_mem_weight_w),
        .row0_mem_weight_valid_i (bank0_mem_weight_valid_w),
        .row1_mem_weight_i       (bank1_mem_weight_w),
        .row1_mem_weight_valid_i (bank1_mem_weight_valid_w),
        .row2_mem_weight_i       (bank2_mem_weight_w),
        .row2_mem_weight_valid_i (bank2_mem_weight_valid_w),
        .row3_mem_weight_i       (bank3_mem_weight_w),
        .row3_mem_weight_valid_i (bank3_mem_weight_valid_w),
        .row4_mem_weight_i       (bank4_mem_weight_w),
        .row4_mem_weight_valid_i (bank4_mem_weight_valid_w),
        .row0_mem_bias_i         (bank0_mem_bias_w),
        .row0_mem_bias_valid_i   (bank0_mem_bias_valid_w),
        .row1_mem_bias_i         (bank1_mem_bias_w),
        .row1_mem_bias_valid_i   (bank1_mem_bias_valid_w),
        .row2_mem_bias_i         (bank2_mem_bias_w),
        .row2_mem_bias_valid_i   (bank2_mem_bias_valid_w),
        .row3_mem_bias_i         (bank3_mem_bias_w),
        .row3_mem_bias_valid_i   (bank3_mem_bias_valid_w),
        .row4_mem_bias_i         (bank4_mem_bias_w),
        .row4_mem_bias_valid_i   (bank4_mem_bias_valid_w),
        .bank0_mem_ofmap_o       (pea_bank0_ofmap_w),
        .bank0_mem_ofmap_valid_o (pea_bank0_ofmap_valid_w),
        .bank1_mem_ofmap_o       (pea_bank1_ofmap_w),
        .bank1_mem_ofmap_valid_o (pea_bank1_ofmap_valid_w),
        .bank2_mem_ofmap_o       (pea_bank2_ofmap_w),
        .bank2_mem_ofmap_valid_o (pea_bank2_ofmap_valid_w),
        .bank3_mem_ofmap_o       (pea_bank3_ofmap_w),
        .bank3_mem_ofmap_valid_o (pea_bank3_ofmap_valid_w),
        .bank4_mem_ofmap_o       (pea_bank4_ofmap_w),
        .bank4_mem_ofmap_valid_o (pea_bank4_ofmap_valid_w),
        .shift_i                 (right_shift_w)
    );

    post_process_unit #(
        .DWIDTH(DWIDTH)
    ) u_post_process_unit (
        .layer_type_i           (layer_type_w),
        .in_channels_i          (in_channels_w),
        .out_channels_i         (out_channels_w),
        .activation_i           (activation_w),
        .bank0_mem_ofmap_i      (pea_bank0_ofmap_w),
        .bank0_mem_ofmap_valid_i(pea_bank0_ofmap_valid_w),
        .bank1_mem_ofmap_i      (pea_bank1_ofmap_w),
        .bank1_mem_ofmap_valid_i(pea_bank1_ofmap_valid_w),
        .bank2_mem_ofmap_i      (pea_bank2_ofmap_w),
        .bank2_mem_ofmap_valid_i(pea_bank2_ofmap_valid_w),
        .bank3_mem_ofmap_i      (pea_bank3_ofmap_w),
        .bank3_mem_ofmap_valid_i(pea_bank3_ofmap_valid_w),
        .bank4_mem_ofmap_i      (pea_bank4_ofmap_w),
        .bank4_mem_ofmap_valid_i(pea_bank4_ofmap_valid_w),
        .bank0_mem_ofmap_o      (post_proc_bank0_w),
        .bank0_mem_ofmap_valid_o(post_proc_bank0_valid_w),
        .bank1_mem_ofmap_o      (post_proc_bank1_w),
        .bank1_mem_ofmap_valid_o(post_proc_bank1_valid_w),
        .bank2_mem_ofmap_o      (post_proc_bank2_w),
        .bank2_mem_ofmap_valid_o(post_proc_bank2_valid_w),
        .bank3_mem_ofmap_o      (post_proc_bank3_w),
        .bank3_mem_ofmap_valid_o(post_proc_bank3_valid_w),
        .bank4_mem_ofmap_o      (post_proc_bank4_w),
        .bank4_mem_ofmap_valid_o(post_proc_bank4_valid_w)
    );

    pool_unit #(
        .DWIDTH(DWIDTH)
    ) u_pool_unit (
        .CLK               (CLK),
        .RST               (RST),
        .pool_step_i       (pool_step_w),
        .bank0_rd_data_i   (ifm_mem_bank0_w),
        .bank1_rd_data_i   (ifm_mem_bank1_w),
        .bank2_rd_data_i   (ifm_mem_bank2_w),
        .bank3_rd_data_i   (ifm_mem_bank3_w),
        .bank4_rd_data_i   (ifm_mem_bank4_w),
        .bank0_pool_data_o (pool_bank0_w),
        .bank0_pool_valid_o(pool_bank0_valid_w),
        .bank1_pool_data_o (pool_bank1_w),
        .bank1_pool_valid_o(pool_bank1_valid_w),
        .bank2_pool_data_o (pool_bank2_w),
        .bank2_pool_valid_o(pool_bank2_valid_w),
        .bank3_pool_data_o (pool_bank3_w),
        .bank3_pool_valid_o(pool_bank3_valid_w),
        .bank4_pool_data_o (pool_bank4_w),
        .bank4_pool_valid_o(pool_bank4_valid_w)
    );

endmodule
