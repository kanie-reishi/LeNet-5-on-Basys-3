`timescale 1 ns / 1 ps

module tb_mac_pe;

    // Parameters
    localparam int DATA_DWIDTH = 16;
    localparam int FRAC_BITS   = 8;

    // Signals
    logic                             CLK;
    logic                             RST;
    logic                             first_ifmap_i;
    logic                             last_ifmap_i;
    logic                             execute_i;
    logic signed [DATA_DWIDTH-1:0]    north_ifmap_i;
    logic                             north_ifmap_valid_i;
    logic signed [DATA_DWIDTH-1:0]    east_ifmap_i;
    logic                             east_ifmap_valid_i;
    logic signed [DATA_DWIDTH-1:0]    south_ifmap_o;
    logic                             south_ifmap_valid_o;
    logic signed [DATA_DWIDTH-1:0]    west_ifmap_o;
    logic                             west_ifmap_valid_o;
    logic signed [DATA_DWIDTH-1:0]    mem_weight_i;
    logic                             mem_weight_valid_i;
    logic signed [DATA_DWIDTH-1:0]    mem_bias_i;
    logic                             mem_bias_valid_i;
    logic signed [DATA_DWIDTH-1:0]    mem_ofmap_o;
    logic                             mem_ofmap_valid_o;

    // Instantiate UUT
    mac_pe #(
        .DATA_DWIDTH(DATA_DWIDTH),
        .FRAC_BITS(FRAC_BITS)
    ) uut (
        .*
    );

    // Clock generator (50 MHz = 20ns period)
    always #10 CLK = ~CLK;

    // Monitor
    always @(posedge CLK) begin
        #2;
        $display("  [MON] T=%0d posedge CLK: ifmap_in=%d, weight=%d, mult_full=%d, mult_q=%d, acc_w=%d, acc_r=%d, ofmap=%d, valid_o=%b", 
                 $time, uut.ifmap_in_w, uut.mem_weight_i, uut.mult_full_w, uut.mult_q_w, uut.accumulator_w, uut.accumulator_r, mem_ofmap_o, mem_ofmap_valid_o);
    end

    initial begin
        // Initialize
        CLK = 0;
        RST = 0;
        first_ifmap_i = 0;
        last_ifmap_i = 0;
        execute_i = 0;
        north_ifmap_i = 0;
        north_ifmap_valid_i = 0;
        east_ifmap_i = 0;
        east_ifmap_valid_i = 0;
        mem_weight_i = 0;
        mem_weight_valid_i = 0;
        mem_bias_i = 0;
        mem_bias_valid_i = 0;

        #40;
        RST = 1;
        #20;

        // Synchronize with clock edge to avoid race conditions
        @(posedge CLK);
        #1;

        // Test Case 1: First iteration - load Bias + Multiply-Accumulate
        // Input: 1.0 (256 = 16'h0100), Weight: 2.0 (512 = 16'h0200), Bias: 3.0 (768 = 16'h0300)
        // Expected product = 2.0 (512 = 16'h0200)
        // Expected accumulator_w = 3.0 + 2.0 = 5.0 (1280 = 16'h0500)
        $display("[TEST] Case 1: Loading bias and performing first product accumulation");
        execute_i = 1;
        north_ifmap_valid_i = 1;
        north_ifmap_i = 16'h0100;
        mem_weight_valid_i = 1;
        mem_weight_i = 16'h0200;
        mem_bias_valid_i = 1;
        mem_bias_i = 16'h0300;
        
        @(posedge CLK);
        #1;

        // Test Case 2: Subsequent iteration - accumulate next product and assert last_ifmap_i
        // Input: 0.5 (128 = 16'h0080), Weight: 4.0 (1024 = 16'h0400), Bias valid = 0
        // Expected product = 2.0 (512 = 16'h0200)
        // Expected accumulator_w = 5.0 (previous) + 2.0 = 7.0 (1792 = 16'h0700)
        $display("[TEST] Case 2: Accumulating next product term and asserting last_ifmap_i");
        mem_bias_valid_i = 0;
        north_ifmap_i = 16'h0080;
        mem_weight_i = 16'h0400;
        last_ifmap_i = 1;
        
        @(posedge CLK);
        #1;

        // Test Case 3: Verify output map latched on previous clock edge
        $display("[TEST] Case 3: Verifying output map latch");
        last_ifmap_i = 0;
        execute_i = 0;
        north_ifmap_valid_i = 0;
        mem_weight_valid_i = 0;
        
        if (mem_ofmap_valid_o && mem_ofmap_o == 16'sd1792) begin
            $display("  [PASS] Output Map verification passed. mem_ofmap_o = %d (Expected: 1792)", mem_ofmap_o);
        end else begin
            $display("  [FAIL] Output Map verification failed. valid = %b, value = %d", mem_ofmap_valid_o, mem_ofmap_o);
        end
        
        @(posedge CLK);
        #1;

        // Test Case 4: Positive Overflow Saturation
        // Bias: 120.0 (30720), Input: 10.0 (2560), Weight: 2.0 (512)
        // Accumulator becomes: 120 + 20 = 140.0 (35840), exceeding 32767 -> Should saturate to 32767 (16'h7FFF)
        $display("[TEST] Case 4: Verifying positive overflow saturation");
        execute_i = 1;
        north_ifmap_valid_i = 1;
        north_ifmap_i = 16'sd2560; // 10.0
        mem_weight_valid_i = 1;
        mem_weight_i = 16'sd512; // 2.0
        mem_bias_valid_i = 1;
        mem_bias_i = 16'sd30720; // 120.0
        last_ifmap_i = 1;
        
        @(posedge CLK);
        #1;
        
        // Stop computation, read latched output on next cycle
        last_ifmap_i = 0;
        execute_i = 0;
        north_ifmap_valid_i = 0;
        mem_weight_valid_i = 0;
        mem_bias_valid_i = 0;
        
        if (mem_ofmap_valid_o && mem_ofmap_o == 16'sh7FFF) begin
            $display("  [PASS] Positive saturation passed. mem_ofmap_o = 16'h%h", mem_ofmap_o);
        end else begin
            $display("  [FAIL] Positive saturation failed. mem_ofmap_o = 16'h%h", mem_ofmap_o);
        end
        
        @(posedge CLK);
        #1;
        $display("[INFO] tb_mac_pe complete.");
        $finish;
    end

endmodule
