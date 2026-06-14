`timescale 1 ns / 1 ps

module tb_pea_buffer;

    // Parameters
    localparam int DWIDTH = 16;
    localparam int FRAC_BITS = 8;
    localparam int NBANKS = 5;

    // Common signals
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
    logic [DWIDTH-1:0]        pea_east_ifmap_i;
    logic                     pea_east_ifmap_valid_i;

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

    // Capture registers to verify transient outputs
    logic [DWIDTH-1:0]        captured_bank0_ofmap;
    logic                     captured_bank0_valid;
    logic [DWIDTH-1:0]        captured_bank1_ofmap;
    logic                     captured_bank1_valid;

    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            captured_bank0_ofmap <= 0;
            captured_bank0_valid <= 0;
            captured_bank1_ofmap <= 0;
            captured_bank1_valid <= 0;
        end else begin
            if (bank0_mem_ofmap_valid_o) begin
                captured_bank0_ofmap <= bank0_mem_ofmap_o;
                captured_bank0_valid <= 1'b1;
            end
            if (bank1_mem_ofmap_valid_o) begin
                captured_bank1_ofmap <= bank1_mem_ofmap_o;
                captured_bank1_valid <= 1'b1;
            end
        end
    end

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
        .bank4_mem_ofmap_valid_o(bank4_mem_ofmap_valid_o)
    );

    // Clock Generation
    always #10 CLK = ~CLK; // 50 MHz

    logic error_flag;

    initial begin
        CLK = 0;
        RST = 1;
        error_flag = 0;

        // Initialize Line Buffer inputs
        lb_load_i = 0;
        lb_shift_en_i = 0;
        ifm_bank0_i = 0;
        ifm_bank1_i = 0;
        ifm_bank2_i = 0;
        ifm_bank3_i = 0;
        ifm_bank4_i = 0;
        ifm_bank0_valid_i = 0;
        ifm_bank1_valid_i = 0;
        ifm_bank2_valid_i = 0;
        ifm_bank3_valid_i = 0;
        ifm_bank4_valid_i = 0;

        // Initialize PEA inputs
        pea_first_ifmap_i = 0;
        pea_last_ifmap_i = 0;
        pea_execute_i = 0;
        pea_ifm_from_north_i = 0;
        pea_east_ifmap_i = 0;
        pea_east_ifmap_valid_i = 0;

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

        // Assert reset
        #5;
        RST = 0;
        #20;
        RST = 1;
        #20;

        //================================================================//
        // TEST CASE 1: Line Buffer Parallel Load & Shift Verification
        //================================================================//
        $display("[TEST] Case 1: Line Buffer load and shift operations");
        @(posedge CLK);
        #1;
        lb_load_i = 1;
        ifm_bank0_i = 16'h0000; ifm_bank0_valid_i = 1;
        ifm_bank1_i = 16'h0011; ifm_bank1_valid_i = 1;
        ifm_bank2_i = 16'h0022; ifm_bank2_valid_i = 1;
        ifm_bank3_i = 16'h0033; ifm_bank3_valid_i = 1;
        ifm_bank4_i = 16'h0044; ifm_bank4_valid_i = 1;

        @(posedge CLK);
        #1;
        lb_load_i = 0;
        ifm_bank0_valid_i = 0;
        ifm_bank1_valid_i = 0;
        ifm_bank2_valid_i = 0;
        ifm_bank3_valid_i = 0;
        ifm_bank4_valid_i = 0;

        // Assert output value BEFORE first clock edge of the shift phase
        lb_shift_en_i = 1;
        #1;
        if (east_ifmap_w !== 16'h0011 || !east_ifmap_valid_w) begin
            $display("  [FAIL] Shift index 0 failed. expected=0011, actual=%h, valid=%b", east_ifmap_w, east_ifmap_valid_w);
            error_flag = 1;
        end

        // Edge 1 shifts to next element (16'h0022)
        @(posedge CLK);
        #1;
        if (east_ifmap_w !== 16'h0022 || !east_ifmap_valid_w) begin
            $display("  [FAIL] Shift index 1 failed. expected=0022, actual=%h, valid=%b", east_ifmap_w, east_ifmap_valid_w);
            error_flag = 1;
        end

        // Edge 2 shifts to next element (16'h0033)
        @(posedge CLK);
        #1;
        if (east_ifmap_w !== 16'h0033 || !east_ifmap_valid_w) begin
            $display("  [FAIL] Shift index 2 failed. expected=0033, actual=%h, valid=%b", east_ifmap_w, east_ifmap_valid_w);
            error_flag = 1;
        end

        // Edge 3 shifts to next element (16'h0044)
        @(posedge CLK);
        #1;
        if (east_ifmap_w !== 16'h0044 || !east_ifmap_valid_w) begin
            $display("  [FAIL] Shift index 3 failed. expected=0044, actual=%h, valid=%b", east_ifmap_w, east_ifmap_valid_w);
            error_flag = 1;
        end

        // Edge 4 shifts to empty
        @(posedge CLK);
        #1;
        if (east_ifmap_w !== 16'h0000 || east_ifmap_valid_w) begin
            $display("  [FAIL] Shift index 4 (empty) failed. actual=%h, valid=%b", east_ifmap_w, east_ifmap_valid_w);
            error_flag = 1;
        end

        lb_shift_en_i = 0;
        if (!error_flag) $display("  [PASS] Line Buffer load and shift operations verified!");

        #50;

        //================================================================//
        // TEST CASE 2: Mock Convolution Operation on PEA
        //================================================================//
        $display("[TEST] Case 2: Mock Convolution computation on PEA");
        
        // Cycle 1: Feed input to Row 0. Assert execute and first_ifmap.
        // Load Row 0 Weight & Bias.
        @(posedge CLK);
        #1;
        pea_execute_i = 1;
        pea_first_ifmap_i = 1;
        pea_ifm_from_north_i = 1;

        // North input values: 0.5, 0.25, 0.125, 0.0625, 0.03125
        ifm_bank0_i = 16'h0080; ifm_bank0_valid_i = 1;
        ifm_bank1_i = 16'h0040; ifm_bank1_valid_i = 1;
        ifm_bank2_i = 16'h0020; ifm_bank2_valid_i = 1;
        ifm_bank3_i = 16'h0010; ifm_bank3_valid_i = 1;
        ifm_bank4_i = 16'h0008; ifm_bank4_valid_i = 1;

        // Row 0 weight and bias valids
        row0_mem_weight_i = 16'h0100; row0_mem_weight_valid_i = 1; // 1.0
        row0_mem_bias_i = 16'h0019; row0_mem_bias_valid_i = 1; // 0.1

        // Cycle 2: Deassert first_ifmap. Input reaches Row 1.
        // Load Row 1 Weight & Bias.
        @(posedge CLK);
        #1;
        pea_first_ifmap_i = 0;
        row0_mem_weight_valid_i = 0; row0_mem_bias_valid_i = 0;

        row1_mem_weight_i = 16'h0200; row1_mem_weight_valid_i = 1; // 2.0
        row1_mem_bias_i = 16'h0033; row1_mem_bias_valid_i = 1; // 0.2

        // Cycle 3: Input reaches Row 2.
        // Load Row 2 Weight & Bias.
        @(posedge CLK);
        #1;
        row1_mem_weight_valid_i = 0; row1_mem_bias_valid_i = 0;

        row2_mem_weight_i = 16'h0300; row2_mem_weight_valid_i = 1; // 3.0
        row2_mem_bias_i = 16'h004D; row2_mem_bias_valid_i = 1; // 0.3

        // Cycle 4: Input reaches Row 3.
        // Load Row 3 Weight & Bias.
        @(posedge CLK);
        #1;
        row2_mem_weight_valid_i = 0; row2_mem_bias_valid_i = 0;

        row3_mem_weight_i = 16'h0400; row3_mem_weight_valid_i = 1; // 4.0
        row3_mem_bias_i = 16'h0066; row3_mem_bias_valid_i = 1; // 0.4

        // Cycle 5: Input reaches Row 4.
        // Load Row 4 Weight & Bias.
        @(posedge CLK);
        #1;
        row3_mem_weight_valid_i = 0; row3_mem_bias_valid_i = 0;

        row4_mem_weight_i = 16'h0500; row4_mem_weight_valid_i = 1; // 5.0
        row4_mem_bias_i = 16'h0080; row4_mem_bias_valid_i = 1; // 0.5

        // Also assert last_ifmap_i to trigger computation termination for Row 0
        pea_last_ifmap_i = 1;

        // Cycle 6: Deassert last_ifmap. Inputs no longer fed to North.
        @(posedge CLK);
        #1;
        row4_mem_weight_valid_i = 0; row4_mem_bias_valid_i = 0;
        pea_last_ifmap_i = 0;
        pea_ifm_from_north_i = 0;
        ifm_bank0_valid_i = 0;
        ifm_bank1_valid_i = 0;
        ifm_bank2_valid_i = 0;
        ifm_bank3_valid_i = 0;
        ifm_bank4_valid_i = 0;

        // Wait a few cycles for all rows to finish their last_ifmap_i execution
        #150;

        // Let's print out the captured outputs.
        // Row 0 Column 0 (PE0):
        //   Weight = 1.0, Input = 0.5, Bias = 0.1
        //   Expected Output = 1.0 * 0.5 + 0.1 = 0.6 = 153 (0x0099)
        // Row 1 Column 1 (PE6):
        //   Weight = 2.0, Input = 0.25 (propagated down to Row 1), Bias = 0.2
        //   Expected Output = 2.0 * 0.25 + 0.2 = 0.7 = 179 (0x00B3)
        $display("  Captured outputs: bank0=%h (valid=%b), bank1=%h (valid=%b)",
                 captured_bank0_ofmap, captured_bank0_valid,
                 captured_bank1_ofmap, captured_bank1_valid);

        if (captured_bank0_ofmap !== 16'h0300 || !captured_bank0_valid) begin
            $display("  [FAIL] PEA bank 0 output failed. expected=0300, actual=%h", captured_bank0_ofmap);
            error_flag = 1;
        end
        if (captured_bank1_ofmap !== 16'h01c0 || !captured_bank1_valid) begin
            $display("  [FAIL] PEA bank 1 output failed. expected=01c0, actual=%h", captured_bank1_ofmap);
            error_flag = 1;
        end

        pea_execute_i = 0;
        #50;

        // Final Report
        if (error_flag) begin
            $display("\n==========================================");
            $display("[RESULT] tb_pea_buffer: [FAIL]");
            $display("==========================================\n");
        end else begin
            $display("\n==========================================");
            $display("[RESULT] tb_pea_buffer: [PASS]");
            $display("==========================================\n");
        end

        $finish;
    end

endmodule
