`timescale 1 ns / 1 ps

module Controller #(
parameter AWIDTH = 16,
parameter DWIDTH = 16,
parameter NBANKS = 5
)(
input wire CLK,
input wire RST,

input  wire                         load_done_i,
input  wire                         start_i,
input  wire                         done_clear_i,

output wire [2:0]                   state_o,
output wire                         done_o,
output wire [2:0]                   layer_op_o,

output reg                          ping_rd_en_o,
output reg  [(NBANKS*AWIDTH)-1:0]   ping_raddr_o,
output reg  [NBANKS-1:0]            ping_wr_en_o,
output reg  [(NBANKS*AWIDTH)-1:0]   ping_waddr_o,

output reg                          pong_rd_en_o,
output reg  [(NBANKS*AWIDTH)-1:0]   pong_raddr_o,
output reg  [NBANKS-1:0]            pong_wr_en_o,
output reg  [(NBANKS*AWIDTH)-1:0]   pong_wraddr_o,

output reg                          weight_rd_en_o,
output reg  [AWIDTH-1:0]            weight_addr_o,

output reg                          bias_rd_en_o,
output reg  [AWIDTH-1:0]            bias_addr_o,

output reg                          pea_weight_load_o,
output reg  [2:0]                   pea_row_weight_select_o,
output reg                          pea_execute_o,

output reg                          adder_valid_o,
output reg                          adder_first_channel_o,
output reg                          relu_last_channel_o,

output reg                          fc_data_valid_o,
output reg                          fc_last_chunk_o,
output reg                          fc_bias_valid_o,
output reg                          fc_relu_en_o,

output reg                          argmax_clear_o,
output reg                          argmax_data_valid_o,
output reg                          argmax_last_o,
output reg  [3:0]                   argmax_bank_valid_o,

output reg  [(NBANKS*3)-1:0]        ifmap_bank_select_o,
output reg  [NBANKS-1:0]            pool_wr_en_o
);

localparam [2:0] S_IDLE       = 3'd0;
localparam [2:0] S_WAIT_LOAD  = 3'd1;
localparam [2:0] S_LOAD_LAYER = 3'd2;
localparam [2:0] S_RUN_LAYER  = 3'd3;
localparam [2:0] S_DONE       = 3'd4;

localparam [2:0] OP_CONV      = 3'd0;
localparam [2:0] OP_POOL      = 3'd1;
localparam [2:0] OP_FC        = 3'd2;
localparam [2:0] OP_RELU      = 3'd3;
localparam [2:0] OP_ARGMAX    = 3'd4;

localparam [1:0] CONV_LOAD    = 2'd0;
localparam [1:0] CONV_FEED    = 2'd1;
localparam [1:0] CONV_FLUSH   = 2'd2;

localparam [3:0] NUM_LAYER    = 4'd8;

localparam [AWIDTH-1:0] CONV1_WEIGHT_BASE = 16'd0;
localparam [AWIDTH-1:0] CONV2_WEIGHT_BASE = 16'd40;
localparam [AWIDTH-1:0] FC1_WEIGHT_BASE   = 16'd840;
localparam [AWIDTH-1:0] FC2_WEIGHT_BASE   = 16'd11080;
localparam [AWIDTH-1:0] FC3_WEIGHT_BASE   = 16'd13768;

localparam [AWIDTH-1:0] CONV1_BIAS_BASE   = 16'd0;
localparam [AWIDTH-1:0] CONV2_BIAS_BASE   = 16'd8;
localparam [AWIDTH-1:0] FC1_BIAS_BASE     = 16'd28;
localparam [AWIDTH-1:0] FC2_BIAS_BASE     = 16'd156;
localparam [AWIDTH-1:0] FC3_BIAS_BASE     = 16'd240;

reg [2:0]  state_r;
reg [2:0]  next_state_r;
reg [3:0]  layer_idx_r;
reg        layer_done_r;

reg [2:0]  layer_op_r;
reg        src_ping_r;
reg        dst_ping_r;
reg [15:0] ifm_size_r;
reg [15:0] ofm_size_r;
reg [15:0] ifm_last_r;
reg [15:0] ofm_last_r;
reg [11:0] in_ch_r;
reg [11:0] out_ch_r;
reg [11:0] in_ch_last_r;
reg [11:0] out_ch_last_r;
reg [15:0] in_len_r;
reg [15:0] out_len_r;
reg [15:0] in_len_last_r;
reg [15:0] out_len_last_r;
reg [AWIDTH-1:0] ifm_bank_depth_r;
reg [AWIDTH-1:0] ofm_bank_depth_r;
reg [AWIDTH-1:0] weight_base_r;
reg [AWIDTH-1:0] bias_base_r;
reg [15:0] fc_chunk_count_r;
reg [15:0] fc_chunk_last_r;
reg [31:0] simple_total_r;
reg [31:0] simple_count_r;
reg [2:0]  simple_bank_r;
reg [AWIDTH-1:0] simple_addr_r;

reg        pool_pair_phase_r;
reg        pool_drain_r;
reg [2:0]  pool_dst_bank_r;
reg [AWIDTH-1:0] pool_dst_addr_r;
reg        pool_wr_fire_d1_r;
reg        pool_wr_fire_d2_r;
reg        pool_wr_fire_d3_r;
reg [NBANKS-1:0] pool_wr_bank_d1_r;
reg [NBANKS-1:0] pool_wr_bank_d2_r;
reg [NBANKS-1:0] pool_wr_bank_d3_r;
reg [2:0]  pool_wr_bank_base_d1_r;
reg [2:0]  pool_wr_bank_base_d2_r;
reg [2:0]  pool_wr_bank_base_d3_r;
reg [AWIDTH-1:0] pool_wr_addr_d1_r;
reg [AWIDTH-1:0] pool_wr_addr_d2_r;
reg [AWIDTH-1:0] pool_wr_addr_d3_r;
reg [(NBANKS*AWIDTH)-1:0] pool_wr_addr_bus_d1_r;
reg [(NBANKS*AWIDTH)-1:0] pool_wr_addr_bus_d2_r;
reg [(NBANKS*AWIDTH)-1:0] pool_wr_addr_bus_d3_r;
reg [AWIDTH-1:0] pool_wr_addr_b0_r;
reg [AWIDTH-1:0] pool_wr_addr_b1_r;
reg [AWIDTH-1:0] pool_wr_addr_b2_r;
reg [AWIDTH-1:0] pool_wr_addr_b3_r;
reg [AWIDTH-1:0] pool_wr_addr_b4_r;
reg [11:0] pool_ch_r;
reg [15:0] pool_row_r;
reg [15:0] pool_col_r;
reg [AWIDTH-1:0] pool_ch_base_r;
reg [AWIDTH-1:0] pool_row_base_r;
reg [15:0] pool_rd_col_r;
reg [15:0] pool_rd_row_r;
reg [15:0] pool_rd_pair_row_r;
reg [11:0] pool_rd_ch_r;
reg        pool_rd_ch_end_r;
reg [31:0] pool_rd_pix_r;
reg [15:0] pool_rd_local_col_r;
reg [2:0]  pool_src_bank0_r;
reg [AWIDTH-1:0] pool_src_ch_base_r;
reg [AWIDTH-1:0] pool_src_row_base_r;
reg [AWIDTH-1:0] pool_prev_read_addr_r;
reg [AWIDTH-1:0] pool_ifm_stride_r;
reg [AWIDTH-1:0] pool_rd_addr_b0_r;
reg [AWIDTH-1:0] pool_rd_addr_b1_r;
reg [AWIDTH-1:0] pool_rd_addr_b2_r;
reg [AWIDTH-1:0] pool_rd_addr_b3_r;
reg [AWIDTH-1:0] pool_rd_addr_b4_r;
reg        pool2_mode_r;

reg [1:0]  conv_phase_r;
reg [2:0]  conv_load_row_r;
reg [2:0]  conv_flush_cnt_r;
reg [11:0] conv_ic_r;
reg [11:0] conv_oc_r;
reg [15:0] conv_row_r;
reg [15:0] conv_col_r;
reg [15:0] conv_out_col_r;
reg [2:0]  conv_src_bank0_r;
reg [2:0]  conv_dst_bank_r;
reg [AWIDTH-1:0] conv_src_ch_base_r;
reg [AWIDTH-1:0] conv_dst_ch_base_r;
reg [AWIDTH-1:0] conv_dst_row_base_r;
reg [AWIDTH-1:0] conv_weight_addr_r;
reg [AWIDTH-1:0] conv_bias_addr_r;
reg [AWIDTH-1:0] conv_row0_base_r;
reg [AWIDTH-1:0] conv_row1_base_r;
reg [AWIDTH-1:0] conv_row2_base_r;
reg [AWIDTH-1:0] conv_row3_base_r;
reg [AWIDTH-1:0] conv_row4_base_r;
reg [2:0] weight_select_d_r;

reg        conv_s0_valid_r;
reg        conv_s0_first_r;
reg        conv_s0_last_r;
reg        conv_s0_prev_r;
reg        conv_s0_dst_ping_r;
reg [NBANKS-1:0] conv_s0_bank_r;
reg [AWIDTH-1:0] conv_s0_addr_r;

reg        conv_s1_valid_r;
reg        conv_s1_first_r;
reg        conv_s1_dst_ping_r;
reg [NBANKS-1:0] conv_s1_bank_r;
reg [AWIDTH-1:0] conv_s1_addr_r;

reg [15:0] fc_out_r;
reg [15:0] fc_chunk_r;
reg [AWIDTH-1:0] fc_weight_addr_r;
reg [AWIDTH-1:0] fc_ifm_addr_r;
reg [AWIDTH-1:0] fc_bias_addr_r;
reg [2:0] fc_flush_cnt_r;
reg       fc_flush_r;
reg       fc_s0_valid_r;
reg       fc_s0_last_r;
reg       fc_s0_bias_r;
reg       fc_s0_dst_ping_r;
reg [NBANKS-1:0] fc_s0_bank_r;
reg [AWIDTH-1:0] fc_s0_addr_r;
reg       fc_s1_valid_r;
reg       fc_s1_dst_ping_r;
reg [NBANKS-1:0] fc_s1_bank_r;
reg [AWIDTH-1:0] fc_s1_addr_r;
reg       fc_s2_valid_r;
reg       fc_s2_dst_ping_r;
reg [NBANKS-1:0] fc_s2_bank_r;
reg [AWIDTH-1:0] fc_s2_addr_r;

reg [1:0]  argmax_addr_r;
reg [1:0]  argmax_rd_count_r;
reg [1:0]  argmax_valid_count_r;
reg [3:0]  argmax_mask_d1_r;
reg        argmax_last_d1_r;
reg        argmax_drain_r;
reg        argmax_done_d1_r;

wire layer_last_w;
wire conv_col_ge4_w;
wire conv_ofm_issue_w;
wire conv_row_last_issue_w;
wire [15:0] conv_ofm_col_w;
wire [AWIDTH-1:0] conv_rd_addr0_w;
wire [AWIDTH-1:0] conv_rd_addr1_w;
wire [AWIDTH-1:0] conv_rd_addr2_w;
wire [AWIDTH-1:0] conv_rd_addr3_w;
wire [AWIDTH-1:0] conv_rd_addr4_w;
wire [AWIDTH-1:0] conv_ofm_addr_w;
wire [AWIDTH-1:0] conv_next_ic_base_w;
wire [(NBANKS*AWIDTH)-1:0] conv_read_bus_w;
wire [(NBANKS*3)-1:0] conv_bank_sel_w;
wire [AWIDTH-1:0] pool_next_src_ch_base_w;
wire [NBANKS-1:0] pool_rd_bank_en_raw_w;
wire [NBANKS-1:0] pool_rd_bank_en_w;
wire [(NBANKS*AWIDTH)-1:0] pool_rd_addr_bus_w;
wire [AWIDTH-1:0] pool_next_ch_base_w;
wire [31:0] pool_rd_ch_last_pix_w;
wire [31:0] pool_rd_ch_pre_last_pix_w;
wire [AWIDTH-1:0] fc_weight_addr_w;

assign layer_last_w = (layer_idx_r == (NUM_LAYER - 1'b1));
assign conv_col_ge4_w = (conv_col_r >= 16'd4);
// A 5x5 valid convolution over a row produces exactly ofm_size_r pixels.
// For Conv1: conv_col_r 4..27 maps to conv_out_col_r 0..23 (24 writes).
// Use an explicit OFM issue guard so the last column is included and no
// off-by-one appears from comparing against the last index only.
assign conv_ofm_col_w = conv_col_ge4_w ? (conv_col_r - 16'd4) : 16'd0;
assign conv_ofm_issue_w = conv_col_ge4_w && (conv_ofm_col_w < ofm_size_r);
assign conv_row_last_issue_w = conv_ofm_issue_w && (conv_ofm_col_w == ofm_last_r);

assign conv_rd_addr0_w = conv_row0_base_r + conv_col_r[AWIDTH-1:0];
assign conv_rd_addr1_w = conv_row1_base_r + conv_col_r[AWIDTH-1:0];
assign conv_rd_addr2_w = conv_row2_base_r + conv_col_r[AWIDTH-1:0];
assign conv_rd_addr3_w = conv_row3_base_r + conv_col_r[AWIDTH-1:0];
assign conv_rd_addr4_w = conv_row4_base_r + conv_col_r[AWIDTH-1:0];
assign conv_ofm_addr_w = conv_dst_ch_base_r + conv_dst_row_base_r + conv_ofm_col_w[AWIDTH-1:0];
assign conv_next_ic_base_w = conv_src_ch_base_r + ifm_bank_depth_r;
assign conv_read_bus_w = pack_5row_addr(conv_src_bank0_r,
                                         conv_rd_addr0_w,
                                         conv_rd_addr1_w,
                                         conv_rd_addr2_w,
                                         conv_rd_addr3_w,
                                         conv_rd_addr4_w);
assign conv_bank_sel_w = pack_5row_sel(conv_src_bank0_r);
assign pool_next_src_ch_base_w = pool_src_ch_base_r + ifm_bank_depth_r;
assign pool_rd_addr_bus_w = pack_pool_wr_bank_addr(pool_rd_addr_b0_r,
                                                   pool_rd_addr_b1_r,
                                                   pool_rd_addr_b2_r,
                                                   pool_rd_addr_b3_r,
                                                   pool_rd_addr_b4_r);
assign pool_rd_bank_en_raw_w = bank_read4_onehot(pool_src_bank0_r);
assign pool_rd_bank_en_w = pool_rd_ch_end_r ? 5'b11110 : pool_rd_bank_en_raw_w;
assign pool_next_ch_base_w = pool_ch_base_r + ofm_bank_depth_r;
assign pool_rd_ch_last_pix_w = ({16'd0, ofm_size_r} * {16'd0, ofm_size_r}) - 32'd1;
assign pool_rd_ch_pre_last_pix_w = pool_rd_ch_last_pix_w - 32'd1;
assign fc_weight_addr_w = weight_base_r + (fc_out_r * fc_chunk_count_r) + fc_chunk_r;


function [NBANKS-1:0] bank_onehot;
    input [2:0] bank_i;
    begin
        case (bank_i)
            3'd0: bank_onehot = 5'b00001;
            3'd1: bank_onehot = 5'b00010;
            3'd2: bank_onehot = 5'b00100;
            3'd3: bank_onehot = 5'b01000;
            3'd4: bank_onehot = 5'b10000;
            default: bank_onehot = 5'b00001;
        endcase
    end
endfunction

function [NBANKS-1:0] bank_read4_onehot;
    input [2:0] bank_i;
    begin
        case (bank_i)
            3'd0: bank_read4_onehot = 5'b01111;
            3'd1: bank_read4_onehot = 5'b11110;
            3'd2: bank_read4_onehot = 5'b11101;
            3'd3: bank_read4_onehot = 5'b11011;
            3'd4: bank_read4_onehot = 5'b10111;
            default: bank_read4_onehot = 5'b01111;
        endcase
    end
endfunction

function [NBANKS-1:0] bank_pair_onehot;
    input [2:0] bank_i;
    begin
        case (bank_i)
            3'd0: bank_pair_onehot = 5'b00011;
            3'd1: bank_pair_onehot = 5'b00110;
            3'd2: bank_pair_onehot = 5'b01100;
            3'd3: bank_pair_onehot = 5'b11000;
            3'd4: bank_pair_onehot = 5'b10001;
            default: bank_pair_onehot = 5'b00011;
        endcase
    end
endfunction

function [2:0] bank_inc;
    input [2:0] bank_i;
    begin
        case (bank_i)
            3'd0: bank_inc = 3'd1;
            3'd1: bank_inc = 3'd2;
            3'd2: bank_inc = 3'd3;
            3'd3: bank_inc = 3'd4;
            default: bank_inc = 3'd0;
        endcase
    end
endfunction

function [(NBANKS*AWIDTH)-1:0] same_bank_addr;
    input [AWIDTH-1:0] addr_i;
    begin
        same_bank_addr = {addr_i, addr_i, addr_i, addr_i, addr_i};
    end
endfunction

function [(NBANKS*AWIDTH)-1:0] pack_pool_wr_bank_addr;
    input [AWIDTH-1:0] b0_i;
    input [AWIDTH-1:0] b1_i;
    input [AWIDTH-1:0] b2_i;
    input [AWIDTH-1:0] b3_i;
    input [AWIDTH-1:0] b4_i;
    begin
        pack_pool_wr_bank_addr = {b4_i, b3_i, b2_i, b1_i, b0_i};
    end
endfunction

function [(NBANKS*AWIDTH)-1:0] pool_pair_waddr;
    input [2:0] bank_i;
    input [AWIDTH-1:0] addr_i;
    reg [AWIDTH-1:0] b0;
    reg [AWIDTH-1:0] b1;
    reg [AWIDTH-1:0] b2;
    reg [AWIDTH-1:0] b3;
    reg [AWIDTH-1:0] b4;
    begin
        b0 = addr_i;
        b1 = addr_i;
        b2 = addr_i;
        b3 = addr_i;
        b4 = addr_i;

        case (bank_i)
            3'd4: begin
                b4 = addr_i;
                b0 = addr_i + 1'b1;
            end
            default: begin
                b0 = addr_i;
                b1 = addr_i;
                b2 = addr_i;
                b3 = addr_i;
                b4 = addr_i;
            end
        endcase

        pool_pair_waddr = {b4, b3, b2, b1, b0};
    end
endfunction

function [2:0] bank_dec;
    input [2:0] bank_i;
    begin
        case (bank_i)
            3'd0: bank_dec = 3'd4;
            3'd1: bank_dec = 3'd0;
            3'd2: bank_dec = 3'd1;
            3'd3: bank_dec = 3'd2;
            default: bank_dec = 3'd3;
        endcase
    end
endfunction

function [(NBANKS*AWIDTH)-1:0] pool_read_addr_bus;
    input [2:0] src_bank0_i;
    input [AWIDTH-1:0] base_addr_i;
    input [AWIDTH-1:0] prev_addr_i;
    input [AWIDTH-1:0] stride_i;
    reg [AWIDTH-1:0] old_addr_w;
    reg [AWIDTH-1:0] b0;
    reg [AWIDTH-1:0] b1;
    reg [AWIDTH-1:0] b2;
    reg [AWIDTH-1:0] b3;
    reg [AWIDTH-1:0] b4;
    begin
        if (base_addr_i >= stride_i) begin
            old_addr_w = base_addr_i - stride_i;
        end
        else begin
            old_addr_w = {AWIDTH{1'b0}};
        end

        b0 = base_addr_i;
        b1 = base_addr_i;
        b2 = base_addr_i;
        b3 = base_addr_i;
        b4 = base_addr_i;

        case (src_bank0_i)
            3'd0: begin
                b0 = base_addr_i;
                b1 = base_addr_i;
                b2 = base_addr_i;
                b3 = base_addr_i;
                b4 = old_addr_w;
            end

            3'd4: begin
                b0 = base_addr_i;
                b1 = base_addr_i;
                b2 = base_addr_i;
                b3 = prev_addr_i;
                b4 = old_addr_w;
            end

            3'd3: begin
                b0 = base_addr_i;
                b1 = base_addr_i;
                b2 = prev_addr_i;
                b3 = old_addr_w;
                b4 = old_addr_w;
            end

            3'd2: begin
                b0 = base_addr_i;
                b1 = prev_addr_i;
                b2 = old_addr_w;
                b3 = old_addr_w;
                b4 = old_addr_w;
            end

            default: begin
                b0 = prev_addr_i;
                b1 = old_addr_w;
                b2 = old_addr_w;
                b3 = old_addr_w;
                b4 = old_addr_w;
            end
        endcase

        pool_read_addr_bus = {b4, b3, b2, b1, b0};
    end
endfunction

function [(NBANKS*AWIDTH)-1:0] pack_5row_addr;
    input [2:0] bank0_i;
    input [AWIDTH-1:0] addr0_i;
    input [AWIDTH-1:0] addr1_i;
    input [AWIDTH-1:0] addr2_i;
    input [AWIDTH-1:0] addr3_i;
    input [AWIDTH-1:0] addr4_i;
    begin
        case (bank0_i)
            3'd0: pack_5row_addr = {addr4_i, addr3_i, addr2_i, addr1_i, addr0_i};
            3'd1: pack_5row_addr = {addr3_i, addr2_i, addr1_i, addr0_i, addr4_i};
            3'd2: pack_5row_addr = {addr2_i, addr1_i, addr0_i, addr4_i, addr3_i};
            3'd3: pack_5row_addr = {addr1_i, addr0_i, addr4_i, addr3_i, addr2_i};
            3'd4: pack_5row_addr = {addr0_i, addr4_i, addr3_i, addr2_i, addr1_i};
            default: pack_5row_addr = {addr4_i, addr3_i, addr2_i, addr1_i, addr0_i};
        endcase
    end
endfunction

function [(NBANKS*3)-1:0] pack_5row_sel;
    input [2:0] bank0_i;
    begin
        case (bank0_i)
            3'd0: pack_5row_sel = {3'd4, 3'd3, 3'd2, 3'd1, 3'd0};
            3'd1: pack_5row_sel = {3'd0, 3'd4, 3'd3, 3'd2, 3'd1};
            3'd2: pack_5row_sel = {3'd1, 3'd0, 3'd4, 3'd3, 3'd2};
            3'd3: pack_5row_sel = {3'd2, 3'd1, 3'd0, 3'd4, 3'd3};
            3'd4: pack_5row_sel = {3'd3, 3'd2, 3'd1, 3'd0, 3'd4};
            default: pack_5row_sel = {3'd4, 3'd3, 3'd2, 3'd1, 3'd0};
        endcase
    end
endfunction

always @(*) begin
    case (state_r)
        S_IDLE:       next_state_r = load_done_i ? S_WAIT_LOAD : S_IDLE;
        S_WAIT_LOAD:  next_state_r = start_i ? S_LOAD_LAYER : S_WAIT_LOAD;
        S_LOAD_LAYER: next_state_r = S_RUN_LAYER;
        S_RUN_LAYER:  next_state_r = layer_done_r ? (layer_last_w ? S_DONE : S_LOAD_LAYER) : S_RUN_LAYER;
        S_DONE:       next_state_r = done_clear_i ? S_IDLE : S_DONE;
        default:      next_state_r = S_IDLE;
    endcase
end

always @(posedge CLK or negedge RST) begin
    if (!RST) begin
        state_r                 <= S_IDLE;
        layer_idx_r             <= 4'd0;
        layer_done_r            <= 1'b0;

        layer_op_r              <= OP_CONV;
        src_ping_r              <= 1'b1;
        dst_ping_r              <= 1'b0;
        ifm_size_r              <= 16'd0;
        ofm_size_r              <= 16'd0;
        ifm_last_r              <= 16'd0;
        ofm_last_r              <= 16'd0;
        in_ch_r                 <= 12'd0;
        out_ch_r                <= 12'd0;
        in_ch_last_r            <= 12'd0;
        out_ch_last_r           <= 12'd0;
        in_len_r                <= 16'd0;
        out_len_r               <= 16'd0;
        in_len_last_r           <= 16'd0;
        out_len_last_r          <= 16'd0;
        ifm_bank_depth_r        <= {AWIDTH{1'b0}};
        ofm_bank_depth_r        <= {AWIDTH{1'b0}};
        weight_base_r           <= {AWIDTH{1'b0}};
        bias_base_r             <= {AWIDTH{1'b0}};
        fc_chunk_count_r        <= 16'd0;
        fc_chunk_last_r         <= 16'd0;
        simple_total_r          <= 32'd0;
        simple_count_r          <= 32'd0;
        simple_bank_r           <= 3'd0;
        simple_addr_r           <= {AWIDTH{1'b0}};
        pool_pair_phase_r       <= 1'b0;
        pool_drain_r            <= 1'b0;
        pool_dst_bank_r         <= 3'd0;
        pool_dst_addr_r         <= {AWIDTH{1'b0}};
        pool_wr_fire_d1_r       <= 1'b0;
        pool_wr_fire_d2_r       <= 1'b0;
        pool_wr_fire_d3_r       <= 1'b0;
        pool_wr_bank_d1_r       <= {NBANKS{1'b0}};
        pool_wr_bank_d2_r       <= {NBANKS{1'b0}};
        pool_wr_bank_d3_r       <= {NBANKS{1'b0}};
        pool_wr_bank_base_d1_r  <= 3'd0;
        pool_wr_bank_base_d2_r  <= 3'd0;
        pool_wr_bank_base_d3_r  <= 3'd0;
        pool_wr_addr_d1_r       <= {AWIDTH{1'b0}};
        pool_wr_addr_d2_r       <= {AWIDTH{1'b0}};
        pool_wr_addr_d3_r       <= {AWIDTH{1'b0}};
        pool_wr_addr_bus_d1_r   <= {(NBANKS*AWIDTH){1'b0}};
        pool_wr_addr_bus_d2_r   <= {(NBANKS*AWIDTH){1'b0}};
        pool_wr_addr_bus_d3_r   <= {(NBANKS*AWIDTH){1'b0}};
        pool_wr_addr_b0_r       <= {AWIDTH{1'b0}};
        pool_wr_addr_b1_r       <= {AWIDTH{1'b0}};
        pool_wr_addr_b2_r       <= {AWIDTH{1'b0}};
        pool_wr_addr_b3_r       <= {AWIDTH{1'b0}};
        pool_wr_addr_b4_r       <= {AWIDTH{1'b0}};
        pool_ch_r               <= 12'd0;
        pool_row_r              <= 16'd0;
        pool_col_r              <= 16'd0;
        pool_ch_base_r          <= {AWIDTH{1'b0}};
        pool_row_base_r         <= {AWIDTH{1'b0}};
        pool_rd_col_r           <= 16'd0;
        pool_rd_row_r           <= 16'd0;
        pool_rd_pair_row_r      <= 16'd0;
        pool_rd_ch_r            <= 12'd0;
        pool_rd_ch_end_r        <= 1'b0;
        pool_rd_pix_r           <= 32'd0;
        pool_rd_local_col_r     <= 16'd0;
        pool_src_bank0_r        <= 3'd0;
        pool_src_ch_base_r      <= {AWIDTH{1'b0}};
        pool_src_row_base_r     <= {AWIDTH{1'b0}};
        pool_prev_read_addr_r   <= {AWIDTH{1'b0}};
        pool_ifm_stride_r       <= {AWIDTH{1'b0}};
        pool_rd_addr_b0_r       <= {AWIDTH{1'b0}};
        pool_rd_addr_b1_r       <= {AWIDTH{1'b0}};
        pool_rd_addr_b2_r       <= {AWIDTH{1'b0}};
        pool_rd_addr_b3_r       <= {AWIDTH{1'b0}};
        pool_rd_addr_b4_r       <= {AWIDTH{1'b0}};
        pool2_mode_r            <= 1'b0;

        conv_phase_r            <= CONV_LOAD;
        conv_load_row_r         <= 3'd0;
        conv_flush_cnt_r        <= 3'd0;
        conv_ic_r               <= 12'd0;
        conv_oc_r               <= 12'd0;
        conv_row_r              <= 16'd0;
        conv_col_r              <= 16'd0;
        conv_out_col_r          <= 16'd0;
        conv_src_bank0_r        <= 3'd0;
        conv_dst_bank_r         <= 3'd0;
        conv_src_ch_base_r      <= {AWIDTH{1'b0}};
        conv_dst_ch_base_r      <= {AWIDTH{1'b0}};
        conv_dst_row_base_r     <= {AWIDTH{1'b0}};
        conv_weight_addr_r      <= {AWIDTH{1'b0}};
        conv_bias_addr_r        <= {AWIDTH{1'b0}};
        conv_row0_base_r        <= {AWIDTH{1'b0}};
        conv_row1_base_r        <= {AWIDTH{1'b0}};
        conv_row2_base_r        <= {AWIDTH{1'b0}};
        conv_row3_base_r        <= {AWIDTH{1'b0}};
        conv_row4_base_r        <= {AWIDTH{1'b0}};
        weight_select_d_r       <= 3'd0;

        conv_s0_valid_r         <= 1'b0;
        conv_s0_first_r         <= 1'b0;
        conv_s0_last_r          <= 1'b0;
        conv_s0_prev_r          <= 1'b0;
        conv_s0_dst_ping_r      <= 1'b0;
        conv_s0_bank_r          <= {NBANKS{1'b0}};
        conv_s0_addr_r          <= {AWIDTH{1'b0}};
        conv_s1_valid_r         <= 1'b0;
        conv_s1_first_r         <= 1'b0;
        conv_s1_dst_ping_r      <= 1'b0;
        conv_s1_bank_r          <= {NBANKS{1'b0}};
        conv_s1_addr_r          <= {AWIDTH{1'b0}};

        fc_out_r                <= 16'd0;
        fc_chunk_r              <= 16'd0;
        fc_weight_addr_r        <= {AWIDTH{1'b0}};
        fc_ifm_addr_r           <= {AWIDTH{1'b0}};
        fc_bias_addr_r          <= {AWIDTH{1'b0}};
        fc_flush_cnt_r          <= 3'd0;
        fc_flush_r              <= 1'b0;
        fc_s0_valid_r           <= 1'b0;
        fc_s0_last_r            <= 1'b0;
        fc_s0_bias_r            <= 1'b0;
        fc_s0_dst_ping_r        <= 1'b0;
        fc_s0_bank_r            <= {NBANKS{1'b0}};
        fc_s0_addr_r            <= {AWIDTH{1'b0}};
        fc_s1_valid_r           <= 1'b0;
        fc_s1_dst_ping_r        <= 1'b0;
        fc_s1_bank_r            <= {NBANKS{1'b0}};
        fc_s1_addr_r            <= {AWIDTH{1'b0}};
        fc_s2_valid_r           <= 1'b0;
        fc_s2_dst_ping_r        <= 1'b0;
        fc_s2_bank_r            <= {NBANKS{1'b0}};
        fc_s2_addr_r            <= {AWIDTH{1'b0}};

        argmax_addr_r          <= 2'd0;
        argmax_rd_count_r      <= 2'd0;
        argmax_valid_count_r   <= 2'd0;
        argmax_mask_d1_r       <= 4'd0;
        argmax_last_d1_r       <= 1'b0;
        argmax_drain_r         <= 1'b0;
        argmax_done_d1_r       <= 1'b0;

        ping_rd_en_o            <= 1'b0;
        ping_raddr_o            <= {(NBANKS*AWIDTH){1'b0}};
        ping_wr_en_o            <= {NBANKS{1'b0}};
        ping_waddr_o            <= {(NBANKS*AWIDTH){1'b0}};
        pong_rd_en_o            <= 1'b0;
        pong_raddr_o            <= {(NBANKS*AWIDTH){1'b0}};
        pong_wr_en_o            <= {NBANKS{1'b0}};
        pong_wraddr_o           <= {(NBANKS*AWIDTH){1'b0}};
        weight_rd_en_o          <= 1'b0;
        weight_addr_o           <= {AWIDTH{1'b0}};
        bias_rd_en_o            <= 1'b0;
        bias_addr_o             <= {AWIDTH{1'b0}};
        pea_weight_load_o       <= 1'b0;
        pea_row_weight_select_o <= 3'd0;
        pea_execute_o           <= 1'b0;
        adder_valid_o           <= 1'b0;
        adder_first_channel_o   <= 1'b0;
        relu_last_channel_o     <= 1'b0;
        fc_data_valid_o         <= 1'b0;
        fc_last_chunk_o         <= 1'b0;
        fc_bias_valid_o         <= 1'b0;
        fc_relu_en_o            <= 1'b0;
        argmax_clear_o         <= 1'b0;
        argmax_data_valid_o    <= 1'b0;
        argmax_last_o          <= 1'b0;
        argmax_bank_valid_o    <= 4'd0;
        ifmap_bank_select_o     <= {(NBANKS*3){1'b0}};
        pool_wr_en_o            <= {NBANKS{1'b0}};
    end
    else begin
        state_r <= next_state_r;

        ping_rd_en_o            <= 1'b0;
        ping_raddr_o            <= {(NBANKS*AWIDTH){1'b0}};
        ping_wr_en_o            <= {NBANKS{1'b0}};
        ping_waddr_o            <= {(NBANKS*AWIDTH){1'b0}};
        pong_rd_en_o            <= 1'b0;
        pong_raddr_o            <= {(NBANKS*AWIDTH){1'b0}};
        pong_wr_en_o            <= {NBANKS{1'b0}};
        pong_wraddr_o           <= {(NBANKS*AWIDTH){1'b0}};
        weight_rd_en_o          <= 1'b0;
        weight_addr_o           <= {AWIDTH{1'b0}};
        bias_rd_en_o            <= 1'b0;
        bias_addr_o             <= {AWIDTH{1'b0}};
        pea_execute_o           <= 1'b0;
        adder_valid_o           <= 1'b0;
        adder_first_channel_o   <= 1'b0;
        relu_last_channel_o     <= 1'b0;
        fc_data_valid_o         <= 1'b0;
        fc_last_chunk_o         <= 1'b0;
        fc_bias_valid_o         <= 1'b0;
        argmax_clear_o         <= 1'b0;
        argmax_data_valid_o    <= 1'b0;
        argmax_last_o          <= 1'b0;
        argmax_bank_valid_o    <= 4'd0;
        ifmap_bank_select_o     <= {(NBANKS*3){1'b0}};

        pea_weight_load_o       <= weight_rd_en_o;
        pea_row_weight_select_o <= weight_select_d_r;

        conv_s1_valid_r         <= conv_s0_valid_r;
        conv_s1_first_r         <= conv_s0_first_r;
        conv_s1_dst_ping_r      <= conv_s0_dst_ping_r;
        conv_s1_bank_r          <= conv_s0_bank_r;
        conv_s1_addr_r          <= conv_s0_addr_r;
        conv_s0_valid_r         <= 1'b0;
        conv_s0_first_r         <= 1'b0;
        conv_s0_last_r          <= 1'b0;
        conv_s0_prev_r          <= 1'b0;
        conv_s0_dst_ping_r      <= 1'b0;
        conv_s0_bank_r          <= {NBANKS{1'b0}};
        conv_s0_addr_r          <= {AWIDTH{1'b0}};

        fc_s1_valid_r           <= fc_s0_valid_r;
        fc_s1_dst_ping_r        <= fc_s0_dst_ping_r;
        fc_s1_bank_r            <= fc_s0_bank_r;
        fc_s1_addr_r            <= fc_s0_addr_r;
        fc_s2_valid_r           <= fc_s1_valid_r;
        fc_s2_dst_ping_r        <= fc_s1_dst_ping_r;
        fc_s2_bank_r            <= fc_s1_bank_r;
        fc_s2_addr_r            <= fc_s1_addr_r;
        fc_s0_valid_r           <= 1'b0;
        fc_s0_last_r            <= 1'b0;
        fc_s0_bias_r            <= 1'b0;
        fc_s0_dst_ping_r        <= 1'b0;
        fc_s0_bank_r            <= {NBANKS{1'b0}};
        fc_s0_addr_r            <= {AWIDTH{1'b0}};

        if (state_r == S_IDLE) begin
            layer_idx_r  <= 4'd0;
            layer_done_r <= 1'b0;
        end
        else if ((state_r == S_RUN_LAYER) && layer_done_r) begin
            layer_done_r <= 1'b0;
            if (!layer_last_w) begin
                layer_idx_r <= layer_idx_r + 1'b1;
            end
        end
        else if (state_r == S_LOAD_LAYER) begin
            layer_done_r        <= 1'b0;
            conv_phase_r        <= CONV_LOAD;
            conv_load_row_r     <= 3'd0;
            conv_flush_cnt_r    <= 3'd0;
            conv_ic_r           <= 12'd0;
            conv_oc_r           <= 12'd0;
            conv_row_r          <= 16'd0;
            conv_col_r          <= 16'd0;
            conv_out_col_r      <= 16'd0;
            conv_src_bank0_r    <= 3'd0;
            conv_dst_bank_r     <= 3'd0;
            conv_src_ch_base_r  <= {AWIDTH{1'b0}};
            conv_dst_ch_base_r  <= {AWIDTH{1'b0}};
            conv_dst_row_base_r <= {AWIDTH{1'b0}};
            conv_row0_base_r    <= {AWIDTH{1'b0}};
            conv_row1_base_r    <= {AWIDTH{1'b0}};
            conv_row2_base_r    <= {AWIDTH{1'b0}};
            conv_row3_base_r    <= {AWIDTH{1'b0}};
            conv_row4_base_r    <= {AWIDTH{1'b0}};
            simple_count_r      <= 32'd0;
            simple_bank_r       <= 3'd0;
            simple_addr_r       <= {AWIDTH{1'b0}};
            pool_pair_phase_r   <= 1'b0;
            pool_drain_r        <= 1'b0;
            pool_dst_bank_r     <= 3'd0;
            pool_dst_addr_r     <= {AWIDTH{1'b0}};
            pool_rd_addr_b0_r   <= {AWIDTH{1'b0}};
            pool_rd_addr_b1_r   <= {AWIDTH{1'b0}};
            pool_rd_addr_b2_r   <= {AWIDTH{1'b0}};
            pool_rd_addr_b3_r   <= {AWIDTH{1'b0}};
            pool_rd_addr_b4_r   <= {AWIDTH{1'b0}};
            pool_wr_fire_d1_r   <= 1'b0;
            pool_wr_fire_d2_r   <= 1'b0;
            pool_wr_fire_d3_r   <= 1'b0;
            pool_wr_bank_d1_r   <= {NBANKS{1'b0}};
            pool_wr_bank_d2_r   <= {NBANKS{1'b0}};
            pool_wr_bank_d3_r   <= {NBANKS{1'b0}};
            pool_wr_addr_d1_r   <= {AWIDTH{1'b0}};
            pool_wr_addr_d2_r   <= {AWIDTH{1'b0}};
            pool_wr_addr_d3_r   <= {AWIDTH{1'b0}};
            pool_wr_addr_bus_d1_r <= {(NBANKS*AWIDTH){1'b0}};
            pool_wr_addr_bus_d2_r <= {(NBANKS*AWIDTH){1'b0}};
            pool_wr_addr_bus_d3_r <= {(NBANKS*AWIDTH){1'b0}};
            pool_wr_addr_b0_r   <= {AWIDTH{1'b0}};
            pool_wr_addr_b1_r   <= {AWIDTH{1'b0}};
            pool_wr_addr_b2_r   <= {AWIDTH{1'b0}};
            pool_wr_addr_b3_r   <= {AWIDTH{1'b0}};
            pool_wr_addr_b4_r   <= {AWIDTH{1'b0}};
            pool_wr_bank_base_d1_r <= 3'd0;
            pool_wr_bank_base_d2_r <= 3'd0;
            pool_wr_bank_base_d3_r <= 3'd0;
            pool_ch_r           <= 12'd0;
            pool_row_r          <= 16'd0;
            pool_col_r          <= 16'd0;
            pool_ch_base_r      <= {AWIDTH{1'b0}};
            pool_row_base_r     <= {AWIDTH{1'b0}};
            pool_rd_col_r       <= 16'd0;
            pool_rd_row_r       <= 16'd0;
            pool_rd_pair_row_r  <= 16'd0;
            pool_rd_ch_r        <= 12'd0;
            pool_rd_ch_end_r    <= 1'b0;
            pool_rd_pix_r       <= 32'd0;
            pool_rd_local_col_r <= 16'd0;
            pool_src_bank0_r    <= 3'd0;
            pool_src_ch_base_r  <= {AWIDTH{1'b0}};
            pool_src_row_base_r <= {AWIDTH{1'b0}};
            pool_prev_read_addr_r <= {AWIDTH{1'b0}};
            pool_dst_addr_r     <= {AWIDTH{1'b0}};
            pool_wr_en_o        <= {NBANKS{1'b0}};
            pool2_mode_r        <= 1'b0;
            fc_out_r            <= 16'd0;
            fc_chunk_r          <= 16'd0;
            fc_ifm_addr_r       <= {AWIDTH{1'b0}};
            fc_flush_cnt_r      <= 3'd0;
            fc_flush_r          <= 1'b0;
            fc_relu_en_o       <= 1'b0;
            argmax_addr_r      <= 2'd0;
            argmax_rd_count_r  <= 2'd0;
            argmax_valid_count_r <= 2'd0;
            argmax_mask_d1_r   <= 4'd0;
            argmax_last_d1_r   <= 1'b0;
            argmax_drain_r     <= 1'b0;
            argmax_done_d1_r   <= 1'b0;

            case (layer_idx_r)
                4'd0: begin
                    layer_op_r       <= OP_CONV;
                    src_ping_r       <= 1'b1;
                    dst_ping_r       <= 1'b0;
                    ifm_size_r       <= 16'd28;
                    ofm_size_r       <= 16'd24;
                    ifm_last_r       <= 16'd27;
                    ofm_last_r       <= 16'd23;
                    in_ch_r          <= 12'd1;
                    out_ch_r         <= 12'd8;
                    in_ch_last_r     <= 12'd0;
                    out_ch_last_r    <= 12'd7;
                    ifm_bank_depth_r <= 16'd168;
                    ofm_bank_depth_r <= 16'd120;
                    weight_base_r    <= CONV1_WEIGHT_BASE;
                    bias_base_r      <= CONV1_BIAS_BASE;
                    conv_weight_addr_r <= CONV1_WEIGHT_BASE;
                    conv_bias_addr_r   <= CONV1_BIAS_BASE;
                end
                4'd1: begin
                    layer_op_r       <= OP_POOL;
                    src_ping_r       <= 1'b0;
                    dst_ping_r       <= 1'b1;
                    ifm_size_r       <= 16'd24;
                    ofm_size_r       <= 16'd12;
                    ifm_last_r       <= 16'd23;
                    ofm_last_r       <= 16'd11;
                    in_ch_r          <= 12'd8;
                    out_ch_r         <= 12'd8;
                    out_ch_last_r    <= 12'd7;
                    ifm_bank_depth_r <= 16'd120;
                    pool_ifm_stride_r <= 16'd24;
                    pool2_mode_r     <= 1'b0;
                    ofm_bank_depth_r <= 16'd36;
                    simple_total_r   <= 32'd1152;
                end
                4'd2: begin
                    layer_op_r       <= OP_CONV;
                    src_ping_r       <= 1'b1;
                    dst_ping_r       <= 1'b0;
                    ifm_size_r       <= 16'd12;
                    ofm_size_r       <= 16'd8;
                    ifm_last_r       <= 16'd11;
                    ofm_last_r       <= 16'd7;
                    in_ch_r          <= 12'd8;
                    out_ch_r         <= 12'd20;
                    in_ch_last_r     <= 12'd7;
                    out_ch_last_r    <= 12'd19;
                    ifm_bank_depth_r <= 16'd36;
                    ofm_bank_depth_r <= 16'd16;
                    weight_base_r    <= CONV2_WEIGHT_BASE;
                    bias_base_r      <= CONV2_BIAS_BASE;
                    conv_weight_addr_r <= CONV2_WEIGHT_BASE;
                    conv_bias_addr_r   <= CONV2_BIAS_BASE;
                end
                4'd3: begin
                    layer_op_r       <= OP_POOL;
                    src_ping_r       <= 1'b0;
                    dst_ping_r       <= 1'b1;
                    ifm_size_r       <= 16'd8;
                    ofm_size_r       <= 16'd4;
                    ifm_last_r       <= 16'd7;
                    ofm_last_r       <= 16'd3;
                    in_ch_r          <= 12'd20;
                    out_ch_r         <= 12'd20;
                    out_ch_last_r    <= 12'd19;
                    ifm_bank_depth_r <= 16'd16;
                    pool_ifm_stride_r <= 16'd8;
                    pool2_mode_r     <= 1'b1;
                    ofm_bank_depth_r <= 16'd4;
                    simple_total_r   <= 32'd320;
                end
                4'd4: begin
                    // FC1 + ReLU
                    layer_op_r       <= OP_FC;
                    src_ping_r       <= 1'b1;
                    dst_ping_r       <= 1'b0;
                    in_len_r         <= 16'd320;
                    out_len_r        <= 16'd128;
                    in_len_last_r    <= 16'd319;
                    out_len_last_r   <= 16'd127;
                    fc_chunk_count_r <= 16'd80;
                    fc_chunk_last_r  <= 16'd79;
                    weight_base_r    <= FC1_WEIGHT_BASE;
                    bias_base_r      <= FC1_BIAS_BASE;
                    fc_weight_addr_r <= FC1_WEIGHT_BASE;
                    fc_bias_addr_r   <= FC1_BIAS_BASE;
                    fc_relu_en_o     <= 1'b1;
                end
                4'd5: begin
                    // FC2 + ReLU
                    layer_op_r       <= OP_FC;
                    src_ping_r       <= 1'b0;
                    dst_ping_r       <= 1'b1;
                    in_len_r         <= 16'd128;
                    out_len_r        <= 16'd84;
                    in_len_last_r    <= 16'd127;
                    out_len_last_r   <= 16'd83;
                    fc_chunk_count_r <= 16'd32;
                    fc_chunk_last_r  <= 16'd31;
                    weight_base_r    <= FC2_WEIGHT_BASE;
                    bias_base_r      <= FC2_BIAS_BASE;
                    fc_weight_addr_r <= FC2_WEIGHT_BASE;
                    fc_bias_addr_r   <= FC2_BIAS_BASE;
                    fc_relu_en_o     <= 1'b1;
                end
                4'd6: begin
                    // FC3, no ReLU
                    layer_op_r       <= OP_FC;
                    src_ping_r       <= 1'b1;
                    dst_ping_r       <= 1'b0;
                    in_len_r         <= 16'd84;
                    out_len_r        <= 16'd10;
                    in_len_last_r    <= 16'd83;
                    out_len_last_r   <= 16'd9;
                    fc_chunk_count_r <= 16'd21;
                    fc_chunk_last_r  <= 16'd20;
                    weight_base_r    <= FC3_WEIGHT_BASE;
                    bias_base_r      <= FC3_BIAS_BASE;
                    fc_weight_addr_r <= FC3_WEIGHT_BASE;
                    fc_bias_addr_r   <= FC3_BIAS_BASE;
                    fc_relu_en_o     <= 1'b0;
                end
                4'd7: begin
                    // ArgMax over FC3 outputs stored in Pong banks 0..3.
                    layer_op_r       <= OP_ARGMAX;
                    src_ping_r       <= 1'b0;
                    dst_ping_r       <= 1'b0;
                    simple_total_r   <= 32'd10;
                    argmax_clear_o   <= 1'b1;
                end
                default: begin
                    layer_op_r       <= OP_RELU;
                    src_ping_r       <= 1'b0;
                    dst_ping_r       <= 1'b0;
                    simple_total_r   <= 32'd1;
                end
            endcase
        end
        else if ((state_r == S_RUN_LAYER) && !layer_done_r) begin
            case (layer_op_r)
                OP_CONV: begin
                    pea_execute_o         <= conv_s0_valid_r;
                    relu_last_channel_o   <= conv_s0_valid_r & conv_s0_last_r;
                    adder_valid_o         <= conv_s1_valid_r;
                    adder_first_channel_o <= conv_s1_valid_r & conv_s1_first_r;

                    if (conv_s0_valid_r && conv_s0_prev_r) begin
                        if (conv_s0_dst_ping_r) begin
                            ping_rd_en_o <= 1'b1;
                            ping_raddr_o <= same_bank_addr(conv_s0_addr_r);
                        end
                        else begin
                            pong_rd_en_o <= 1'b1;
                            pong_raddr_o <= same_bank_addr(conv_s0_addr_r);
                        end
                    end

                    if (conv_s1_valid_r) begin
                        if (conv_s1_dst_ping_r) begin
                            ping_wr_en_o <= conv_s1_bank_r;
                            ping_waddr_o <= same_bank_addr(conv_s1_addr_r);
                        end
                        else begin
                            pong_wr_en_o  <= conv_s1_bank_r;
                            pong_wraddr_o <= same_bank_addr(conv_s1_addr_r);
                        end
                    end

                    case (conv_phase_r)
                        CONV_LOAD: begin
                            // Start IFM streaming in the same cycle as weight read.
                            // After the 5 weight-load cycles, IFM streaming continues in CONV_FEED
                            // while weight_rd_en_o goes low. This lets the filter slide across FM.
                            weight_rd_en_o      <= 1'b1;
                            weight_addr_o       <= conv_weight_addr_r;
                            weight_select_d_r   <= conv_load_row_r;
                            ifmap_bank_select_o <= conv_bank_sel_w;

                            if (src_ping_r) begin
                                ping_rd_en_o <= 1'b1;
                                ping_raddr_o <= conv_read_bus_w;
                            end
                            else begin
                                pong_rd_en_o <= 1'b1;
                                pong_raddr_o <= conv_read_bus_w;
                            end

                            if (conv_ofm_issue_w) begin
                                conv_s0_valid_r    <= 1'b1;
                                conv_s0_first_r    <= (conv_ic_r == 12'd0);
                                conv_s0_last_r     <= (conv_ic_r == in_ch_last_r);
                                conv_s0_prev_r     <= (conv_ic_r != 12'd0);
                                conv_s0_dst_ping_r <= dst_ping_r;
                                conv_s0_bank_r     <= bank_onehot(conv_dst_bank_r);
                                conv_s0_addr_r     <= conv_ofm_addr_w;
                            end

                            if ((conv_load_row_r == 3'd0) && (conv_ic_r == 12'd0)) begin
                                bias_rd_en_o <= 1'b1;
                                bias_addr_o  <= conv_bias_addr_r;
                            end

                            conv_weight_addr_r <= conv_weight_addr_r + 1'b1;

                            if (conv_col_r != ifm_last_r) begin
                                conv_col_r <= conv_col_r + 1'b1;
                                if (conv_ofm_issue_w && !conv_row_last_issue_w) begin
                                    conv_out_col_r <= conv_out_col_r + 1'b1;
                                end
                            end

                            if (conv_load_row_r == 3'd4) begin
                                conv_load_row_r <= 3'd0;
                                conv_phase_r    <= CONV_FEED;
                            end
                            else begin
                                conv_load_row_r <= conv_load_row_r + 1'b1;
                            end
                        end

                        CONV_FEED: begin
                            // Continue IFM streaming after weight load finishes.
                            // Here weight_rd_en_o remains 0, but Ping/Pong keeps sliding over FM.
                            ifmap_bank_select_o <= conv_bank_sel_w;
                            if (src_ping_r) begin
                                ping_rd_en_o <= 1'b1;
                                ping_raddr_o <= conv_read_bus_w;
                            end
                            else begin
                                pong_rd_en_o <= 1'b1;
                                pong_raddr_o <= conv_read_bus_w;
                            end

                            if (conv_ofm_issue_w) begin
                                conv_s0_valid_r    <= 1'b1;
                                conv_s0_first_r    <= (conv_ic_r == 12'd0);
                                conv_s0_last_r     <= (conv_ic_r == in_ch_last_r);
                                conv_s0_prev_r     <= (conv_ic_r != 12'd0);
                                conv_s0_dst_ping_r <= dst_ping_r;
                                conv_s0_bank_r     <= bank_onehot(conv_dst_bank_r);
                                conv_s0_addr_r     <= conv_ofm_addr_w;
                            end

                            if (conv_col_r == ifm_last_r) begin
                                conv_col_r     <= 16'd0;
                                conv_out_col_r <= 16'd0;

                                if (conv_row_r == ofm_last_r) begin
                                    conv_row_r          <= 16'd0;
                                    conv_src_bank0_r    <= 3'd0;
                                    conv_dst_bank_r     <= 3'd0;
                                    conv_dst_row_base_r <= {AWIDTH{1'b0}};

                                    if ((conv_ic_r == in_ch_last_r) && (conv_oc_r == out_ch_last_r)) begin
                                        conv_phase_r     <= CONV_FLUSH;
                                        conv_flush_cnt_r <= 3'd0;
                                    end
                                    else begin
                                        conv_phase_r     <= CONV_LOAD;
                                        if (conv_ic_r == in_ch_last_r) begin
                                            conv_ic_r          <= 12'd0;
                                            conv_src_ch_base_r <= {AWIDTH{1'b0}};
                                            conv_row0_base_r   <= {AWIDTH{1'b0}};
                                            conv_row1_base_r   <= {AWIDTH{1'b0}};
                                            conv_row2_base_r   <= {AWIDTH{1'b0}};
                                            conv_row3_base_r   <= {AWIDTH{1'b0}};
                                            conv_row4_base_r   <= {AWIDTH{1'b0}};
                                            conv_oc_r          <= conv_oc_r + 1'b1;
                                            conv_dst_ch_base_r <= conv_dst_ch_base_r + ofm_bank_depth_r;
                                            conv_dst_bank_r    <= 3'd0;
                                            conv_dst_row_base_r <= {AWIDTH{1'b0}};
                                            conv_bias_addr_r   <= conv_bias_addr_r + 1'b1;
                                        end
                                        else begin
                                            conv_ic_r          <= conv_ic_r + 1'b1;
                                            conv_src_ch_base_r <= conv_next_ic_base_w;
                                            // Each input channel starts at the same base address on all 5 banks.
                                            // Rows are striped across banks inside a channel, so bank4 can have
                                            // smaller used depth than bank0..bank3. The next channel base is still
                                            // common for every bank, especially for Conv2 reading Pool1 output.
                                            conv_row0_base_r   <= conv_next_ic_base_w;
                                            conv_row1_base_r   <= conv_next_ic_base_w;
                                            conv_row2_base_r   <= conv_next_ic_base_w;
                                            conv_row3_base_r   <= conv_next_ic_base_w;
                                            conv_row4_base_r   <= conv_next_ic_base_w;
                                            conv_src_bank0_r   <= 3'd0;
                                        end
                                    end
                                end
                                else begin
                                    conv_row_r       <= conv_row_r + 1'b1;
                                    conv_row0_base_r <= conv_row1_base_r;
                                    conv_row1_base_r <= conv_row2_base_r;
                                    conv_row2_base_r <= conv_row3_base_r;
                                    conv_row3_base_r <= conv_row4_base_r;
                                    conv_row4_base_r <= conv_row0_base_r + ifm_size_r[AWIDTH-1:0];
                                    conv_src_bank0_r <= bank_inc(conv_src_bank0_r);
                                    conv_dst_bank_r  <= bank_inc(conv_dst_bank_r);
                                    if (conv_dst_bank_r == 3'd4) begin
                                        conv_dst_row_base_r <= conv_dst_row_base_r + ofm_size_r[AWIDTH-1:0];
                                    end
                                end
                            end
                            else begin
                                conv_col_r <= conv_col_r + 1'b1;
                                if (conv_ofm_issue_w && !conv_row_last_issue_w) begin
                                    conv_out_col_r <= conv_out_col_r + 1'b1;
                                end
                            end
                        end

                        CONV_FLUSH: begin
                            if (conv_flush_cnt_r == 3'd5) begin
                                layer_done_r <= 1'b1;
                            end
                            else begin
                                conv_flush_cnt_r <= conv_flush_cnt_r + 1'b1;
                            end
                        end

                        default: begin
                            conv_phase_r <= CONV_LOAD;
                        end
                    endcase
                end

                OP_POOL: begin
                    pool_rd_ch_end_r <= 1'b0;
                    pool_wr_fire_d3_r <= pool_wr_fire_d2_r;
                    pool_wr_fire_d2_r <= pool_wr_fire_d1_r;
                    pool_wr_bank_d3_r <= pool_wr_bank_d2_r;
                    pool_wr_bank_d2_r <= pool_wr_bank_d1_r;
                    pool_wr_bank_base_d3_r <= pool_wr_bank_base_d2_r;
                    pool_wr_bank_base_d2_r <= pool_wr_bank_base_d1_r;
                    pool_wr_addr_d3_r <= pool_wr_addr_d2_r;
                    pool_wr_addr_d2_r <= pool_wr_addr_d1_r;
                    pool_wr_addr_bus_d3_r <= pool_wr_addr_bus_d2_r;
                    pool_wr_addr_bus_d2_r <= pool_wr_addr_bus_d1_r;
                    if (pool_wr_fire_d1_r) begin
                        pool_wr_en_o <= pool_wr_bank_d1_r;
                    end
                    pool_wr_fire_d1_r <= 1'b0;
                    pool_wr_bank_d1_r <= bank_pair_onehot(pool_dst_bank_r);
                    pool_wr_bank_base_d1_r <= pool_dst_bank_r;
                    pool_wr_addr_d1_r <= pool_ch_base_r + pool_row_base_r + pool_col_r[AWIDTH-1:0];
                    pool_wr_addr_bus_d1_r <= pack_pool_wr_bank_addr(pool_wr_addr_b0_r,
                                                                     pool_wr_addr_b1_r,
                                                                     pool_wr_addr_b2_r,
                                                                     pool_wr_addr_b3_r,
                                                                     pool_wr_addr_b4_r);

                    if (pool_wr_fire_d1_r && ~pool_rd_ch_end_r) begin
                        if (pool_wr_bank_d1_r[0]) begin
                            pool_wr_addr_b0_r <= pool_wr_addr_b0_r + 1'b1;
                        end
                        if (pool_wr_bank_d1_r[1]) begin
                            pool_wr_addr_b1_r <= pool_wr_addr_b1_r + 1'b1;
                        end
                        if (pool_wr_bank_d1_r[2]) begin
                            pool_wr_addr_b2_r <= pool_wr_addr_b2_r + 1'b1;
                        end
                        if (pool_wr_bank_d1_r[3]) begin
                            pool_wr_addr_b3_r <= pool_wr_addr_b3_r + 1'b1;
                        end
                        if (pool_wr_bank_d1_r[4]) begin
                            pool_wr_addr_b4_r <= pool_wr_addr_b4_r + 1'b1;
                        end
                    end

                    if (pool_wr_fire_d3_r) begin
                        if (dst_ping_r) begin
                            ping_wr_en_o <= pool_wr_bank_d3_r;
                            ping_waddr_o <= pool_wr_addr_bus_d3_r;
                        end
                        else begin
                            pong_wr_en_o  <= pool_wr_bank_d3_r;
                            pong_wraddr_o <= pool_wr_addr_bus_d3_r;
                        end
                    end

                    if (pool_drain_r) begin
                        if (!pool_wr_fire_d1_r && !pool_wr_fire_d2_r && !pool_wr_fire_d3_r) begin
                            layer_done_r <= 1'b1;
                        end
                    end
                    else begin
                        if (src_ping_r) begin
                            ping_rd_en_o <= 1'b1;
                            ping_raddr_o <= pool_rd_addr_bus_w;
                        end
                        else begin
                            pong_rd_en_o <= 1'b1;
                            pong_raddr_o <= pool_rd_addr_bus_w;
                        end

                        if (!pool_pair_phase_r) begin
                            pool_wr_fire_d1_r <= 1'b1;

                            if (pool_col_r == ofm_last_r) begin
                                pool_col_r <= 16'd0;

                                if (pool_row_r >= (ofm_size_r - 16'd2)) begin
                                    pool_row_r      <= 16'd0;
                                    pool_row_base_r <= {AWIDTH{1'b0}};
                                    pool_dst_bank_r <= 3'd0;

                                    if (pool_ch_r == out_ch_last_r) begin
                                        pool_ch_r      <= 12'd0;
                                        pool_ch_base_r <= {AWIDTH{1'b0}};
                                        pool_dst_bank_r <= 3'd0;
                                        pool_row_base_r <= {AWIDTH{1'b0}};
                                        pool_wr_addr_b0_r <= {AWIDTH{1'b0}};
                                        pool_wr_addr_b1_r <= {AWIDTH{1'b0}};
                                        pool_wr_addr_b2_r <= {AWIDTH{1'b0}};
                                        pool_wr_addr_b3_r <= {AWIDTH{1'b0}};
                                        pool_wr_addr_b4_r <= {AWIDTH{1'b0}};
                                    end
                                    else begin
                                        pool_ch_r      <= pool_ch_r + 1'b1;
                                        pool_ch_base_r <= pool_next_ch_base_w;
                                        pool_dst_bank_r <= 3'd0;
                                        pool_row_base_r <= {AWIDTH{1'b0}};
                                        pool_col_r      <= 16'd0;
                                        pool_wr_addr_b0_r <= pool_next_ch_base_w;
                                        pool_wr_addr_b1_r <= pool_next_ch_base_w;
                                        pool_wr_addr_b2_r <= pool_next_ch_base_w;
                                        pool_wr_addr_b3_r <= pool_next_ch_base_w;
                                        pool_wr_addr_b4_r <= pool_next_ch_base_w;
                                    end
                                end
                                else begin
                                    pool_row_r <= pool_row_r + 16'd2;

                                    case (pool_dst_bank_r)
                                        3'd0: begin
                                            pool_dst_bank_r <= 3'd2;
                                        end
                                        3'd1: begin
                                            pool_dst_bank_r <= 3'd3;
                                        end
                                        3'd2: begin
                                            pool_dst_bank_r <= 3'd4;
                                        end
                                        3'd3: begin
                                            pool_dst_bank_r <= 3'd0;
                                            pool_row_base_r <= pool_row_base_r + ofm_size_r[AWIDTH-1:0];
                                        end
                                        default: begin
                                            pool_dst_bank_r <= 3'd1;
                                            pool_row_base_r <= pool_row_base_r + ofm_size_r[AWIDTH-1:0];
                                        end
                                    endcase
                                end
                            end
                            else begin
                                pool_col_r <= pool_col_r + 1'b1;
                            end
                        end
                        pool_pair_phase_r <= ~pool_pair_phase_r;

                        if (simple_count_r == (simple_total_r - 1'b1)) begin
                            pool_drain_r <= 1'b1;
                        end
                        else begin
                            simple_count_r <= simple_count_r + 1'b1;

                            if (pool_rd_bank_en_w[0]) begin
                                pool_rd_addr_b0_r <= pool_rd_addr_b0_r + 1'b1;
                            end
                            if (pool_rd_bank_en_w[1]) begin
                                pool_rd_addr_b1_r <= pool_rd_addr_b1_r + 1'b1;
                            end
                            if (pool_rd_bank_en_w[2]) begin
                                pool_rd_addr_b2_r <= pool_rd_addr_b2_r + 1'b1;
                            end
                            if (pool_rd_bank_en_w[3]) begin
                                pool_rd_addr_b3_r <= pool_rd_addr_b3_r + 1'b1;
                            end
                            if (pool_rd_bank_en_w[4]) begin
                                pool_rd_addr_b4_r <= pool_rd_addr_b4_r + 1'b1;
                            end

                            // pool_rd_bank_en_w is combinationally driven from the registered
                            // pool_rd_ch_end_r, so assert pool_rd_ch_end_r one cycle before
                            // the channel actually wraps. This makes the special final-read
                            // bank mask active on the last pixel of the current input channel.
                            if ((pool_rd_pix_r == pool_rd_ch_pre_last_pix_w) &&
                                (pool_rd_ch_r != out_ch_last_r)) begin
                                pool_rd_ch_end_r <= 1'b1;
                            end

                            if (pool_rd_local_col_r == (pool_ifm_stride_r - 1'b1)) begin
                                pool_rd_local_col_r <= 16'd0;
                                pool_rd_col_r       <= pool_rd_col_r + 1'b1;
                                pool_src_bank0_r    <= bank_dec(pool_src_bank0_r);

                                if (pool_rd_pix_r == pool_rd_ch_last_pix_w) begin
                                    pool_rd_pix_r        <= 32'd0;
                                    pool_rd_pair_row_r   <= 16'd0;
                                    pool_rd_row_r        <= 16'd0;
                                    pool_rd_col_r        <= 16'd0;
                                    pool_rd_local_col_r  <= 16'd0;
                                    pool_src_bank0_r     <= 3'd0;

                                    if (pool_rd_ch_r == out_ch_last_r) begin
                                        pool_rd_ch_r        <= 12'd0;
                                        pool_src_ch_base_r  <= {AWIDTH{1'b0}};
                                        pool_rd_addr_b0_r   <= {AWIDTH{1'b0}};
                                        pool_rd_addr_b1_r   <= {AWIDTH{1'b0}};
                                        pool_rd_addr_b2_r   <= {AWIDTH{1'b0}};
                                        pool_rd_addr_b3_r   <= {AWIDTH{1'b0}};
                                        pool_rd_addr_b4_r   <= {AWIDTH{1'b0}};
                                    end
                                    else begin
                                        pool_rd_ch_r        <= pool_rd_ch_r + 1'b1;
                                        pool_src_ch_base_r  <= pool_next_src_ch_base_w;
                                        pool_rd_addr_b0_r   <= pool_next_src_ch_base_w;
                                        pool_rd_addr_b1_r   <= pool_next_src_ch_base_w;
                                        pool_rd_addr_b2_r   <= pool_next_src_ch_base_w;
                                        pool_rd_addr_b3_r   <= pool_next_src_ch_base_w;
                                        pool_rd_addr_b4_r   <= pool_next_src_ch_base_w;
                                    end
                                end
                                else begin
                                    pool_rd_pix_r <= pool_rd_pix_r + 1'b1;

                                    if (pool_src_bank0_r == 3'd1) begin
                                        pool_rd_pair_row_r <= pool_rd_pair_row_r + 16'd2;
                                        pool_rd_row_r      <= pool_rd_row_r + 16'd2;
                                    end
                                end
                            end
                            else begin
                                pool_rd_pix_r       <= pool_rd_pix_r + 1'b1;
                                pool_rd_col_r       <= pool_rd_col_r + 1'b1;
                                pool_rd_local_col_r <= pool_rd_local_col_r + 1'b1;
                            end

                            if (simple_bank_r == 3'd4) begin
                                simple_bank_r <= 3'd0;
                                simple_addr_r <= simple_addr_r + 1'b1;
                            end
                            else begin
                                simple_bank_r <= simple_bank_r + 1'b1;
                            end
                        end
                    end
                end

                OP_FC: begin
                    fc_data_valid_o <= fc_s0_valid_r;
                    fc_last_chunk_o <= fc_s0_last_r;
                    fc_bias_valid_o <= fc_s0_bias_r;

                    if (fc_s2_valid_r) begin
                        if (fc_s2_dst_ping_r) begin
                            ping_wr_en_o <= fc_s2_bank_r;
                            ping_waddr_o <= same_bank_addr(fc_s2_addr_r);
                        end
                        else begin
                            pong_wr_en_o  <= fc_s2_bank_r;
                            pong_wraddr_o <= same_bank_addr(fc_s2_addr_r);
                        end
                    end

                    if (fc_flush_r) begin
                        if (fc_flush_cnt_r == 3'd4) begin
                            layer_done_r <= 1'b1;
                        end
                        else begin
                            fc_flush_cnt_r <= fc_flush_cnt_r + 1'b1;
                        end
                    end
                    else begin
                        weight_rd_en_o <= 1'b1;
                        weight_addr_o  <= fc_weight_addr_w;

                        if (src_ping_r) begin
                            ping_rd_en_o <= 1'b1;
                            ping_raddr_o <= same_bank_addr(fc_ifm_addr_r);
                        end
                        else begin
                            pong_rd_en_o <= 1'b1;
                            pong_raddr_o <= same_bank_addr(fc_ifm_addr_r);
                        end

                        if (fc_chunk_r == 16'd0) begin
                            bias_rd_en_o <= 1'b1;
                            bias_addr_o  <= fc_bias_addr_r;
                        end

                        fc_s0_valid_r    <= 1'b1;
                        fc_s0_last_r     <= (fc_chunk_r == fc_chunk_last_r);
                        fc_s0_bias_r     <= (fc_chunk_r == 16'd0);
                        fc_s0_dst_ping_r <= dst_ping_r;
                        fc_s0_bank_r     <= bank_onehot(simple_bank_r);
                        fc_s0_addr_r     <= simple_addr_r;


                        if (fc_chunk_r == fc_chunk_last_r) begin
                            fc_chunk_r    <= 16'd0;
                            fc_ifm_addr_r <= {AWIDTH{1'b0}};
                            fc_bias_addr_r <= fc_bias_addr_r + 1'b1;

                            if (fc_out_r == out_len_last_r) begin
                                fc_flush_r     <= 1'b1;
                                fc_flush_cnt_r <= 3'd0;
                            end
                            else begin
                                fc_out_r <= fc_out_r + 1'b1;
                                if (simple_bank_r == 3'd3) begin
                                    simple_bank_r <= 3'd0;
                                    simple_addr_r <= simple_addr_r + 1'b1;
                                end
                                else begin
                                    simple_bank_r <= simple_bank_r + 1'b1;
                                end
                            end
                        end
                        else begin
                            fc_chunk_r    <= fc_chunk_r + 1'b1;
                            fc_ifm_addr_r <= fc_ifm_addr_r + 1'b1;
                        end
                    end
                end

                OP_ARGMAX: begin
                    // Read FC3 logits from Pong memory. FC3 has 10 outputs:
                    //   addr0 bank0..3 -> index 0..3
                    //   addr1 bank0..3 -> index 4..7
                    //   addr2 bank0..1 -> index 8..9
                    argmax_data_valid_o <= |argmax_mask_d1_r;
                    argmax_bank_valid_o <= argmax_mask_d1_r;
                    argmax_last_o       <= argmax_last_d1_r;
                    argmax_mask_d1_r    <= 4'd0;
                    argmax_last_d1_r    <= 1'b0;

                    if (!argmax_drain_r) begin
                        pong_rd_en_o  <= 1'b1;
                        pong_raddr_o  <= same_bank_addr({{(AWIDTH-2){1'b0}}, argmax_addr_r});

                        case (argmax_rd_count_r)
                            2'd0: argmax_mask_d1_r <= 4'b1111;
                            2'd1: argmax_mask_d1_r <= 4'b1111;
                            default: argmax_mask_d1_r <= 4'b0011;
                        endcase
                        argmax_last_d1_r <= (argmax_rd_count_r == 2'd2);

                        if (argmax_rd_count_r == 2'd2) begin
                            argmax_drain_r <= 1'b1;
                        end
                        else begin
                            argmax_rd_count_r <= argmax_rd_count_r + 1'b1;
                            argmax_addr_r     <= argmax_addr_r + 1'b1;
                        end
                    end
                    else if (!argmax_last_d1_r && (argmax_mask_d1_r == 4'd0)) begin
                        if (!argmax_done_d1_r) begin
                            argmax_done_d1_r <= 1'b1;
                        end
                        else begin
                            layer_done_r     <= 1'b1;
                            argmax_done_d1_r <= 1'b0;
                        end
                    end
                end

                OP_RELU: begin
                    if (src_ping_r) begin
                        ping_rd_en_o <= 1'b1;
                        ping_raddr_o <= same_bank_addr(simple_addr_r);
                    end
                    else begin
                        pong_rd_en_o <= 1'b1;
                        pong_raddr_o <= same_bank_addr(simple_addr_r);
                    end

                    if (dst_ping_r) begin
                        ping_wr_en_o <= bank_onehot(simple_bank_r);
                        ping_waddr_o <= same_bank_addr(simple_addr_r);
                    end
                    else begin
                        pong_wr_en_o  <= bank_onehot(simple_bank_r);
                        pong_wraddr_o <= same_bank_addr(simple_addr_r);
                    end
                    relu_last_channel_o <= 1'b1;

                    if (simple_count_r == (simple_total_r - 1'b1)) begin
                        layer_done_r <= 1'b1;
                    end
                    else begin
                        simple_count_r <= simple_count_r + 1'b1;
                        if (simple_bank_r == 3'd4) begin
                            simple_bank_r <= 3'd0;
                            simple_addr_r <= simple_addr_r + 1'b1;
                        end
                        else begin
                            simple_bank_r <= simple_bank_r + 1'b1;
                        end
                    end
                end

                default: begin
                    layer_done_r <= 1'b1;
                end
            endcase
        end
    end
end

assign state_o    = state_r;
assign done_o     = (state_r == S_DONE);
assign layer_op_o = layer_op_r;
endmodule


