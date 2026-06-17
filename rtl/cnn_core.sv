`timescale 1 ns / 1 ps

module cnn_core #(
    parameter AXI_ADDR_WIDTH  = 19,
    parameter AXI_DATA_DWIDTH = 16,
    parameter AWIDTH          = 16,
    parameter DWIDTH          = 16,
    parameter NBANKS          = 5,
    parameter TOTAL_DWIDTH    = NBANKS * DWIDTH
)(
    input  wire                         CLK,
    input  wire                         RST,

    input  wire [AXI_ADDR_WIDTH-1:0]    axi_waddr_i,
    input  wire [AXI_DATA_DWIDTH-1:0]   axi_wdata_i,
    input  wire                         axi_wvalid_i,

    input  wire [AXI_ADDR_WIDTH-1:0]    axi_raddr_i,
    input  wire                         axi_arvalid_i,
    output wire [AXI_DATA_DWIDTH-1:0]   axi_rdata_o,

    output wire                         predict_valid_o,
    output wire [3:0]                   predict_value_o,
    output wire [2:0]                   state_o,
    output wire                         done_o
);

    // LeNet-5 memory sizing:
    //   FM ping/pong: max Conv2 OFM depth per bank = 20 channels * 16 addr = 320 -> 9 bits
    //   Weight: 40 + 800 + 10240 + 2688 + 210 = 13978 packed words -> 14 bits
    //   Bias: 8 + 20 + 128 + 84 + 10 = 250 words -> 8 bits
    //
    // Controller uses the largest internal address width so Conv/Pool/FC address
    // math stays common, then each memory receives a truncated address bus.
    localparam CTRL_AWIDTH   = 14;
    localparam FM_AWIDTH     = 10;
    localparam WEIGHT_AWIDTH = 14;
    localparam BIAS_AWIDTH   = 8;

    wire load_done_w;
    wire start_w;
    wire done_clear_w;
    wire [2:0] state_w;
    wire done_w;
    wire [2:0] layer_op_w;

    wire ping_awvalid_w;
    wire [CTRL_AWIDTH-1:0] ping_awaddr_w;
    wire [TOTAL_DWIDTH-1:0] ping_awdata_w;
    wire ping_arvalid_w;
    wire [CTRL_AWIDTH-1:0] ping_araddr_w;
    wire [TOTAL_DWIDTH-1:0] ping_ardata_w;

    wire pong_awvalid_w;
    wire [CTRL_AWIDTH-1:0] pong_awaddr_w;
    wire [TOTAL_DWIDTH-1:0] pong_awdata_w;
    wire pong_arvalid_w;
    wire [CTRL_AWIDTH-1:0] pong_araddr_w;
    wire [TOTAL_DWIDTH-1:0] pong_ardata_w;

    wire weight_awvalid_w;
    wire [CTRL_AWIDTH-1:0] weight_awaddr_w;
    wire [TOTAL_DWIDTH-1:0] weight_awdata_w;

    wire bias_awvalid_w;
    wire [CTRL_AWIDTH-1:0] bias_awaddr_w;
    wire [DWIDTH-1:0] bias_awdata_w;

    wire ping_rd_en_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] ping_raddr_w;
    wire [NBANKS-1:0] ping_wr_en_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] ping_waddr_w;

    wire pong_rd_en_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] pong_raddr_w;
    wire [NBANKS-1:0] pong_wr_en_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] pong_waddr_w;

    wire weight_rd_en_w;
    wire [CTRL_AWIDTH-1:0] weight_addr_w;

    wire bias_rd_en_w;
    wire [CTRL_AWIDTH-1:0] bias_addr_w;

    wire pea_weight_load_w;
    wire [2:0] pea_row_weight_select_w;
    wire pea_execute_w;
    wire adder_valid_w;
    wire adder_first_channel_w;
    wire relu_last_channel_w;

    wire fc_data_valid_w;
    wire fc_last_chunk_w;
    wire fc_bias_valid_w;
    wire fc_relu_en_w;

    wire argmax_clear_w;
    wire argmax_data_valid_w;
    wire argmax_last_w;
    wire [3:0] argmax_bank_valid_w;
    wire [(4*DWIDTH)-1:0] argmax_data_w;
    wire [3:0] argmax_index_w;
    wire signed [DWIDTH-1:0] argmax_value_w;
    wire argmax_valid_w;

    reg predict_valid_r;
    reg [3:0] predict_value_r;

    wire [TOTAL_DWIDTH-1:0] ping_ifmap_w;
    wire [NBANKS-1:0] ping_ifmap_valid_w;
    wire [TOTAL_DWIDTH-1:0] pong_ifmap_w;
    wire [NBANKS-1:0] pong_ifmap_valid_w;

    wire [TOTAL_DWIDTH-1:0] weight_data_w;
    wire [NBANKS-1:0] weight_valid_w;

    wire [DWIDTH-1:0] bias_data_w;
    wire bias_valid_w;

    wire signed [(25*DWIDTH)-1:0] product_w;
    wire product_valid_w;
    wire adder_tree_valid_w;
    wire adder_first_channel_w_d;
    wire relu_last_channel_w_d;
    wire signed [DWIDTH-1:0] psum_w;
    wire psum_valid_w;

    wire signed [DWIDTH-1:0] relu_data_w;
    wire relu_valid_w;
    wire relu_applied_w;

    wire signed [TOTAL_DWIDTH-1:0] pool_data_w;
    wire [NBANKS-1:0] pool_valid_w;
    wire [NBANKS-1:0] pool_wr_en_pre_w;

    wire signed [DWIDTH-1:0] fc_data_w;
    wire fc_valid_w;

    wire [TOTAL_DWIDTH-1:0] fc_ifmap_data_w;
    wire [NBANKS-1:0]       fc_ifmap_valid_w;
    wire [TOTAL_DWIDTH-1:0] fc_weight_data_w;
    wire [NBANKS-1:0]       fc_weight_valid_w;
    wire [TOTAL_DWIDTH-1:0] fc_write_data_w;
    wire [NBANKS-1:0]       fc_write_valid_w;

    wire fc_bias_fire_w;

    wire [TOTAL_DWIDTH-1:0] active_ifmap_w;
    wire [NBANKS-1:0] active_ifmap_valid_w;
    wire [TOTAL_DWIDTH-1:0] pea_ifmap_w;
    wire [NBANKS-1:0] pea_ifmap_valid_w;
    wire [(NBANKS*3)-1:0] ifmap_bank_select_w;
    reg  [(NBANKS*3)-1:0] ifmap_bank_select_d1_r;

    wire [TOTAL_DWIDTH-1:0] prev_psum_bus_w;
    wire [NBANKS-1:0] prev_psum_valid_bus_w;
    wire signed [DWIDTH-1:0] prev_psum_w;
    wire prev_psum_valid_w;

    wire [TOTAL_DWIDTH-1:0] mem_write_data_w;
    wire [NBANKS-1:0] mem_write_valid_w;

    wire [FM_AWIDTH-1:0] ping_awaddr_fm_w;
    wire [FM_AWIDTH-1:0] ping_araddr_fm_w;
    wire [(NBANKS*FM_AWIDTH)-1:0] ping_raddr_fm_w;
    wire [(NBANKS*FM_AWIDTH)-1:0] ping_mem_waddr_fm_w;

    wire [FM_AWIDTH-1:0] pong_awaddr_fm_w;
    wire [FM_AWIDTH-1:0] pong_araddr_fm_w;
    wire [(NBANKS*FM_AWIDTH)-1:0] pong_raddr_fm_w;
    wire [(NBANKS*FM_AWIDTH)-1:0] pong_mem_waddr_fm_w;

    // Controller write intent is early for the conv pipeline.
    // Delay only the write controls that go into Ping/Pong FM memory;
    // keep the original controller write intent for prev-psum selection.
    reg  [NBANKS-1:0]  ping_wr_en_d1_r;
    reg  [NBANKS-1:0]  ping_wr_en_d2_r;
    reg  [NBANKS-1:0]  ping_wr_en_d3_r;
    reg  [(NBANKS*CTRL_AWIDTH)-1:0] ping_waddr_d1_r;
    reg  [(NBANKS*CTRL_AWIDTH)-1:0] ping_waddr_d2_r;
    reg  [(NBANKS*CTRL_AWIDTH)-1:0] ping_waddr_d3_r;
    reg  [NBANKS-1:0]  pong_wr_en_d1_r;
    reg  [NBANKS-1:0]  pong_wr_en_d2_r;
    reg  [NBANKS-1:0]  pong_wr_en_d3_r;
    reg  [(NBANKS*CTRL_AWIDTH)-1:0] pong_waddr_d1_r;
    reg  [(NBANKS*CTRL_AWIDTH)-1:0] pong_waddr_d2_r;
    reg  [(NBANKS*CTRL_AWIDTH)-1:0] pong_waddr_d3_r;

    wire [NBANKS-1:0]  ping_mem_wr_en_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] ping_mem_waddr_w;
    wire [NBANKS-1:0]  pong_mem_wr_en_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] pong_mem_waddr_w;

    wire               conv_psum_write_fire_w;
    wire               conv_relu_write_fire_w;
    wire [NBANKS-1:0]  conv_ping_mem_wr_en_w;
    wire [NBANKS-1:0]  conv_pong_mem_wr_en_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] conv_ping_mem_waddr_w;
    wire [(NBANKS*CTRL_AWIDTH)-1:0] conv_pong_mem_waddr_w;
    wire [TOTAL_DWIDTH-1:0] conv_write_data_w;
    wire [NBANKS-1:0]       conv_write_valid_w;

    reg relu_last_channel_d1_r;
    reg relu_last_channel_d2_r;
    reg relu_last_channel_d3_r;

    localparam [2:0] OP_CONV = 3'd0;
    localparam [2:0] OP_POOL = 3'd1;
    localparam [2:0] OP_FC   = 3'd2;
    localparam [2:0] OP_RELU = 3'd3;

    function [DWIDTH-1:0] mux_bank_data;
        input [TOTAL_DWIDTH-1:0] data_i;
        input [NBANKS-1:0]       sel_i;
        integer k;
        begin
            mux_bank_data = {DWIDTH{1'b0}};
            for (k = 0; k < NBANKS; k = k + 1) begin
                if (sel_i[k]) begin
                    mux_bank_data = data_i[(k*DWIDTH) +: DWIDTH];
                end
            end
        end
    endfunction

    function mux_bank_valid;
        input [NBANKS-1:0] valid_i;
        input [NBANKS-1:0] sel_i;
        integer k;
        begin
            mux_bank_valid = 1'b0;
            for (k = 0; k < NBANKS; k = k + 1) begin
                if (sel_i[k]) begin
                    mux_bank_valid = valid_i[k];
                end
            end
        end
    endfunction

    function [DWIDTH-1:0] select_bank_data;
        input [TOTAL_DWIDTH-1:0] data_i;
        input [2:0]              bank_i;
        begin
            case (bank_i)
                3'd0: select_bank_data = data_i[(0*DWIDTH) +: DWIDTH];
                3'd1: select_bank_data = data_i[(1*DWIDTH) +: DWIDTH];
                3'd2: select_bank_data = data_i[(2*DWIDTH) +: DWIDTH];
                3'd3: select_bank_data = data_i[(3*DWIDTH) +: DWIDTH];
                3'd4: select_bank_data = data_i[(4*DWIDTH) +: DWIDTH];
                default: select_bank_data = {DWIDTH{1'b0}};
            endcase
        end
    endfunction

    function select_bank_valid;
        input [NBANKS-1:0] valid_i;
        input [2:0]        bank_i;
        begin
            case (bank_i)
                3'd0: select_bank_valid = valid_i[0];
                3'd1: select_bank_valid = valid_i[1];
                3'd2: select_bank_valid = valid_i[2];
                3'd3: select_bank_valid = valid_i[3];
                3'd4: select_bank_valid = valid_i[4];
                default: select_bank_valid = 1'b0;
            endcase
        end
    endfunction

    assign ping_awaddr_fm_w = ping_awaddr_w[FM_AWIDTH-1:0];
    assign ping_araddr_fm_w = ping_araddr_w[FM_AWIDTH-1:0];
    assign pong_awaddr_fm_w = pong_awaddr_w[FM_AWIDTH-1:0];
    assign pong_araddr_fm_w = pong_araddr_w[FM_AWIDTH-1:0];

    genvar fm_addr_bank_g;

    generate
        for (fm_addr_bank_g = 0; fm_addr_bank_g < NBANKS; fm_addr_bank_g = fm_addr_bank_g + 1) begin : TRUNC_FM_ADDR
            assign ping_raddr_fm_w[(fm_addr_bank_g*FM_AWIDTH) +: FM_AWIDTH] =
                ping_raddr_w[(fm_addr_bank_g*CTRL_AWIDTH) +: FM_AWIDTH];

            assign ping_mem_waddr_fm_w[(fm_addr_bank_g*FM_AWIDTH) +: FM_AWIDTH] =
                ping_mem_waddr_w[(fm_addr_bank_g*CTRL_AWIDTH) +: FM_AWIDTH];

            assign pong_raddr_fm_w[(fm_addr_bank_g*FM_AWIDTH) +: FM_AWIDTH] =
                pong_raddr_w[(fm_addr_bank_g*CTRL_AWIDTH) +: FM_AWIDTH];

            assign pong_mem_waddr_fm_w[(fm_addr_bank_g*FM_AWIDTH) +: FM_AWIDTH] =
                pong_mem_waddr_w[(fm_addr_bank_g*CTRL_AWIDTH) +: FM_AWIDTH];
        end
    endgenerate

    assign active_ifmap_w =
        (|ping_wr_en_w) ? pong_ifmap_w :
        (|pong_wr_en_w) ? ping_ifmap_w :
        (|ping_ifmap_valid_w) ? ping_ifmap_w : pong_ifmap_w;

    assign active_ifmap_valid_w =
        (|ping_wr_en_w) ? pong_ifmap_valid_w :
        (|pong_wr_en_w) ? ping_ifmap_valid_w :
        (|ping_ifmap_valid_w) ? ping_ifmap_valid_w : pong_ifmap_valid_w;

    genvar bank_g;

    generate
        for (bank_g = 0; bank_g < NBANKS; bank_g = bank_g + 1) begin : REORDER_IFMAP_FOR_PEA
            assign pea_ifmap_w[(bank_g*DWIDTH) +: DWIDTH] =
                select_bank_data(active_ifmap_w, ifmap_bank_select_d1_r[(bank_g*3) +: 3]);

            assign pea_ifmap_valid_w[bank_g] =
                select_bank_valid(active_ifmap_valid_w, ifmap_bank_select_d1_r[(bank_g*3) +: 3]);
        end
    endgenerate

    assign prev_psum_bus_w =
        (|ping_wr_en_w) ? ping_ifmap_w :
        (|pong_wr_en_w) ? pong_ifmap_w :
                          {TOTAL_DWIDTH{1'b0}};

    assign prev_psum_valid_bus_w =
        (|ping_wr_en_w) ? ping_ifmap_valid_w :
        (|pong_wr_en_w) ? pong_ifmap_valid_w :
                          {NBANKS{1'b0}};

    assign prev_psum_w =
        (|ping_wr_en_w) ? mux_bank_data(prev_psum_bus_w, ping_wr_en_w) :
        (|pong_wr_en_w) ? mux_bank_data(prev_psum_bus_w, pong_wr_en_w) :
                          {DWIDTH{1'b0}};

    assign prev_psum_valid_w =
        (|ping_wr_en_w) ? mux_bank_valid(prev_psum_valid_bus_w, ping_wr_en_w) :
        (|pong_wr_en_w) ? mux_bank_valid(prev_psum_valid_bus_w, pong_wr_en_w) :
                          1'b0;

    // Convolution writes are split by channel phase:
    //   - intermediate input channels write partial sums directly from AdderTree
    //   - the final input channel writes the ReLU output feature-map value
    // Pool/FC/ReLU standalone layers keep their own data paths.
    assign conv_psum_write_fire_w = psum_valid_w && !relu_last_channel_w_d;
    assign conv_relu_write_fire_w = relu_valid_w && relu_applied_w;

    assign conv_write_data_w = conv_relu_write_fire_w ? {NBANKS{relu_data_w}} :
                                                        {NBANKS{psum_w}};

    assign conv_write_valid_w = conv_relu_write_fire_w ? {NBANKS{relu_valid_w}} :
                                                         {NBANKS{psum_valid_w}};

    // FC is four-bank wide. Bank 4 is masked to zero/invalid because Pool2 and
    // FC write-back intentionally use only banks 0..3.
    assign fc_ifmap_data_w  = { {DWIDTH{1'b0}}, active_ifmap_w[(4*DWIDTH)-1:0] };
    assign fc_ifmap_valid_w = { 1'b0, active_ifmap_valid_w[3:0] };
    assign fc_weight_data_w  = { {DWIDTH{1'b0}}, weight_data_w[(4*DWIDTH)-1:0] };
    assign fc_weight_valid_w = { 1'b0, weight_valid_w[3:0] };
    assign fc_write_data_w   = { {DWIDTH{1'b0}}, {4{fc_data_w}} };
    assign fc_write_valid_w  = { 1'b0, {4{fc_valid_w}} };

    assign argmax_data_w = active_ifmap_w[(4*DWIDTH)-1:0];

    assign mem_write_data_w = (layer_op_w == OP_CONV) ? conv_write_data_w :
                              (layer_op_w == OP_POOL) ? pool_data_w :
                              (layer_op_w == OP_FC)   ? fc_write_data_w :
                                                         {NBANKS{relu_data_w}};

    assign mem_write_valid_w = (layer_op_w == OP_CONV) ? conv_write_valid_w :
                              (layer_op_w == OP_POOL) ? pool_valid_w :
                              (layer_op_w == OP_FC)   ? fc_write_valid_w :
                                                         {NBANKS{relu_valid_w}};

    // Convolution write-back latency alignment.
    // Controller write intent appears one cycle after PEA execute.
    // PEA registers product_valid, then Adder_Tree registers psum_valid:
    //   controller wr intent -> d1 aligns with psum_valid_w.
    // ReLU registers the final-channel OFM one more cycle later:
    //   controller wr intent -> d2 aligns with relu_valid_w/relu_applied_w.
    // This is important for Conv2+ where ic>0 continuously reads old psum from
    // destination memory while writing the updated psum back to the same memory.
    assign conv_ping_mem_wr_en_w = conv_relu_write_fire_w ? ping_wr_en_d3_r :
                                   conv_psum_write_fire_w ? ping_wr_en_d2_r : {NBANKS{1'b0}};
    assign conv_pong_mem_wr_en_w = conv_relu_write_fire_w ? pong_wr_en_d3_r :
                                   conv_psum_write_fire_w ? pong_wr_en_d2_r : {NBANKS{1'b0}};
    assign conv_ping_mem_waddr_w = conv_relu_write_fire_w ? ping_waddr_d3_r : ping_waddr_d2_r;
    assign conv_pong_mem_waddr_w = conv_relu_write_fire_w ? pong_waddr_d3_r : pong_waddr_d2_r;
    // For Pool/FC/ReLU standalone layers, keep the original one-bank controls.
    assign ping_mem_wr_en_w = (layer_op_w == OP_CONV) ? conv_ping_mem_wr_en_w : ping_wr_en_w;
    assign ping_mem_waddr_w = (layer_op_w == OP_CONV) ? conv_ping_mem_waddr_w : ping_waddr_w;
    assign pong_mem_wr_en_w = (layer_op_w == OP_CONV) ? conv_pong_mem_wr_en_w : pong_wr_en_w;
    assign pong_mem_waddr_w = (layer_op_w == OP_CONV) ? conv_pong_mem_waddr_w : pong_waddr_w;

    assign adder_tree_valid_w      = product_valid_w;
    assign adder_first_channel_w_d = adder_first_channel_w;
    assign relu_last_channel_w_d   = relu_last_channel_d3_r;

    // FC bias is only usable when both Controller intent and Bias_Memory valid are high.
    // IFM/weight valid vectors are passed into Fully_Connected and gated there so
    // chunk0 can still consume bias + IFM + weight in the same cycle.
    assign fc_bias_fire_w = fc_bias_valid_w && bias_valid_w;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            relu_last_channel_d1_r <= 1'b0;
            relu_last_channel_d2_r <= 1'b0;
            relu_last_channel_d3_r <= 1'b0;
            ifmap_bank_select_d1_r <= {(NBANKS*3){1'b0}};

            ping_wr_en_d1_r        <= {NBANKS{1'b0}};
            ping_wr_en_d2_r        <= {NBANKS{1'b0}};
            ping_wr_en_d3_r        <= {NBANKS{1'b0}};
            ping_waddr_d1_r        <= {(NBANKS*CTRL_AWIDTH){1'b0}};
            ping_waddr_d2_r        <= {(NBANKS*CTRL_AWIDTH){1'b0}};
            ping_waddr_d3_r        <= {(NBANKS*CTRL_AWIDTH){1'b0}};
            pong_wr_en_d1_r        <= {NBANKS{1'b0}};
            pong_wr_en_d2_r        <= {NBANKS{1'b0}};
            pong_wr_en_d3_r        <= {NBANKS{1'b0}};
            pong_waddr_d1_r        <= {(NBANKS*CTRL_AWIDTH){1'b0}};
            pong_waddr_d2_r        <= {(NBANKS*CTRL_AWIDTH){1'b0}};
            pong_waddr_d3_r        <= {(NBANKS*CTRL_AWIDTH){1'b0}};
        end
        else begin
            relu_last_channel_d1_r <= relu_last_channel_w;
            relu_last_channel_d2_r <= relu_last_channel_d1_r;
            relu_last_channel_d3_r <= relu_last_channel_d2_r;
            ifmap_bank_select_d1_r <= ifmap_bank_select_w;

            ping_wr_en_d1_r        <= ping_wr_en_w;
            ping_wr_en_d2_r        <= ping_wr_en_d1_r;
            ping_wr_en_d3_r        <= ping_wr_en_d2_r;
            ping_waddr_d1_r        <= ping_waddr_w;
            ping_waddr_d2_r        <= ping_waddr_d1_r;
            ping_waddr_d3_r        <= ping_waddr_d2_r;
            pong_wr_en_d1_r        <= pong_wr_en_w;
            pong_wr_en_d2_r        <= pong_wr_en_d1_r;
            pong_wr_en_d3_r        <= pong_wr_en_d2_r;
            pong_waddr_d1_r        <= pong_waddr_w;
            pong_waddr_d2_r        <= pong_waddr_d1_r;
            pong_waddr_d3_r        <= pong_waddr_d2_r;
        end
    end

    //-------------------------------------//
    // Prediction result register
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            predict_valid_r <= 1'b0;
            predict_value_r <= 4'd0;
        end
        else begin
            if (done_clear_w || start_w) begin
                predict_valid_r <= 1'b0;
                predict_value_r <= 4'd0;
            end
            else if (argmax_valid_w) begin
                predict_valid_r <= 1'b1;
                predict_value_r <= argmax_index_w;
            end
        end
    end


    Global_Arbiter #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_DWIDTH(AXI_DATA_DWIDTH),
        .MEM_ADDR_WIDTH(CTRL_AWIDTH),
        .MEM_DATA_DWIDTH(TOTAL_DWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) u_global_arbiter (
        .CLK(CLK),
        .RST(RST),
        .axi_waddr_i(axi_waddr_i),
        .axi_wdata_i(axi_wdata_i),
        .axi_wvalid_i(axi_wvalid_i),
        .axi_raddr_i(axi_raddr_i),
        .axi_arvalid_i(axi_arvalid_i),
        .axi_rdata_o(axi_rdata_o),
        .ctrl_state_i(state_w),
        .ctrl_done_i(done_w),
        .predict_valid_i(predict_valid_r),
        .predict_value_i(predict_value_r),
        .load_done_o(load_done_w),
        .start_o(start_w),
        .done_clear_o(done_clear_w),
        .ping_fm_wvalid_o(ping_awvalid_w),
        .ping_fm_waddr_o(ping_awaddr_w),
        .ping_fm_wdata_o(ping_awdata_w),
        .ping_fm_arvalid_o(ping_arvalid_w),
        .ping_fm_raddr_o(ping_araddr_w),
        .ping_fm_rdata_i(ping_ardata_w),
        .pong_fm_wvalid_o(pong_awvalid_w),
        .pong_fm_waddr_o(pong_awaddr_w),
        .pong_fm_wdata_o(pong_awdata_w),
        .pong_fm_arvalid_o(pong_arvalid_w),
        .pong_fm_raddr_o(pong_araddr_w),
        .pong_fm_rdata_i(pong_ardata_w),
        .weight_wvalid_o(weight_awvalid_w),
        .weight_waddr_o(weight_awaddr_w),
        .weight_wdata_o(weight_awdata_w),
        .bias_wvalid_o(bias_awvalid_w),
        .bias_waddr_o(bias_awaddr_w),
        .bias_wdata_o(bias_awdata_w)
    );

    Controller #(
        .AWIDTH(CTRL_AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) u_controller (
        .CLK(CLK),
        .RST(RST),
        .load_done_i(load_done_w),
        .start_i(start_w),
        .done_clear_i(done_clear_w),
        .state_o(state_w),
        .done_o(done_w),
        .layer_op_o(layer_op_w),
        .ping_rd_en_o(ping_rd_en_w),
        .ping_raddr_o(ping_raddr_w),
        .ping_wr_en_o(ping_wr_en_w),
        .ping_waddr_o(ping_waddr_w),
        .pong_rd_en_o(pong_rd_en_w),
        .pong_raddr_o(pong_raddr_w),
        .pong_wr_en_o(pong_wr_en_w),
        .pong_wraddr_o(pong_waddr_w),
        .weight_rd_en_o(weight_rd_en_w),
        .weight_addr_o(weight_addr_w),
        .bias_rd_en_o(bias_rd_en_w),
        .bias_addr_o(bias_addr_w),
        .pea_weight_load_o(pea_weight_load_w),
        .pea_row_weight_select_o(pea_row_weight_select_w),
        .pea_execute_o(pea_execute_w),
        .adder_valid_o(adder_valid_w),
        .adder_first_channel_o(adder_first_channel_w),
        .relu_last_channel_o(relu_last_channel_w),
        .fc_data_valid_o(fc_data_valid_w),
        .fc_last_chunk_o(fc_last_chunk_w),
        .fc_bias_valid_o(fc_bias_valid_w),
        .fc_relu_en_o(fc_relu_en_w),
        .argmax_clear_o(argmax_clear_w),
        .argmax_data_valid_o(argmax_data_valid_w),
        .argmax_last_o(argmax_last_w),
        .argmax_bank_valid_o(argmax_bank_valid_w),
        .ifmap_bank_select_o(ifmap_bank_select_w),
        .pool_wr_en_o(pool_wr_en_pre_w)
    );

    Ping_Pong_FM_Memory #(
        .AWIDTH(FM_AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS),
        .TOTAL_DWIDTH(TOTAL_DWIDTH)
    ) u_ping_fm_memory (
        .CLK(CLK),
        .arbiter_FM_wvalid_i(ping_awvalid_w),
        .arbiter_FM_waddr_i(ping_awaddr_fm_w),
        .arbiter_FM_wdata_i(ping_awdata_w),
        .arbiter_FM_arvalid_i(ping_arvalid_w),
        .arbiter_FM_raddr_i(ping_araddr_fm_w),
        .arbiter_FM_rdata_o(ping_ardata_w),
        .ctrl_bank_rd_en_i(ping_rd_en_w),
        .ctrl_bank_raddr_i(ping_raddr_fm_w),
        .ctrl_bank_wr_en_i(ping_mem_wr_en_w),
        .ctrl_bank_waddr_i(ping_mem_waddr_fm_w),
        .pea_mem_ofmap_i(mem_write_data_w),
        .pea_mem_ofmap_valid_i(mem_write_valid_w),
        .mem_pea_ifmap_o(ping_ifmap_w),
        .mem_pea_ifmap_valid_o(ping_ifmap_valid_w)
    );

    Ping_Pong_FM_Memory #(
        .AWIDTH(FM_AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS),
        .TOTAL_DWIDTH(TOTAL_DWIDTH)
    ) u_pong_fm_memory (
        .CLK(CLK),
        .arbiter_FM_wvalid_i(pong_awvalid_w),
        .arbiter_FM_waddr_i(pong_awaddr_fm_w),
        .arbiter_FM_wdata_i(pong_awdata_w),
        .arbiter_FM_arvalid_i(pong_arvalid_w),
        .arbiter_FM_raddr_i(pong_araddr_fm_w),
        .arbiter_FM_rdata_o(pong_ardata_w),
        .ctrl_bank_rd_en_i(pong_rd_en_w),
        .ctrl_bank_raddr_i(pong_raddr_fm_w),
        .ctrl_bank_wr_en_i(pong_mem_wr_en_w),
        .ctrl_bank_waddr_i(pong_mem_waddr_fm_w),
        .pea_mem_ofmap_i(mem_write_data_w),
        .pea_mem_ofmap_valid_i(mem_write_valid_w),
        .mem_pea_ifmap_o(pong_ifmap_w),
        .mem_pea_ifmap_valid_o(pong_ifmap_valid_w)
    );

    Weight_Memory #(
        .AWIDTH(WEIGHT_AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS),
        .TOTAL_DWIDTH(TOTAL_DWIDTH)
    ) u_weight_memory (
        .CLK(CLK),
        .arbiter_weight_wvalid_i(weight_awvalid_w),
        .arbiter_weight_waddr_i(weight_awaddr_w),
        .arbiter_weight_wdata_i(weight_awdata_w),
        .arbiter_weight_arvalid_i(1'b0),
        .arbiter_weight_raddr_i({WEIGHT_AWIDTH{1'b0}}),
        .arbiter_weight_rdata_o(),
        .ctrl_weight_rd_en_i(weight_rd_en_w),
        .ctrl_weight_addr_i(weight_addr_w),
        .weight_data_o(weight_data_w),
        .weight_valid_o(weight_valid_w)
    );

    Bias_Memory #(
        .AWIDTH(BIAS_AWIDTH),
        .DWIDTH(DWIDTH)
    ) u_bias_memory (
        .CLK(CLK),
        .arbiter_bias_wvalid_i(bias_awvalid_w),
        .arbiter_bias_waddr_i(bias_awaddr_w[BIAS_AWIDTH-1:0]),
        .arbiter_bias_wdata_i(bias_awdata_w),
        .arbiter_bias_arvalid_i(1'b0),
        .arbiter_bias_raddr_i({BIAS_AWIDTH{1'b0}}),
        .arbiter_bias_rdata_o(),
        .ctrl_bias_rd_en_i(bias_rd_en_w),
        .ctrl_bias_addr_i(bias_addr_w[BIAS_AWIDTH-1:0]),
        .bias_data_o(bias_data_w),
        .bias_valid_o(bias_valid_w)
    );

    PEA_5x5 #(
        .DATA_DWIDTH(DWIDTH)
    ) u_pea_5x5 (
        .CLK(CLK),
        .RST(RST),
        .weight_load_i(pea_weight_load_w),
        .row_weight_select_i(pea_row_weight_select_w),
        .row_weight_i(weight_data_w),
        .FM_Bank1_ifmap_i(pea_ifmap_w),
        .FM_Bank1_ifmap_valid_i(pea_ifmap_valid_w),
        .execute_i(pea_execute_w),
        .product_o(product_w),
        .product_valid_o(product_valid_w)
    );

    Adder_Tree_5x5 #(
        .DATA_DWIDTH(DWIDTH)
    ) u_adder_tree_5x5 (
        .CLK(CLK),
        .RST(RST),
        .product_valid_i(adder_tree_valid_w),
        .product_i(product_w),
        .first_channel_i(adder_first_channel_w_d),
        .prev_psum_i(prev_psum_w),
        .prev_psum_valid_i(prev_psum_valid_w),
        .bias_i(bias_data_w),
        .bias_valid_i(bias_valid_w),
        .psum_o(psum_w),
        .psum_valid_o(psum_valid_w)
    );

    ReLU #(
        .DATA_DWIDTH(DWIDTH)
    ) u_relu (
        .CLK(CLK),
        .RST(RST),
        .psum_i(psum_w),
        .psum_valid_i(psum_valid_w),
        .last_channel_i(relu_last_channel_w_d),
        .fm_data_o(relu_data_w),
        .fm_data_valid_o(relu_valid_w),
        .relu_applied_o(relu_applied_w)
    );

    Maxpooling #(
        .DATA_DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) u_maxpooling (
        .CLK(CLK),
        .RST(RST),
        .fm_data_i(active_ifmap_w),
        .fm_data_valid_i((layer_op_w == OP_POOL) ? active_ifmap_valid_w : {NBANKS{1'b0}}),
        .pool_wr_en_i((layer_op_w == OP_POOL) ? pool_wr_en_pre_w : {NBANKS{1'b0}}),
        .pool_data_o(pool_data_w),
        .pool_data_valid_o(pool_valid_w)
    );

    Fully_Connected #(
        .DATA_DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) u_fully_connected (
        .CLK(CLK),
        .RST(RST),
        .bias_i(bias_data_w),
        .bias_valid_i(fc_bias_fire_w),
        .ifm_data_i(fc_ifmap_data_w),
        .ifm_valid_i(fc_ifmap_valid_w),
        .weight_data_i(fc_weight_data_w),
        .weight_valid_i(fc_weight_valid_w),
        .data_valid_i(fc_data_valid_w),
        .last_chunk_i(fc_last_chunk_w),
        .relu_en_i(fc_relu_en_w),
        .fc_data_o(fc_data_w),
        .fc_data_valid_o(fc_valid_w)
    );

    ArgMax_4Bank #(
        .DATA_DWIDTH(DWIDTH),
        .INDEX_DWIDTH(4)
    ) u_argmax_4bank (
        .CLK(CLK),
        .RST(RST),
        .clear_i(argmax_clear_w),
        .data_valid_i(argmax_data_valid_w ? argmax_bank_valid_w : 4'd0),
        .data_i(argmax_data_w),
        .last_i(argmax_last_w),
        .max_index_o(argmax_index_w),
        .max_value_o(argmax_value_w),
        .max_valid_o(argmax_valid_w)
    );

    assign predict_valid_o = predict_valid_r;
    assign predict_value_o = predict_value_r;
    assign state_o         = state_w;
    assign done_o          = done_w;

endmodule
