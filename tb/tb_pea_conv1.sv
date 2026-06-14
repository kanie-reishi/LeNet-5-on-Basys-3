`timescale 1 ns / 1 ps

module tb_pea_conv1;

    // Parameters
    localparam int DWIDTH = 16;
    localparam int FRAC_BITS = 8;
    localparam int NBANKS = 5;

    // Clock and Reset
    logic CLK;
    logic RST;

    //================================================================//
    // Line Buffer Signals
    //================================================================//
    logic                     lb_load_i;
    logic                     lb_shift_en_i;

    logic [DWIDTH-1:0]        ifm_bank0_i;
    logic [DWIDTH-1:0]        ifm_bank1_i;
    logic [DWIDTH-1:0]        ifm_bank2_i;
    logic [DWIDTH-1:0]        ifm_bank3_i;
    logic [DWIDTH-1:0]        ifm_bank4_i;

    logic                     ifm_bank0_valid_i;
    logic                     ifm_bank1_valid_i;
    logic                     ifm_bank2_valid_i;
    logic                     ifm_bank3_valid_i;
    logic                     ifm_bank4_valid_i;

    logic [DWIDTH-1:0]        east_ifmap_w;
    logic                     east_ifmap_valid_w;

    //================================================================//
    // PEA Signals
    //================================================================//
    logic                     pea_first_ifmap_i;
    logic                     pea_last_ifmap_i;
    logic                     pea_execute_i;
    logic                     pea_ifm_from_north_i;

    // External East Input
    wire [DWIDTH-1:0]         pea_east_ifmap_i;
    wire                      pea_east_ifmap_valid_i;

    // Row Weights/Biases
    logic [DWIDTH-1:0]        row0_mem_weight_i;
    logic                     row0_mem_weight_valid_i;
    logic [DWIDTH-1:0]        row1_mem_weight_i;
    logic                     row1_mem_weight_valid_i;
    logic [DWIDTH-1:0]        row2_mem_weight_i;
    logic                     row2_mem_weight_valid_i;
    logic [DWIDTH-1:0]        row3_mem_weight_i;
    logic                     row3_mem_weight_valid_i;
    logic [DWIDTH-1:0]        row4_mem_weight_i;
    logic                     row4_mem_weight_valid_i;

    logic [DWIDTH-1:0]        row0_mem_bias_i;
    logic                     row0_mem_bias_valid_i;
    logic [DWIDTH-1:0]        row1_mem_bias_i;
    logic                     row1_mem_bias_valid_i;
    logic [DWIDTH-1:0]        row2_mem_bias_i;
    logic                     row2_mem_bias_valid_i;
    logic [DWIDTH-1:0]        row3_mem_bias_i;
    logic                     row3_mem_bias_valid_i;
    logic [DWIDTH-1:0]        row4_mem_bias_i;
    logic                     row4_mem_bias_valid_i;

    // OFMAP Output
    logic [DWIDTH-1:0]        bank0_mem_ofmap_o;
    logic                     bank0_mem_ofmap_valid_o;
    logic [DWIDTH-1:0]        bank1_mem_ofmap_o;
    logic                     bank1_mem_ofmap_valid_o;
    logic [DWIDTH-1:0]        bank2_mem_ofmap_o;
    logic                     bank2_mem_ofmap_valid_o;
    logic [DWIDTH-1:0]        bank3_mem_ofmap_o;
    logic                     bank3_mem_ofmap_valid_o;
    logic [DWIDTH-1:0]        bank4_mem_ofmap_o;
    logic                     bank4_mem_ofmap_valid_o;

    //================================================================//
    // Instantiations
    //================================================================//
    line_buffer #(
        .DWIDTH(DWIDTH)
    ) u_line_buffer (
        .CLK(CLK),
        .RST(RST),
        .load_i(lb_load_i),
        .shift_en_i(lb_shift_en_i),
        .ifm_bank0_i(ifm_bank0_i),
        .ifm_bank1_i(ifm_bank1_i),
        .ifm_bank2_i(ifm_bank2_i),
        .ifm_bank3_i(ifm_bank3_i),
        .ifm_bank4_i(ifm_bank4_i),
        .ifm_bank0_valid_i(ifm_bank0_valid_i),
        .ifm_bank1_valid_i(ifm_bank1_valid_i),
        .ifm_bank2_valid_i(ifm_bank2_valid_i),
        .ifm_bank3_valid_i(ifm_bank3_valid_i),
        .ifm_bank4_valid_i(ifm_bank4_valid_i),
        .east_ifmap_o(east_ifmap_w),
        .east_ifmap_valid_o(east_ifmap_valid_w)
    );

    pea #(
        .DATA_DWIDTH(DWIDTH),
        .FRAC_BITS(FRAC_BITS)
    ) u_pea (
        .CLK(CLK),
        .RST(RST),
        .first_ifmap_i(pea_first_ifmap_i),
        .last_ifmap_i(pea_last_ifmap_i),
        .execute_i(pea_execute_i),
        .ifm_from_north_i(pea_ifm_from_north_i),
        .bank0_mem_ifmap_i(ifm_bank0_i),
        .bank0_mem_ifmap_valid_i(ifm_bank0_valid_i),
        .bank1_mem_ifmap_i(ifm_bank1_i),
        .bank1_mem_ifmap_valid_i(ifm_bank1_valid_i),
        .bank2_mem_ifmap_i(ifm_bank2_i),
        .bank2_mem_ifmap_valid_i(ifm_bank2_valid_i),
        .bank3_mem_ifmap_i(ifm_bank3_i),
        .bank3_mem_ifmap_valid_i(ifm_bank3_valid_i),
        .bank4_mem_ifmap_i(ifm_bank4_i),
        .bank4_mem_ifmap_valid_i(ifm_bank4_valid_i),
        .east_ifmap_i(pea_east_ifmap_i),
        .east_ifmap_valid_i(pea_east_ifmap_valid_i),
        .row0_mem_weight_i(row0_mem_weight_i),
        .row0_mem_weight_valid_i(row0_mem_weight_valid_i),
        .row1_mem_weight_i(row1_mem_weight_i),
        .row1_mem_weight_valid_i(row1_mem_weight_valid_i),
        .row2_mem_weight_i(row2_mem_weight_i),
        .row2_mem_weight_valid_i(row2_mem_weight_valid_i),
        .row3_mem_weight_i(row3_mem_weight_i),
        .row3_mem_weight_valid_i(row3_mem_weight_valid_i),
        .row4_mem_weight_i(row4_mem_weight_i),
        .row4_mem_weight_valid_i(row4_mem_weight_valid_i),
        .row0_mem_bias_i(row0_mem_bias_i),
        .row0_mem_bias_valid_i(row0_mem_bias_valid_i),
        .row1_mem_bias_i(row1_mem_bias_i),
        .row1_mem_bias_valid_i(row1_mem_bias_valid_i),
        .row2_mem_bias_i(row2_mem_bias_i),
        .row2_mem_bias_valid_i(row2_mem_bias_valid_i),
        .row3_mem_bias_i(row3_mem_bias_i),
        .row3_mem_bias_valid_i(row3_mem_bias_valid_i),
        .row4_mem_bias_i(row4_mem_bias_i),
        .row4_mem_bias_valid_i(row4_mem_bias_valid_i),
        .bank0_mem_ofmap_o(bank0_mem_ofmap_o),
        .bank0_mem_ofmap_valid_o(bank0_mem_ofmap_valid_o),
        .bank1_mem_ofmap_o(bank1_mem_ofmap_o),
        .bank1_mem_ofmap_valid_o(bank1_mem_ofmap_valid_o),
        .bank2_mem_ofmap_o(bank2_mem_ofmap_o),
        .bank2_mem_ofmap_valid_o(bank2_mem_ofmap_valid_o),
        .bank3_mem_ofmap_o(bank3_mem_ofmap_o),
        .bank3_mem_ofmap_valid_o(bank3_mem_ofmap_valid_o),
        .bank4_mem_ofmap_o(bank4_mem_ofmap_o),
        .bank4_mem_ofmap_valid_o(bank4_mem_ofmap_valid_o),
        .shift_i(4'd12)
    );

    // Clock Generation
    always #10 CLK = ~CLK; // 50 MHz

    // RAM Memories loaded from Hex files
    logic [127:0] ifm_ram [0:1023];
    logic [127:0] weight_ram [0:399];
    logic [31:0]  bias_ram [0:15];
    logic [127:0] expected_ofm_ram [0:783];

    // Simulation Execution Variables
    integer t_counter;
    integer out_y;
    integer out_x_base;

    assign pea_east_ifmap_i = (t_counter < 25 && (t_counter % 5 == 1)) ? ifm_bank0_i :
                              (t_counter < 25 && (t_counter % 5 >= 2)) ? east_ifmap_w :
                              16'h0000;

    assign pea_east_ifmap_valid_i = (t_counter < 25 && (t_counter % 5 == 1)) ? ifm_bank0_valid_i :
                                    (t_counter < 25 && (t_counter % 5 >= 2)) ? east_ifmap_valid_w :
                                    1'b0;
    integer pass;
    integer error_count;
    integer match_count;

    // Output capture logic
    always @(negedge CLK) begin: output_capture
        integer col_idx;
        integer actual_x;
        logic signed [15:0] raw_val;
        logic signed [31:0] shifted_val;
        logic [7:0] final_val;
        integer golden_line;
        logic [7:0] expected_val;
        integer check_row;

        if (t_counter >= 25 && t_counter <= 29) begin
            check_row = t_counter - 25;
            for (col_idx = 0; col_idx < 5; col_idx = col_idx + 1) begin
                if (pass == 0 || check_row == 0) begin
                    actual_x = out_x_base + col_idx;
                    if (actual_x < 28) begin
                        case (col_idx)
                            0: raw_val = bank0_mem_ofmap_o;
                            1: raw_val = bank1_mem_ofmap_o;
                            2: raw_val = bank2_mem_ofmap_o;
                            3: raw_val = bank3_mem_ofmap_o;
                            default: raw_val = bank4_mem_ofmap_o;
                        endcase
                        
                        // Shift is already performed inside the PE
                        shifted_val = $signed({{16{raw_val[15]}}, raw_val});
                        
                        // ReLU & Clamp
                        if (shifted_val < 0) begin
                            final_val = 8'd0;
                        end else if (shifted_val > 127) begin
                            final_val = 8'd127;
                        end else begin
                            final_val = shifted_val[7:0];
                        end
                        
                        // Get Golden expected output
                        golden_line = out_y * 28 + actual_x;
                        expected_val = expected_ofm_ram[golden_line][((pass == 0) ? check_row : 5)*8 +: 8];
                        
                        if (final_val !== expected_val) begin
                            $display("  [FAIL] Mismatch at Pixel(%d,%d) Ch:%d | Expected:%h, Got:%h (raw:%h, shifted:%d) at t:%d", 
                                     out_y, actual_x, (pass == 0) ? check_row : 5, expected_val, final_val, raw_val, shifted_val, t_counter);
                            error_count = error_count + 1;
                        end else begin
                            match_count = match_count + 1;
                        end
                    end
                end
            end
        end
    end

    initial begin: simulation_driver
        integer ky;
        integer kx;
        integer col;
        integer loop_actual_x;
        logic [15:0] pix_val;
        integer row;
        integer local_t;
        integer oc_idx;
        integer w_ky;
        integer w_kx;
        logic signed [7:0] wt_val;
        logic signed [31:0] bs_val;

        CLK = 0;
        RST = 1;
        error_count = 0;
        match_count = 0;
        t_counter = 0;

        // Load Hex Files
        $readmemh("hex_conv1/ifm.hex", ifm_ram);
        $readmemh("hex_conv1/weight.hex", weight_ram);
        $readmemh("hex_conv1/bias.hex", bias_ram);
        $readmemh("hex_conv1/expected_ofm.hex", expected_ofm_ram);

        $display("[INFO] Hex memories loaded successfully.");

        // Reset Sequence
        #5;
        RST = 0;
        #20;
        RST = 1;
        #20;

        $display("[TEST] Starting Conv1 full feature map computation on 5x5 PEA");

        // Loop over the 6 output channels (Pass 0: channels 0..4, Pass 1: channel 5)
        for (pass = 0; pass < 2; pass = pass + 1) begin
            $display("[PASS %0d] Processing channels...", pass);
            
            // Loop over output height coordinates (0 to 27)
            for (out_y = 0; out_y < 28; out_y = out_y + 1) begin
                
                // Loop over output width blocks (0 to 27, in steps of 5)
                for (out_x_base = 0; out_x_base < 28; out_x_base = out_x_base + 5) begin
                    
                    // Reset inputs
                    lb_load_i = 0;
                    lb_shift_en_i = 0;
                    ifm_bank0_i = 0; ifm_bank1_i = 0; ifm_bank2_i = 0; ifm_bank3_i = 0; ifm_bank4_i = 0;
                    ifm_bank0_valid_i = 0; ifm_bank1_valid_i = 0; ifm_bank2_valid_i = 0; ifm_bank3_valid_i = 0; ifm_bank4_valid_i = 0;
                    
                    pea_first_ifmap_i = 0;
                    pea_last_ifmap_i = 0;
                    pea_execute_i = 0;
                    pea_ifm_from_north_i = 0;
                    
                    row0_mem_weight_i = 0; row0_mem_weight_valid_i = 0;
                    row1_mem_weight_i = 0; row1_mem_weight_valid_i = 0;
                    row2_mem_weight_i = 0; row2_mem_weight_valid_i = 0;
                    row3_mem_weight_i = 0; row3_mem_weight_valid_i = 0;
                    row4_mem_weight_i = 0; row4_mem_weight_valid_i = 0;
                    
                    row0_mem_bias_i = 0; row0_mem_bias_valid_i = 0;
                    row1_mem_bias_i = 0; row1_mem_bias_valid_i = 0;
                    row2_mem_bias_i = 0; row2_mem_bias_valid_i = 0;
                    row3_mem_bias_i = 0; row3_mem_bias_valid_i = 0;
                    row4_mem_bias_i = 0; row4_mem_bias_valid_i = 0;

                    // Execute 25 MAC cycles for the 5x5 kernel + 10 propagation cycles
                    t_counter = 0;
                    repeat (35) begin
                        #1;

                        // PE array execution remains active up to cycle 28 (t_counter < 29)
                        // to allow final outputs of delayed rows to compute and propagate.
                        pea_execute_i = (t_counter < 29);
                        pea_first_ifmap_i = (t_counter == 0);
                        pea_last_ifmap_i = (t_counter == 24);

                        // 1. Inputs feeding to Row 0 (and registers loading for other columns)
                        // We only feed the 25 active input elements per tile.
                        if (t_counter < 25) begin
                            ky = t_counter / 5;
                            kx = t_counter % 5;
                            
                            if (kx == 0) begin
                                pea_ifm_from_north_i = 1;
                                for (col = 0; col < 5; col = col + 1) begin
                                    loop_actual_x = out_x_base + col;
                                    pix_val = 0;
                                    if (loop_actual_x < 32 && out_y + ky < 32) begin
                                        pix_val = {8'h00, ifm_ram[(out_y + ky)*32 + loop_actual_x][7:0]};
                                    end
                                    case (col)
                                        0: begin ifm_bank0_i = pix_val; ifm_bank0_valid_i = 1; end
                                        1: begin ifm_bank1_i = pix_val; ifm_bank1_valid_i = 1; end
                                        2: begin ifm_bank2_i = pix_val; ifm_bank2_valid_i = 1; end
                                        3: begin ifm_bank3_i = pix_val; ifm_bank3_valid_i = 1; end
                                        default: begin ifm_bank4_i = pix_val; ifm_bank4_valid_i = 1; end
                                    endcase
                                end
                                lb_load_i = 0;
                                lb_shift_en_i = 0;
                            end else if (kx == 1) begin
                                pea_ifm_from_north_i = 0;
                                for (col = 0; col < 5; col = col + 1) begin
                                    loop_actual_x = out_x_base + 5 + col;
                                    pix_val = 0;
                                    if (loop_actual_x < 32 && out_y + ky < 32) begin
                                        pix_val = {8'h00, ifm_ram[(out_y + ky)*32 + loop_actual_x][7:0]};
                                    end
                                    case (col)
                                        0: begin ifm_bank0_i = pix_val; ifm_bank0_valid_i = 1; end
                                        1: begin ifm_bank1_i = pix_val; ifm_bank1_valid_i = 1; end
                                        2: begin ifm_bank2_i = pix_val; ifm_bank2_valid_i = 1; end
                                        3: begin ifm_bank3_i = pix_val; ifm_bank3_valid_i = 1; end
                                        default: begin ifm_bank4_i = pix_val; ifm_bank4_valid_i = 1; end
                                    endcase
                                end
                                lb_load_i = 1;
                                lb_shift_en_i = 0;
                            end else begin
                                pea_ifm_from_north_i = 0;
                                ifm_bank0_valid_i = 0; ifm_bank1_valid_i = 0; ifm_bank2_valid_i = 0; ifm_bank3_valid_i = 0; ifm_bank4_valid_i = 0;
                                lb_load_i = 0;
                                lb_shift_en_i = 1;
                            end
                        end else begin
                            pea_ifm_from_north_i = 0;
                            ifm_bank0_valid_i = 0; ifm_bank1_valid_i = 0; ifm_bank2_valid_i = 0; ifm_bank3_valid_i = 0; ifm_bank4_valid_i = 0;
                            lb_load_i = 0;
                            lb_shift_en_i = 0;
                        end

                        // 2. Weights and Biases feeding with systolic pipeline delays
                        for (row = 0; row < 5; row = row + 1) begin
                            local_t = t_counter - row;
                            oc_idx = (pass == 0) ? row : 5;

                            if (local_t >= 0 && local_t < 25 && oc_idx < 6) begin
                                w_ky = local_t / 5;
                                w_kx = local_t % 5;
                                wt_val = weight_ram[(w_ky*5 + w_kx)*16][oc_idx*8 +: 8];
                                bs_val = bias_ram[oc_idx];
                                
                                case (row)
                                    0: begin
                                        row0_mem_weight_i = {wt_val, 8'h00};
                                        row0_mem_weight_valid_i = 1;
                                        row0_mem_bias_i = bs_val[15:0];
                                        row0_mem_bias_valid_i = (local_t == 0);
                                    end
                                    1: begin
                                        row1_mem_weight_i = {wt_val, 8'h00};
                                        row1_mem_weight_valid_i = 1;
                                        row1_mem_bias_i = bs_val[15:0];
                                        row1_mem_bias_valid_i = (local_t == 0);
                                    end
                                    2: begin
                                        row2_mem_weight_i = {wt_val, 8'h00};
                                        row2_mem_weight_valid_i = 1;
                                        row2_mem_bias_i = bs_val[15:0];
                                        row2_mem_bias_valid_i = (local_t == 0);
                                    end
                                    3: begin
                                        row3_mem_weight_i = {wt_val, 8'h00};
                                        row3_mem_weight_valid_i = 1;
                                        row3_mem_bias_i = bs_val[15:0];
                                        row3_mem_bias_valid_i = (local_t == 0);
                                    end
                                    default: begin
                                        row4_mem_weight_i = {wt_val, 8'h00};
                                        row4_mem_weight_valid_i = 1;
                                        row4_mem_bias_i = bs_val[15:0];
                                        row4_mem_bias_valid_i = (local_t == 0);
                                    end
                                endcase
                            end else begin
                                case (row)
                                    0: begin row0_mem_weight_valid_i = 0; row0_mem_bias_valid_i = 0; end
                                    1: begin row1_mem_weight_valid_i = 0; row1_mem_bias_valid_i = 0; end
                                    2: begin row2_mem_weight_valid_i = 0; row2_mem_bias_valid_i = 0; end
                                    3: begin row3_mem_weight_valid_i = 0; row3_mem_bias_valid_i = 0; end
                                    default: begin row4_mem_weight_valid_i = 0; row4_mem_bias_valid_i = 0; end
                                endcase
                            end
                        end
                        @(posedge CLK);
                        t_counter = t_counter + 1;
                    end
                end
            end
        end

        #50;

        // Final Verification Output
        if (error_count > 0) begin
            $display("\n==================================================");
            $display("[RESULT] tb_pea_conv1: [FAIL]");
            $display("  Mismatches: %d", error_count);
            $display("  Matches   : %d", match_count);
            $display("==================================================\n");
        end else begin
            $display("\n==================================================");
            $display("[RESULT] tb_pea_conv1: [PASS]");
            $display("  All %d output values matched golden predictions!", match_count);
            $display("==================================================\n");
        end

        $finish;
    end

    always @(posedge CLK) begin
        if (t_counter >= 0 && t_counter <= 35) begin
            $display("[TRACE_ROW0] t = %0d | valids = %b %b %b %b %b | ifm_valids = %b %b %b %b %b | outs = %h %h %h %h %h",
                     t_counter,
                     u_pea.gen_row[0].gen_col[0].u_pe.mem_ofmap_valid_o,
                     u_pea.gen_row[0].gen_col[1].u_pe.mem_ofmap_valid_o,
                     u_pea.gen_row[0].gen_col[2].u_pe.mem_ofmap_valid_o,
                     u_pea.gen_row[0].gen_col[3].u_pe.mem_ofmap_valid_o,
                     u_pea.gen_row[0].gen_col[4].u_pe.mem_ofmap_valid_o,
                     u_pea.gen_row[0].gen_col[0].u_pe.ifmap_valid_w,
                     u_pea.gen_row[0].gen_col[1].u_pe.ifmap_valid_w,
                     u_pea.gen_row[0].gen_col[2].u_pe.ifmap_valid_w,
                     u_pea.gen_row[0].gen_col[3].u_pe.ifmap_valid_w,
                     u_pea.gen_row[0].gen_col[4].u_pe.ifmap_valid_w,
                     u_pea.gen_row[0].gen_col[0].u_pe.mem_ofmap_o,
                     u_pea.gen_row[0].gen_col[1].u_pe.mem_ofmap_o,
                     u_pea.gen_row[0].gen_col[2].u_pe.mem_ofmap_o,
                     u_pea.gen_row[0].gen_col[3].u_pe.mem_ofmap_o,
                     u_pea.gen_row[0].gen_col[4].u_pe.mem_ofmap_o);
        end
    end

    // Psum logging for all 25 PEs in the array
    generate
        genvar r, c;
        for (r = 0; r < 5; r = r + 1) begin: gen_log_row
            for (c = 0; c < 5; c = c + 1) begin: gen_log_col
                integer step_cnt;
                always @(posedge CLK) begin
                    if (!RST) begin
                        step_cnt = 0;
                    end else if (u_pea.gen_row[r].gen_col[c].u_pe.execute_i) begin
                        if (u_pea.gen_row[r].gen_col[c].u_pe.first_ifmap_i && u_pea.gen_row[r].gen_col[c].u_pe.ifmap_valid_w) begin
                            step_cnt = 0;
                        end
                        if (u_pea.gen_row[r].gen_col[c].u_pe.ifmap_valid_w) begin
                            if (step_cnt < 25) begin
                                $display("[PSUM] pass=%0d y=%0d x_base=%0d row=%0d col=%0d step=%0d | acc=%d", 
                                         pass, out_y, out_x_base, r, c, step_cnt, 
                                         $signed(u_pea.gen_row[r].gen_col[c].u_pe.accumulator_w));
                            end
                            step_cnt = step_cnt + 1;
                        end
                    end
                end
            end
        end
    endgenerate

endmodule
