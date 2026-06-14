`timescale 1 ns / 1 ps

module controller #(
    parameter int AWIDTH       = 10,
    parameter int DWIDTH       = 16,
    parameter int INST_DWIDTH  = 64
)(
    input  logic                     CLK,
    input  logic                     RST, // Active-low asynchronous reset

    //================================//
    //          From Arbiter          //
    //================================//
    input  logic                     load_flag_i,
    input  logic                     start_flag_i,
    input  logic                     done_flag_i,
    input  logic [AWIDTH-1:0]        max_IM_addr_i,
    output logic [2:0]               state_o,
    output logic                     complete_o,

    //================================//
    //        To Weight Memory        //
    //================================//
    output logic                     ctrl_WM_bank0_rd_en_o,
    output logic                     ctrl_WM_bank1_rd_en_o,
    output logic                     ctrl_WM_bank2_rd_en_o,
    output logic                     ctrl_WM_bank3_rd_en_o,
    output logic                     ctrl_WM_bank4_rd_en_o,

    output logic [AWIDTH-1:0]        ctrl_WM_bank0_addr_o,
    output logic [AWIDTH-1:0]        ctrl_WM_bank1_addr_o,
    output logic [AWIDTH-1:0]        ctrl_WM_bank2_addr_o,
    output logic [AWIDTH-1:0]        ctrl_WM_bank3_addr_o,
    output logic [AWIDTH-1:0]        ctrl_WM_bank4_addr_o,

    //================================//
    //         To Bias Memory         //
    //================================//
    output logic                     ctrl_BM_bank0_rd_en_o,
    output logic                     ctrl_BM_bank1_rd_en_o,
    output logic                     ctrl_BM_bank2_rd_en_o,
    output logic                     ctrl_BM_bank3_rd_en_o,
    output logic                     ctrl_BM_bank4_rd_en_o,

    output logic [AWIDTH-1:0]        ctrl_BM_bank0_addr_o,
    output logic [AWIDTH-1:0]        ctrl_BM_bank1_addr_o,
    output logic [AWIDTH-1:0]        ctrl_BM_bank2_addr_o,
    output logic [AWIDTH-1:0]        ctrl_BM_bank3_addr_o,
    output logic [AWIDTH-1:0]        ctrl_BM_bank4_addr_o,

    //================================//
    //      To Instruction Memory     //
    //================================//
    output logic                     ctrl_IM_rd_en_o,
    output logic [AWIDTH-1:0]        ctrl_IM_addr_o,

    //================================//
    //    From Instruction Memory     //
    //================================//
    input  logic [INST_DWIDTH-1:0]   instruction_i,
    input  logic                     instruction_valid_i,

    //================================//
    //        To Ping FM Memory       //
    //================================//
    output logic                     ctrl_Ping_FM_bank0_rd_en_o,
    output logic                     ctrl_Ping_FM_bank1_rd_en_o,
    output logic                     ctrl_Ping_FM_bank2_rd_en_o,
    output logic                     ctrl_Ping_FM_bank3_rd_en_o,
    output logic                     ctrl_Ping_FM_bank4_rd_en_o,

    output logic                     ctrl_Ping_FM_bank0_wr_en_o,
    output logic                     ctrl_Ping_FM_bank1_wr_en_o,
    output logic                     ctrl_Ping_FM_bank2_wr_en_o,
    output logic                     ctrl_Ping_FM_bank3_wr_en_o,
    output logic                     ctrl_Ping_FM_bank4_wr_en_o,

    output logic [AWIDTH-1:0]        ctrl_Ping_FM_bank0_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Ping_FM_bank1_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Ping_FM_bank2_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Ping_FM_bank3_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Ping_FM_bank4_addr_o,

    //================================//
    //        To Pong FM Memory       //
    //================================//
    output logic                     ctrl_Pong_FM_bank0_rd_en_o,
    output logic                     ctrl_Pong_FM_bank1_rd_en_o,
    output logic                     ctrl_Pong_FM_bank2_rd_en_o,
    output logic                     ctrl_Pong_FM_bank3_rd_en_o,
    output logic                     ctrl_Pong_FM_bank4_rd_en_o,

    output logic                     ctrl_Pong_FM_bank0_wr_en_o,
    output logic                     ctrl_Pong_FM_bank1_wr_en_o,
    output logic                     ctrl_Pong_FM_bank2_wr_en_o,
    output logic                     ctrl_Pong_FM_bank3_wr_en_o,
    output logic                     ctrl_Pong_FM_bank4_wr_en_o,

    output logic [AWIDTH-1:0]        ctrl_Pong_FM_bank0_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Pong_FM_bank1_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Pong_FM_bank2_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Pong_FM_bank3_addr_o,
    output logic [AWIDTH-1:0]        ctrl_Pong_FM_bank4_addr_o,

    //================================//
    //            From PEA            //
    //================================//
    input  logic                     bank0_mem_ofmap_valid_i,
    input  logic                     bank1_mem_ofmap_valid_i,
    input  logic                     bank2_mem_ofmap_valid_i,
    input  logic                     bank3_mem_ofmap_valid_i,
    input  logic                     bank4_mem_ofmap_valid_i,

    //================================//
    //             To PEA             //
    //================================//
    output logic                     first_ifmap_o,
    output logic                     last_ifmap_o,
    output logic                     execute_o,
    output logic                     ifm_from_north_o,

    //================================//
    //        To Line Buffer          //
    //================================//
    output logic                     line_buffer_load_o,
    output logic                     line_buffer_shift_o,
    output logic [2:0]               pool_step_o,

    // Decoded Instruction Outputs (for Post-Processing Unit)
    output logic [3:0]               layer_type_o,
    output logic [11:0]              in_channels_o,
    output logic [11:0]              out_channels_o,
    output logic [7:0]               activation_o
);

    //================================//
    //           Localparam           //
    //================================//
    typedef enum logic [2:0] {
        s_IDLE      = 3'd0,
        s_LOAD      = 3'd1,
        s_FETCH     = 3'd2,
        s_DECODE    = 3'd3,
        s_EXEC_CONV = 3'd4,
        s_EXEC_POOL = 3'd5,
        s_READ      = 3'd6
    } state_t;

    //================================//
    //       Register Declaration     //
    //================================//
    state_t                        current_state_r;
    state_t                        next_state_r;

    logic [AWIDTH:0]               ctrl_IM_addr_r;

    // Decoded instruction registers
    logic [3:0]                    layer_type_r;
    logic [15:0]                   INPUT_WIDTH_r;
    logic [11:0]                   IN_CH_r;
    logic [11:0]                   OUT_CH_r;
    logic [3:0]                    KERNEL_r;
    logic [3:0]                    STRIDE_r;
    logic [3:0]                    PAD_r;
    logic [7:0]                    activation_r;
    logic [15:0]                   OUTPUT_WIDTH_r;

    // Loop counters for CONV / FC execution
    logic [3:0]                    KERNEL_x_counter_r;
    logic [3:0]                    KERNEL_y_counter_r;
    logic [11:0]                   IN_CH_counter_r;
    logic [15:0]                   OUTPUT_X_counter_r;
    logic [15:0]                   OUTPUT_Y_counter_r;
    logic [11:0]                   OUT_CH_counter_r;

    // Division-free group indices for block addressing
    logic [7:0]                    OUTPUT_X_block_r;
    logic [11:0]                   OUT_CH_group_r;

    // Delayed registers for write-back pipeline synchronization (5 cycles delay)
    logic [11:0]                   OUT_CH_counter_d1_r, OUT_CH_counter_d2_r, OUT_CH_counter_d3_r, OUT_CH_counter_d4_r, OUT_CH_counter_d5_r;
    logic [15:0]                   OUTPUT_Y_counter_d1_r, OUTPUT_Y_counter_d2_r, OUTPUT_Y_counter_d3_r, OUTPUT_Y_counter_d4_r, OUTPUT_Y_counter_d5_r;
    logic [7:0]                    OUTPUT_X_block_d1_r, OUTPUT_X_block_d2_r, OUTPUT_X_block_d3_r, OUTPUT_X_block_d4_r, OUTPUT_X_block_d5_r;
    logic [15:0]                   OUTPUT_X_counter_d1_r, OUTPUT_X_counter_d2_r, OUTPUT_X_counter_d3_r, OUTPUT_X_counter_d4_r, OUTPUT_X_counter_d5_r;

    // Output capture row counter (staggered write row index)
    logic [2:0]                    OFMAP_row_counter_r;

    // PEA interface registers
    logic                          first_ifmap_r;
    logic                          last_ifmap_r;
    logic                          execute_r;
    logic                          ifm_from_north_r;
    logic                          line_buffer_load_r;
    logic                          line_buffer_shift_r;

    // Control flags for execution termination
    logic                          read_WM_BM_stop_r;
    logic                          last_exec_tile_r;
    logic [2:0]                    last_ofmap_cnt_r;

    //================================//
    //      Max Pooling Registers     //
    //================================//
    logic [2:0]                    pool_step_r; // 0 to 4
    logic [11:0]                   POOL_CH_counter_r;
    logic [15:0]                   POOL_Y_counter_r;
    logic [15:0]                   POOL_X_counter_r;
    logic [7:0]                    POOL_X_block_r;

    //================================//
    //         Wire Declaration       //
    //================================//
    logic                          fetch_done_flag_w;
    logic                          Ping_Pong_Select_w;

    logic                          kernel_x_last_w;
    logic                          kernel_y_last_w;
    logic                          in_ch_last_w;
    logic                          output_x_last_w;
    logic                          output_y_last_w;
    logic                          out_ch_last_w;

    logic                          last_ifm_issue_w;
    logic                          last_ofmap_valid_w;
    logic                          last_exec_tile_w;
    logic                          last_ofmap_count_hit_w;

    logic                          wm_row0_rd_en_w;
    logic                          bm_row0_rd_en_w;

    logic                          first_ifmap_int_w;
    logic                          last_ifmap_int_w;
    logic                          execute_int_w;

    logic                          ifm_from_north_pre_w;
    logic                          line_buffer_load_pre_w;
    logic                          line_buffer_shift_pre_w;

    // Lookup values for banked dimensions (to avoid division by 5)
    logic [7:0]                    W_prime;
    logic [11:0]                   H_W_prime;
    logic [7:0]                    W_prime_in;
    logic [11:0]                   H_W_prime_in;

    // Write-back address wires
    logic                          ofmap_write_fire_w;
    logic [11:0]                   ofmap_out_ch_w;
    logic [AWIDTH-1:0]             ofmap_write_addr_w;

    //================================//
    //        Lookups (No Div)        //
    //================================//
    // Lookups for output banked BRAM sizes
    always_comb begin
        case (OUTPUT_WIDTH_r)
            16'd28:  begin W_prime = 8'd6; H_W_prime = 12'd168; end
            16'd14:  begin W_prime = 8'd3; H_W_prime = 12'd42;  end
            16'd10:  begin W_prime = 8'd2; H_W_prime = 12'd20;  end
            16'd5:   begin W_prime = 8'd1; H_W_prime = 12'd5;   end
            16'd1:   begin W_prime = 8'd1; H_W_prime = 12'd1;   end
            default: begin W_prime = 8'd1; H_W_prime = 12'd1;   end
        endcase
    end

    // Lookups for input banked BRAM sizes
    always_comb begin
        case (INPUT_WIDTH_r)
            16'd32:  begin W_prime_in = 8'd7; H_W_prime_in = 12'd224; end
            16'd28:  begin W_prime_in = 8'd6; H_W_prime_in = 12'd168; end
            16'd14:  begin W_prime_in = 8'd3; H_W_prime_in = 12'd42;  end
            16'd10:  begin W_prime_in = 8'd2; H_W_prime_in = 12'd20;  end
            16'd5:   begin W_prime_in = 8'd1; H_W_prime_in = 12'd5;   end
            16'd1:   begin W_prime_in = 8'd1; H_W_prime_in = 12'd1;   end
            default: begin W_prime_in = 8'd1; H_W_prime_in = 12'd1;   end
        endcase
    end

    //================================//
    //              FSM               //
    //================================//
    always_comb begin
        case (current_state_r)
            s_IDLE:      if (load_flag_i) next_state_r = s_LOAD; else next_state_r = s_IDLE;
            s_LOAD:      if (start_flag_i) next_state_r = s_FETCH; else next_state_r = s_LOAD;
            s_FETCH:     if (fetch_done_flag_w) next_state_r = s_DECODE; else next_state_r = s_FETCH;
            s_DECODE:    begin
                if (instruction_valid_i) begin
                    if (instruction_i[63:60] == 4'h1 || instruction_i[63:60] == 4'h3)
                        next_state_r = s_EXEC_CONV;
                    else if (instruction_i[63:60] == 4'h2)
                        next_state_r = s_EXEC_POOL;
                    else
                        next_state_r = s_READ;
                end else begin
                    next_state_r = s_READ;
                end
            end
            s_EXEC_CONV: begin
                if (last_ofmap_valid_w) begin
                    if (ctrl_IM_addr_r > {1'b0, max_IM_addr_i}) next_state_r = s_READ; else next_state_r = s_FETCH;
                end else begin
                    next_state_r = s_EXEC_CONV;
                end
            end
            s_EXEC_POOL: begin
                if (pool_step_r == 3'd4 && POOL_X_block_r == (OUTPUT_WIDTH_r - 1)/5 && POOL_Y_counter_r == OUTPUT_WIDTH_r - 1 && POOL_CH_counter_r == OUT_CH_r - 1) begin
                    if (ctrl_IM_addr_r > {1'b0, max_IM_addr_i}) next_state_r = s_READ; else next_state_r = s_FETCH;
                end else begin
                    next_state_r = s_EXEC_POOL;
                end
            end
            s_READ:      if (done_flag_i) next_state_r = s_IDLE; else next_state_r = s_READ;
            default:     next_state_r = s_IDLE;
        endcase
    end

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST)
            current_state_r <= s_IDLE;
        else
            current_state_r <= next_state_r;
    end

    assign state_o        = current_state_r;
    assign complete_o     = (current_state_r == s_READ);
    assign layer_type_o   = layer_type_r;
    assign in_channels_o  = IN_CH_r;
    assign out_channels_o = OUT_CH_r;
    assign activation_o   = activation_r;

    //================================//
    //           FETCH State          //
    //================================//
    assign ctrl_IM_rd_en_o    = (current_state_r == s_FETCH);
    assign ctrl_IM_addr_o     = ctrl_IM_addr_r[AWIDTH-1:0];
    assign fetch_done_flag_w  = ctrl_IM_rd_en_o;

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            ctrl_IM_addr_r <= {(AWIDTH+1){1'b0}};
        end else begin
            if (current_state_r == s_IDLE)
                ctrl_IM_addr_r <= {(AWIDTH+1){1'b0}};
            else if (current_state_r == s_FETCH)
                ctrl_IM_addr_r <= ctrl_IM_addr_r + 1'b1;
        end
    end

    //================================//
    //          DECODE State          //
    //================================//
    function automatic [15:0] calc_out_width(
        input [15:0] in_width_i,
        input [3:0]  stride_i,
        input [3:0]  kernel_i
    );
        if (stride_i == 4'd2)
            return in_width_i >> 1;
        else
            return in_width_i - kernel_i + 1;
    endfunction

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            layer_type_r   <= 4'd0;
            INPUT_WIDTH_r  <= 16'd0;
            IN_CH_r        <= 12'd0;
            OUT_CH_r       <= 12'd0;
            KERNEL_r       <= 4'd0;
            STRIDE_r       <= 4'd0;
            PAD_r          <= 4'd0;
            activation_r   <= 8'd0;
            OUTPUT_WIDTH_r <= 16'd0;
        end else begin
            if (current_state_r == s_IDLE) begin
                layer_type_r   <= 4'd0;
                INPUT_WIDTH_r  <= 16'd0;
                IN_CH_r        <= 12'd0;
                OUT_CH_r       <= 12'd0;
                KERNEL_r       <= 4'd0;
                STRIDE_r       <= 4'd0;
                PAD_r          <= 4'd0;
                activation_r   <= 8'd0;
                OUTPUT_WIDTH_r <= 16'd0;
            end else if ((current_state_r == s_DECODE) && instruction_valid_i) begin
                layer_type_r   <= instruction_i[63:60];
                INPUT_WIDTH_r  <= instruction_i[59:44];
                IN_CH_r        <= instruction_i[43:32];
                OUT_CH_r       <= instruction_i[31:20];
                KERNEL_r       <= instruction_i[19:16];
                STRIDE_r       <= instruction_i[15:12];
                PAD_r          <= instruction_i[11:8];
                activation_r   <= instruction_i[7:0];
                OUTPUT_WIDTH_r <= calc_out_width(instruction_i[59:44], instruction_i[15:12], instruction_i[19:16]);
            end
        end
    end

    //================================//
    //        EXEC_CONV State         //
    //================================//
    assign kernel_x_last_w  = (KERNEL_x_counter_r == (KERNEL_r - 1'b1));
    assign kernel_y_last_w  = (KERNEL_y_counter_r == (KERNEL_r - 1'b1));
    assign in_ch_last_w     = (IN_CH_counter_r    == (IN_CH_r   - 1'b1));
    assign output_x_last_w  = (OUTPUT_X_counter_r >= (OUTPUT_WIDTH_r - 5));
    assign output_y_last_w  = (OUTPUT_Y_counter_r == (OUTPUT_WIDTH_r - 1));
    assign out_ch_last_w    = (OUT_CH_counter_r   >= (OUT_CH_r - 5));

    assign last_ifm_issue_w = (current_state_r == s_EXEC_CONV) &&
                              (KERNEL_x_counter_r == 0) && // BRAM read active cycle
                              kernel_y_last_w &&
                              in_ch_last_w &&
                              output_x_last_w &&
                              output_y_last_w &&
                              out_ch_last_w;

    assign last_exec_tile_w       = read_WM_BM_stop_r;
    assign last_ofmap_count_hit_w = (last_ofmap_cnt_r == 3'd4);

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            KERNEL_x_counter_r <= 4'd0;
            KERNEL_y_counter_r <= 4'd0;
            IN_CH_counter_r    <= 12'd0;
            OUTPUT_X_counter_r <= 16'd0;
            OUTPUT_Y_counter_r <= 16'd0;
            OUT_CH_counter_r   <= 12'd0;

            OUTPUT_X_block_r   <= 8'd0;
            OUT_CH_group_r     <= 12'd0;

            read_WM_BM_stop_r  <= 1'b0;
            last_exec_tile_r   <= 1'b0;
            last_ofmap_cnt_r   <= 3'd0;
        end else begin
            if (current_state_r == s_EXEC_CONV) begin
                if (in_ch_last_w && kernel_x_last_w && kernel_y_last_w && output_x_last_w && output_y_last_w && out_ch_last_w)
                    read_WM_BM_stop_r <= 1'b1;

                if (last_exec_tile_w)
                    last_exec_tile_r <= last_exec_tile_w;

                if (last_exec_tile_r && bank0_mem_ofmap_valid_i)
                    last_ofmap_cnt_r <= last_ofmap_cnt_r + 1'b1;
                else
                    last_ofmap_cnt_r <= 3'd0;

                if (!read_WM_BM_stop_r) begin
                    if (kernel_x_last_w) begin
                        KERNEL_x_counter_r <= 4'd0;
                        if (kernel_y_last_w) begin
                            KERNEL_y_counter_r <= 4'd0;
                            if (in_ch_last_w) begin
                                IN_CH_counter_r <= 12'd0;
                                if (output_x_last_w) begin
                                    OUTPUT_X_counter_r <= 16'd0;
                                    OUTPUT_X_block_r   <= 8'd0;
                                    if (output_y_last_w) begin
                                        OUTPUT_Y_counter_r <= 16'd0;
                                        if (out_ch_last_w) begin
                                            OUT_CH_counter_r <= 12'd0;
                                            OUT_CH_group_r   <= 12'd0;
                                        end else begin
                                            OUT_CH_counter_r <= OUT_CH_counter_r + 3'd5;
                                            OUT_CH_group_r   <= OUT_CH_group_r + 1'b1;
                                        end
                                    end else begin
                                        OUTPUT_Y_counter_r <= OUTPUT_Y_counter_r + 1'b1;
                                    end
                                end else begin
                                    OUTPUT_X_counter_r <= OUTPUT_X_counter_r + 3'd5;
                                    OUTPUT_X_block_r   <= OUTPUT_X_block_r + 1'b1;
                                end
                            end else begin
                                IN_CH_counter_r <= IN_CH_counter_r + 1'b1;
                            end
                        end else begin
                            KERNEL_y_counter_r <= KERNEL_y_counter_r + 1'b1;
                        end
                    end else begin
                        KERNEL_x_counter_r <= KERNEL_x_counter_r + 1'b1;
                    end
                end
            end else begin
                KERNEL_x_counter_r <= 4'd0;
                KERNEL_y_counter_r <= 4'd0;
                IN_CH_counter_r    <= 12'd0;
                OUTPUT_X_counter_r <= 16'd0;
                OUTPUT_Y_counter_r <= 16'd0;
                OUT_CH_counter_r   <= 12'd0;

                OUTPUT_X_block_r   <= 8'd0;
                OUT_CH_group_r     <= 12'd0;

                read_WM_BM_stop_r  <= 1'b0;
                last_exec_tile_r   <= 1'b0;
                last_ofmap_cnt_r   <= 3'd0;
            end
        end
    end

    // Delay lines for write back synchronization (5 cycles delay)
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            OUT_CH_counter_d1_r   <= 0; OUT_CH_counter_d2_r   <= 0; OUT_CH_counter_d3_r   <= 0; OUT_CH_counter_d4_r   <= 0; OUT_CH_counter_d5_r   <= 0;
            OUTPUT_Y_counter_d1_r <= 0; OUTPUT_Y_counter_d2_r <= 0; OUTPUT_Y_counter_d3_r <= 0; OUTPUT_Y_counter_d4_r <= 0; OUTPUT_Y_counter_d5_r <= 0;
            OUTPUT_X_block_d1_r   <= 0; OUTPUT_X_block_d2_r   <= 0; OUTPUT_X_block_d3_r   <= 0; OUTPUT_X_block_d4_r   <= 0; OUTPUT_X_block_d5_r   <= 0;
            OUTPUT_X_counter_d1_r <= 0; OUTPUT_X_counter_d2_r <= 0; OUTPUT_X_counter_d3_r <= 0; OUTPUT_X_counter_d4_r <= 0; OUTPUT_X_counter_d5_r <= 0;
        end else if (current_state_r == s_EXEC_CONV) begin
            OUT_CH_counter_d1_r   <= OUT_CH_counter_r;
            OUT_CH_counter_d2_r   <= OUT_CH_counter_d1_r;
            OUT_CH_counter_d3_r   <= OUT_CH_counter_d2_r;
            OUT_CH_counter_d4_r   <= OUT_CH_counter_d3_r;
            OUT_CH_counter_d5_r   <= OUT_CH_counter_d4_r;

            OUTPUT_Y_counter_d1_r <= OUTPUT_Y_counter_r;
            OUTPUT_Y_counter_d2_r <= OUTPUT_Y_counter_d1_r;
            OUTPUT_Y_counter_d3_r <= OUTPUT_Y_counter_d2_r;
            OUTPUT_Y_counter_d4_r <= OUTPUT_Y_counter_d3_r;
            OUTPUT_Y_counter_d5_r <= OUTPUT_Y_counter_d4_r;

            OUTPUT_X_block_d1_r   <= OUTPUT_X_block_r;
            OUTPUT_X_block_d2_r   <= OUTPUT_X_block_d1_r;
            OUTPUT_X_block_d3_r   <= OUTPUT_X_block_d2_r;
            OUTPUT_X_block_d4_r   <= OUTPUT_X_block_d3_r;
            OUTPUT_X_block_d5_r   <= OUTPUT_X_block_d4_r;

            OUTPUT_X_counter_d1_r <= OUTPUT_X_counter_r;
            OUTPUT_X_counter_d2_r <= OUTPUT_X_counter_d1_r;
            OUTPUT_X_counter_d3_r <= OUTPUT_X_counter_d2_r;
            OUTPUT_X_counter_d4_r <= OUTPUT_X_counter_d3_r;
            OUTPUT_X_counter_d5_r <= OUTPUT_X_counter_d4_r;
        end
    end

    //================================//
    //        Weight Memory          //
    //================================//
    assign wm_row0_rd_en_w = (current_state_r == s_EXEC_CONV) && !read_WM_BM_stop_r;

    logic wm_row1_rd_en_r, wm_row2_rd_en_r, wm_row3_rd_en_r, wm_row4_rd_en_r;
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            wm_row1_rd_en_r <= 1'b0;
            wm_row2_rd_en_r <= 1'b0;
            wm_row3_rd_en_r <= 1'b0;
            wm_row4_rd_en_r <= 1'b0;
        end else begin
            wm_row1_rd_en_r <= wm_row0_rd_en_w;
            wm_row2_rd_en_r <= wm_row1_rd_en_r;
            wm_row3_rd_en_r <= wm_row2_rd_en_r;
            wm_row4_rd_en_r <= wm_row3_rd_en_r;
        end
    end

    assign ctrl_WM_bank0_rd_en_o = wm_row0_rd_en_w;
    assign ctrl_WM_bank1_rd_en_o = wm_row1_rd_en_r;
    assign ctrl_WM_bank2_rd_en_o = wm_row2_rd_en_r;
    assign ctrl_WM_bank3_rd_en_o = wm_row3_rd_en_r;
    assign ctrl_WM_bank4_rd_en_o = wm_row4_rd_en_r;

    assign ctrl_WM_bank0_addr_o = ctrl_WM_bank0_rd_en_o ? ((((OUT_CH_group_r * IN_CH_r) + IN_CH_counter_r) * KERNEL_r + KERNEL_y_counter_r) * KERNEL_r + KERNEL_x_counter_r) : {AWIDTH{1'b0}};
    assign ctrl_WM_bank1_addr_o = ctrl_WM_bank1_rd_en_o ? ((((OUT_CH_group_r * IN_CH_r) + IN_CH_counter_r) * KERNEL_r + KERNEL_y_counter_r) * KERNEL_r + KERNEL_x_counter_r) : {AWIDTH{1'b0}};
    assign ctrl_WM_bank2_addr_o = ctrl_WM_bank2_rd_en_o ? ((((OUT_CH_group_r * IN_CH_r) + IN_CH_counter_r) * KERNEL_r + KERNEL_y_counter_r) * KERNEL_r + KERNEL_x_counter_r) : {AWIDTH{1'b0}};
    assign ctrl_WM_bank3_addr_o = ctrl_WM_bank3_rd_en_o ? ((((OUT_CH_group_r * IN_CH_r) + IN_CH_counter_r) * KERNEL_r + KERNEL_y_counter_r) * KERNEL_r + KERNEL_x_counter_r) : {AWIDTH{1'b0}};
    assign ctrl_WM_bank4_addr_o = ctrl_WM_bank4_rd_en_o ? ((((OUT_CH_group_r * IN_CH_r) + IN_CH_counter_r) * KERNEL_r + KERNEL_y_counter_r) * KERNEL_r + KERNEL_x_counter_r) : {AWIDTH{1'b0}};

    //================================//
    //          Bias Memory           //
    //================================//
    assign bm_row0_rd_en_w = (current_state_r == s_EXEC_CONV) && (KERNEL_x_counter_r == 0) && (KERNEL_y_counter_r == 0) && (IN_CH_counter_r == 0) && !read_WM_BM_stop_r;

    logic bm_row1_rd_en_r, bm_row2_rd_en_r, bm_row3_rd_en_r, bm_row4_rd_en_r;
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            bm_row1_rd_en_r <= 1'b0;
            bm_row2_rd_en_r <= 1'b0;
            bm_row3_rd_en_r <= 1'b0;
            bm_row4_rd_en_r <= 1'b0;
        end else begin
            bm_row1_rd_en_r <= bm_row0_rd_en_w;
            bm_row2_rd_en_r <= bm_row1_rd_en_r;
            bm_row3_rd_en_r <= bm_row2_rd_en_r;
            bm_row4_rd_en_r <= bm_row3_rd_en_r;
        end
    end

    assign ctrl_BM_bank0_rd_en_o = bm_row0_rd_en_w;
    assign ctrl_BM_bank1_rd_en_o = bm_row1_rd_en_r;
    assign ctrl_BM_bank2_rd_en_o = bm_row2_rd_en_r;
    assign ctrl_BM_bank3_rd_en_o = bm_row3_rd_en_r;
    assign ctrl_BM_bank4_rd_en_o = bm_row4_rd_en_r;

    assign ctrl_BM_bank0_addr_o = bm_row0_rd_en_w ? OUT_CH_group_r : {AWIDTH{1'b0}};
    assign ctrl_BM_bank1_addr_o = bm_row1_rd_en_r ? OUT_CH_group_r : {AWIDTH{1'b0}};
    assign ctrl_BM_bank2_addr_o = bm_row2_rd_en_r ? OUT_CH_group_r : {AWIDTH{1'b0}};
    assign ctrl_BM_bank3_addr_o = bm_row3_rd_en_r ? OUT_CH_group_r : {AWIDTH{1'b0}};
    assign ctrl_BM_bank4_addr_o = bm_row4_rd_en_r ? OUT_CH_group_r : {AWIDTH{1'b0}};

    //================================//
    //      IFM Address (CONV/FC)     //
    //================================//
    logic [AWIDTH-1:0] ifm_conv_addr_w;
    assign ifm_conv_addr_w = (IN_CH_counter_r * INPUT_WIDTH_r * W_prime_in) + 
                             ((OUTPUT_Y_counter_r + KERNEL_y_counter_r) * W_prime_in) + 
                             OUTPUT_X_block_r + ((KERNEL_x_counter_r == 1) ? 1'b1 : 1'b0);

    //================================//
    //        OFMAP Write-Back        //
    //================================//
    assign ofmap_write_fire_w = bank0_mem_ofmap_valid_i |
                                 bank1_mem_ofmap_valid_i |
                                 bank2_mem_ofmap_valid_i |
                                 bank3_mem_ofmap_valid_i |
                                 bank4_mem_ofmap_valid_i;

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            OFMAP_row_counter_r <= 3'd0;
        end else begin
            if (current_state_r != s_EXEC_CONV)
                OFMAP_row_counter_r <= 3'd0;
            else if (ofmap_write_fire_w) begin
                if (OFMAP_row_counter_r == 3'd4)
                    OFMAP_row_counter_r <= 3'd0;
                else
                    OFMAP_row_counter_r <= OFMAP_row_counter_r + 1'b1;
            end
        end
    end

    assign ofmap_out_ch_w     = OUT_CH_counter_d5_r + OFMAP_row_counter_r;
    assign ofmap_write_addr_w = (ofmap_out_ch_w * H_W_prime) + (OUTPUT_Y_counter_d5_r * W_prime) + OUTPUT_X_block_d5_r;

    assign last_ofmap_valid_w = last_exec_tile_r && bank0_mem_ofmap_valid_i && last_ofmap_count_hit_w;

    // Ping/Pong selection based on Instruction address LSB (0 -> Ping is source, Pong is dest; 1 -> Pong is source, Ping is dest)
    assign Ping_Pong_Select_w = ctrl_IM_addr_r[0];

    //================================//
    //        EXEC_POOL State         //
    //================================//
    assign pool_step_o = pool_step_r;

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            pool_step_r        <= 3'd0;
            POOL_CH_counter_r  <= 12'd0;
            POOL_Y_counter_r   <= 16'd0;
            POOL_X_counter_r   <= 16'd0;
            POOL_X_block_r     <= 8'd0;
        end else if (current_state_r == s_EXEC_POOL) begin
            if (pool_step_r == 3'd4) begin
                pool_step_r <= 3'd0;
                if (POOL_X_block_r == (OUTPUT_WIDTH_r - 1)/5) begin
                    POOL_X_block_r   <= 8'd0;
                    POOL_X_counter_r <= 16'd0;
                    if (POOL_Y_counter_r == OUTPUT_WIDTH_r - 1) begin
                        POOL_Y_counter_r <= 16'd0;
                        if (POOL_CH_counter_r == OUT_CH_r - 1) begin
                            POOL_CH_counter_r <= 12'd0;
                        end else begin
                            POOL_CH_counter_r <= POOL_CH_counter_r + 1'b1;
                        end
                    end else begin
                        POOL_Y_counter_r <= POOL_Y_counter_r + 1'b1;
                    end
                end else begin
                    POOL_X_block_r   <= POOL_X_block_r + 1'b1;
                    POOL_X_counter_r <= POOL_X_counter_r + 3'd5;
                end
            end else begin
                pool_step_r <= pool_step_r + 1'b1;
            end
        end else begin
            pool_step_r        <= 3'd0;
            POOL_CH_counter_r  <= 12'd0;
            POOL_Y_counter_r   <= 16'd0;
            POOL_X_counter_r   <= 16'd0;
            POOL_X_block_r     <= 8'd0;
        end
    end

    // Read addresses for Max Pool input (from source memory)
    logic [AWIDTH-1:0] pool_read_addr_w;
    always_comb begin
        case (pool_step_r)
            3'd0: pool_read_addr_w = (POOL_CH_counter_r * INPUT_WIDTH_r * W_prime_in) + ((POOL_Y_counter_r * 2) * W_prime_in) + (POOL_X_block_r * 2);
            3'd1: pool_read_addr_w = (POOL_CH_counter_r * INPUT_WIDTH_r * W_prime_in) + ((POOL_Y_counter_r * 2) * W_prime_in) + (POOL_X_block_r * 2) + 1'b1;
            3'd2: pool_read_addr_w = (POOL_CH_counter_r * INPUT_WIDTH_r * W_prime_in) + ((POOL_Y_counter_r * 2 + 1) * W_prime_in) + (POOL_X_block_r * 2);
            3'd3: pool_read_addr_w = (POOL_CH_counter_r * INPUT_WIDTH_r * W_prime_in) + ((POOL_Y_counter_r * 2 + 1) * W_prime_in) + (POOL_X_block_r * 2) + 1'b1;
            default: pool_read_addr_w = {AWIDTH{1'b0}};
        endcase
    end

    // Write address for Max Pool output (to destination memory)
    logic [AWIDTH-1:0] pool_write_addr_w;
    assign pool_write_addr_w = (POOL_CH_counter_r * H_W_prime) + (POOL_Y_counter_r * W_prime) + POOL_X_block_r;

    //================================//
    //       Ping FM Memory Port      //
    //================================//
    assign ctrl_Ping_FM_bank0_rd_en_o = (current_state_r == s_EXEC_CONV) ? (Ping_Pong_Select_w && (KERNEL_x_counter_r == 0 || KERNEL_x_counter_r == 1) && !read_WM_BM_stop_r) :
                                        (current_state_r == s_EXEC_POOL) ? (Ping_Pong_Select_w && pool_step_r <= 3'd3) : 1'b0;
    assign ctrl_Ping_FM_bank1_rd_en_o = ctrl_Ping_FM_bank0_rd_en_o;
    assign ctrl_Ping_FM_bank2_rd_en_o = ctrl_Ping_FM_bank0_rd_en_o;
    assign ctrl_Ping_FM_bank3_rd_en_o = ctrl_Ping_FM_bank0_rd_en_o;
    assign ctrl_Ping_FM_bank4_rd_en_o = ctrl_Ping_FM_bank0_rd_en_o;

    assign ctrl_Ping_FM_bank0_wr_en_o = (current_state_r == s_EXEC_CONV) ? (~Ping_Pong_Select_w && bank0_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 0 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (~Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 0 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Ping_FM_bank1_wr_en_o = (current_state_r == s_EXEC_CONV) ? (~Ping_Pong_Select_w && bank1_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 1 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (~Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 1 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Ping_FM_bank2_wr_en_o = (current_state_r == s_EXEC_CONV) ? (~Ping_Pong_Select_w && bank2_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 2 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (~Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 2 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Ping_FM_bank3_wr_en_o = (current_state_r == s_EXEC_CONV) ? (~Ping_Pong_Select_w && bank3_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 3 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (~Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 3 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Ping_FM_bank4_wr_en_o = (current_state_r == s_EXEC_CONV) ? (~Ping_Pong_Select_w && bank4_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 4 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (~Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 4 < OUTPUT_WIDTH_r)) : 1'b0;

    assign ctrl_Ping_FM_bank0_addr_o  = ctrl_Ping_FM_bank0_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Ping_FM_bank1_addr_o  = ctrl_Ping_FM_bank1_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Ping_FM_bank2_addr_o  = ctrl_Ping_FM_bank2_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Ping_FM_bank3_addr_o  = ctrl_Ping_FM_bank3_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Ping_FM_bank4_addr_o  = ctrl_Ping_FM_bank4_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);

    //================================//
    //       Pong FM Memory Port      //
    //================================//
    assign ctrl_Pong_FM_bank0_rd_en_o = (current_state_r == s_EXEC_CONV) ? (~Ping_Pong_Select_w && (KERNEL_x_counter_r == 0 || KERNEL_x_counter_r == 1) && !read_WM_BM_stop_r) :
                                        (current_state_r == s_EXEC_POOL) ? (~Ping_Pong_Select_w && pool_step_r <= 3'd3) : 1'b0;
    assign ctrl_Pong_FM_bank1_rd_en_o = ctrl_Pong_FM_bank0_rd_en_o;
    assign ctrl_Pong_FM_bank2_rd_en_o = ctrl_Pong_FM_bank0_rd_en_o;
    assign ctrl_Pong_FM_bank3_rd_en_o = ctrl_Pong_FM_bank0_rd_en_o;
    assign ctrl_Pong_FM_bank4_rd_en_o = ctrl_Pong_FM_bank0_rd_en_o;

    assign ctrl_Pong_FM_bank0_wr_en_o = (current_state_r == s_EXEC_CONV) ? (Ping_Pong_Select_w && bank0_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 0 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 0 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Pong_FM_bank1_wr_en_o = (current_state_r == s_EXEC_CONV) ? (Ping_Pong_Select_w && bank1_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 1 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 1 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Pong_FM_bank2_wr_en_o = (current_state_r == s_EXEC_CONV) ? (Ping_Pong_Select_w && bank2_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 2 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 2 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Pong_FM_bank3_wr_en_o = (current_state_r == s_EXEC_CONV) ? (Ping_Pong_Select_w && bank3_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 3 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 3 < OUTPUT_WIDTH_r)) : 1'b0;
    assign ctrl_Pong_FM_bank4_wr_en_o = (current_state_r == s_EXEC_CONV) ? (Ping_Pong_Select_w && bank4_mem_ofmap_valid_i && (OUTPUT_X_counter_d5_r + 4 < OUTPUT_WIDTH_r)) :
                                        (current_state_r == s_EXEC_POOL) ? (Ping_Pong_Select_w && pool_step_r == 3'd4 && (POOL_X_block_r * 5 + 4 < OUTPUT_WIDTH_r)) : 1'b0;

    assign ctrl_Pong_FM_bank0_addr_o  = ctrl_Pong_FM_bank0_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Pong_FM_bank1_addr_o  = ctrl_Pong_FM_bank1_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Pong_FM_bank2_addr_o  = ctrl_Pong_FM_bank2_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Pong_FM_bank3_addr_o  = ctrl_Pong_FM_bank3_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);
    assign ctrl_Pong_FM_bank4_addr_o  = ctrl_Pong_FM_bank4_wr_en_o ? (current_state_r == s_EXEC_CONV ? ofmap_write_addr_w : pool_write_addr_w) :
                                        (current_state_r == s_EXEC_CONV ? ifm_conv_addr_w : pool_read_addr_w);

    //================================//
    //         To PEA Control         //
    //================================//
    assign first_ifmap_int_w  = (current_state_r == s_EXEC_CONV) &&
                                (KERNEL_x_counter_r == 4'd0) &&
                                (KERNEL_y_counter_r == 4'd0) &&
                                (IN_CH_counter_r == 0) &&
                                !read_WM_BM_stop_r;

    assign last_ifmap_int_w   = (current_state_r == s_EXEC_CONV) &&
                                kernel_x_last_w &&
                                kernel_y_last_w &&
                                in_ch_last_w &&
                                !read_WM_BM_stop_r;

    assign execute_int_w      = (current_state_r == s_EXEC_CONV) && !read_WM_BM_stop_r;

    assign ifm_from_north_pre_w = (current_state_r == s_EXEC_CONV) &&
                                  (KERNEL_x_counter_r == 4'd0) &&
                                  !read_WM_BM_stop_r;

    assign line_buffer_load_pre_w = (current_state_r == s_EXEC_CONV) &&
                                    (KERNEL_x_counter_r == 4'd1) &&
                                    !read_WM_BM_stop_r;

    assign line_buffer_shift_pre_w = (current_state_r == s_EXEC_CONV) &&
                                     (KERNEL_x_counter_r >= 4'd2) &&
                                     !read_WM_BM_stop_r;

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            first_ifmap_r       <= 1'b0;
            last_ifmap_r        <= 1'b0;
            execute_r           <= 1'b0;
            ifm_from_north_r    <= 1'b0;
            line_buffer_load_r  <= 1'b0;
            line_buffer_shift_r <= 1'b0;
        end else begin
            first_ifmap_r       <= first_ifmap_int_w;
            last_ifmap_r        <= last_ifmap_int_w;
            execute_r           <= execute_int_w;

            // delay 1 cycle to match BRAM read latency
            ifm_from_north_r    <= ifm_from_north_pre_w;
            line_buffer_load_r  <= line_buffer_load_pre_w;
            line_buffer_shift_r <= line_buffer_shift_pre_w;
        end
    end

    assign first_ifmap_o        = first_ifmap_r;
    assign last_ifmap_o         = last_ifmap_r;
    assign execute_o            = execute_r;
    assign ifm_from_north_o     = ifm_from_north_r;
    assign line_buffer_load_o   = line_buffer_load_r;
    assign line_buffer_shift_o  = line_buffer_shift_r;

endmodule
