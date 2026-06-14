`timescale 1 ns / 1 ps

module tb_memory_banks;

    // Parameters
    localparam int AWIDTH = 10;
    localparam int DWIDTH = 16;
    localparam int NBANKS = 5;
    localparam int TOTAL_DWIDTH = NBANKS * DWIDTH;

    // Common clock
    logic CLK;

    //================================================================//
    // Weight Bank Memory Signals
    //================================================================//
    logic                         arbiter_WM_wvalid_i;
    logic [AWIDTH-1:0]            arbiter_WM_waddr_i;
    logic [TOTAL_DWIDTH-1:0]      arbiter_WM_wdata_i;

    logic                         ctrl_WM_bank0_rd_en_i;
    logic                         ctrl_WM_bank1_rd_en_i;
    logic                         ctrl_WM_bank2_rd_en_i;
    logic                         ctrl_WM_bank3_rd_en_i;
    logic                         ctrl_WM_bank4_rd_en_i;

    logic [AWIDTH-1:0]            ctrl_WM_bank0_addr_i;
    logic [AWIDTH-1:0]            ctrl_WM_bank1_addr_i;
    logic [AWIDTH-1:0]            ctrl_WM_bank2_addr_i;
    logic [AWIDTH-1:0]            ctrl_WM_bank3_addr_i;
    logic [AWIDTH-1:0]            ctrl_WM_bank4_addr_i;

    logic [DWIDTH-1:0]            bank0_mem_weight_o;
    logic [DWIDTH-1:0]            bank1_mem_weight_o;
    logic [DWIDTH-1:0]            bank2_mem_weight_o;
    logic [DWIDTH-1:0]            bank3_mem_weight_o;
    logic [DWIDTH-1:0]            bank4_mem_weight_o;

    logic                         bank0_mem_weight_valid_o;
    logic                         bank1_mem_weight_valid_o;
    logic                         bank2_mem_weight_valid_o;
    logic                         bank3_mem_weight_valid_o;
    logic                         bank4_mem_weight_valid_o;

    //================================================================//
    // Bias Bank Memory Signals
    //================================================================//
    logic                         arbiter_BM_wvalid_i;
    logic [AWIDTH-1:0]            arbiter_BM_waddr_i;
    logic [TOTAL_DWIDTH-1:0]      arbiter_BM_wdata_i;

    logic                         ctrl_BM_bank0_rd_en_i;
    logic                         ctrl_BM_bank1_rd_en_i;
    logic                         ctrl_BM_bank2_rd_en_i;
    logic                         ctrl_BM_bank3_rd_en_i;
    logic                         ctrl_BM_bank4_rd_en_i;

    logic [AWIDTH-1:0]            ctrl_BM_bank0_addr_i;
    logic [AWIDTH-1:0]            ctrl_BM_bank1_addr_i;
    logic [AWIDTH-1:0]            ctrl_BM_bank2_addr_i;
    logic [AWIDTH-1:0]            ctrl_BM_bank3_addr_i;
    logic [AWIDTH-1:0]            ctrl_BM_bank4_addr_i;

    logic [DWIDTH-1:0]            bank0_mem_bias_o;
    logic [DWIDTH-1:0]            bank1_mem_bias_o;
    logic [DWIDTH-1:0]            bank2_mem_bias_o;
    logic [DWIDTH-1:0]            bank3_mem_bias_o;
    logic [DWIDTH-1:0]            bank4_mem_bias_o;

    logic                         bank0_mem_bias_valid_o;
    logic                         bank1_mem_bias_valid_o;
    logic                         bank2_mem_bias_valid_o;
    logic                         bank3_mem_bias_valid_o;
    logic                         bank4_mem_bias_valid_o;

    //================================================================//
    // Ping Pong FMAP Bank Memory Signals
    //================================================================//
    logic                         arbiter_FM_wvalid_i;
    logic [AWIDTH-1:0]            arbiter_FM_waddr_i;
    logic [TOTAL_DWIDTH-1:0]      arbiter_FM_wdata_i;

    logic                         arbiter_FM_arvalid_i;
    logic [AWIDTH-1:0]            arbiter_FM_raddr_i;
    logic [TOTAL_DWIDTH-1:0]      arbiter_FM_rdata_o;

    logic                         ctrl_FM_bank0_rd_en_i;
    logic                         ctrl_FM_bank1_rd_en_i;
    logic                         ctrl_FM_bank2_rd_en_i;
    logic                         ctrl_FM_bank3_rd_en_i;
    logic                         ctrl_FM_bank4_rd_en_i;

    logic                         ctrl_FM_bank0_wr_en_i;
    logic                         ctrl_FM_bank1_wr_en_i;
    logic                         ctrl_FM_bank2_wr_en_i;
    logic                         ctrl_FM_bank3_wr_en_i;
    logic                         ctrl_FM_bank4_wr_en_i;

    logic [AWIDTH-1:0]            ctrl_FM_bank0_addr_i;
    logic [AWIDTH-1:0]            ctrl_FM_bank1_addr_i;
    logic [AWIDTH-1:0]            ctrl_FM_bank2_addr_i;
    logic [AWIDTH-1:0]            ctrl_FM_bank3_addr_i;
    logic [AWIDTH-1:0]            ctrl_FM_bank4_addr_i;

    logic [DWIDTH-1:0]            bank0_mem_ofmap_i;
    logic [DWIDTH-1:0]            bank1_mem_ofmap_i;
    logic [DWIDTH-1:0]            bank2_mem_ofmap_i;
    logic [DWIDTH-1:0]            bank3_mem_ofmap_i;
    logic [DWIDTH-1:0]            bank4_mem_ofmap_i;

    logic                         bank0_mem_ofmap_valid_i;
    logic                         bank1_mem_ofmap_valid_i;
    logic                         bank2_mem_ofmap_valid_i;
    logic                         bank3_mem_ofmap_valid_i;
    logic                         bank4_mem_ofmap_valid_i;

    logic [DWIDTH-1:0]            bank0_mem_ifmap_o;
    logic [DWIDTH-1:0]            bank1_mem_ifmap_o;
    logic [DWIDTH-1:0]            bank2_mem_ifmap_o;
    logic [DWIDTH-1:0]            bank3_mem_ifmap_o;
    logic [DWIDTH-1:0]            bank4_mem_ifmap_o;

    logic                         bank0_mem_ifmap_valid_o;
    logic                         bank1_mem_ifmap_valid_o;
    logic                         bank2_mem_ifmap_valid_o;
    logic                         bank3_mem_ifmap_valid_o;
    logic                         bank4_mem_ifmap_valid_o;

    //================================================================//
    // UUT Instantiations
    //================================================================//
    weight_bank_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) u_weight_bank (
        .CLK(CLK),
        .arbiter_WM_wvalid_i(arbiter_WM_wvalid_i),
        .arbiter_WM_waddr_i(arbiter_WM_waddr_i),
        .arbiter_WM_wdata_i(arbiter_WM_wdata_i),
        .ctrl_bank0_rd_en_i(ctrl_WM_bank0_rd_en_i),
        .ctrl_bank1_rd_en_i(ctrl_WM_bank1_rd_en_i),
        .ctrl_bank2_rd_en_i(ctrl_WM_bank2_rd_en_i),
        .ctrl_bank3_rd_en_i(ctrl_WM_bank3_rd_en_i),
        .ctrl_bank4_rd_en_i(ctrl_WM_bank4_rd_en_i),
        .ctrl_bank0_addr_i(ctrl_WM_bank0_addr_i),
        .ctrl_bank1_addr_i(ctrl_WM_bank1_addr_i),
        .ctrl_bank2_addr_i(ctrl_WM_bank2_addr_i),
        .ctrl_bank3_addr_i(ctrl_WM_bank3_addr_i),
        .ctrl_bank4_addr_i(ctrl_WM_bank4_addr_i),
        .bank0_mem_weight_o(bank0_mem_weight_o),
        .bank1_mem_weight_o(bank1_mem_weight_o),
        .bank2_mem_weight_o(bank2_mem_weight_o),
        .bank3_mem_weight_o(bank3_mem_weight_o),
        .bank4_mem_weight_o(bank4_mem_weight_o),
        .bank0_mem_weight_valid_o(bank0_mem_weight_valid_o),
        .bank1_mem_weight_valid_o(bank1_mem_weight_valid_o),
        .bank2_mem_weight_valid_o(bank2_mem_weight_valid_o),
        .bank3_mem_weight_valid_o(bank3_mem_weight_valid_o),
        .bank4_mem_weight_valid_o(bank4_mem_weight_valid_o)
    );

    bias_bank_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) u_bias_bank (
        .CLK(CLK),
        .arbiter_BM_wvalid_i(arbiter_BM_wvalid_i),
        .arbiter_BM_waddr_i(arbiter_BM_waddr_i),
        .arbiter_BM_wdata_i(arbiter_BM_wdata_i),
        .ctrl_bank0_rd_en_i(ctrl_BM_bank0_rd_en_i),
        .ctrl_bank1_rd_en_i(ctrl_BM_bank1_rd_en_i),
        .ctrl_bank2_rd_en_i(ctrl_BM_bank2_rd_en_i),
        .ctrl_bank3_rd_en_i(ctrl_BM_bank3_rd_en_i),
        .ctrl_bank4_rd_en_i(ctrl_BM_bank4_rd_en_i),
        .ctrl_bank0_addr_i(ctrl_BM_bank0_addr_i),
        .ctrl_bank1_addr_i(ctrl_BM_bank1_addr_i),
        .ctrl_bank2_addr_i(ctrl_BM_bank2_addr_i),
        .ctrl_bank3_addr_i(ctrl_BM_bank3_addr_i),
        .ctrl_bank4_addr_i(ctrl_BM_bank4_addr_i),
        .bank0_mem_bias_o(bank0_mem_bias_o),
        .bank1_mem_bias_o(bank1_mem_bias_o),
        .bank2_mem_bias_o(bank2_mem_bias_o),
        .bank3_mem_bias_o(bank3_mem_bias_o),
        .bank4_mem_bias_o(bank4_mem_bias_o),
        .bank0_mem_bias_valid_o(bank0_mem_bias_valid_o),
        .bank1_mem_bias_valid_o(bank1_mem_bias_valid_o),
        .bank2_mem_bias_valid_o(bank2_mem_bias_valid_o),
        .bank3_mem_bias_valid_o(bank3_mem_bias_valid_o),
        .bank4_mem_bias_valid_o(bank4_mem_bias_valid_o)
    );

    ping_pong_fmap_bank_memory #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) u_fmap_bank (
        .CLK(CLK),
        .arbiter_FM_wvalid_i(arbiter_FM_wvalid_i),
        .arbiter_FM_waddr_i(arbiter_FM_waddr_i),
        .arbiter_FM_wdata_i(arbiter_FM_wdata_i),
        .arbiter_FM_arvalid_i(arbiter_FM_arvalid_i),
        .arbiter_FM_raddr_i(arbiter_FM_raddr_i),
        .arbiter_FM_rdata_o(arbiter_FM_rdata_o),
        .ctrl_bank0_rd_en_i(ctrl_FM_bank0_rd_en_i),
        .ctrl_bank1_rd_en_i(ctrl_FM_bank1_rd_en_i),
        .ctrl_bank2_rd_en_i(ctrl_FM_bank2_rd_en_i),
        .ctrl_bank3_rd_en_i(ctrl_FM_bank3_rd_en_i),
        .ctrl_bank4_rd_en_i(ctrl_FM_bank4_rd_en_i),
        .ctrl_bank0_wr_en_i(ctrl_FM_bank0_wr_en_i),
        .ctrl_bank1_wr_en_i(ctrl_FM_bank1_wr_en_i),
        .ctrl_bank2_wr_en_i(ctrl_FM_bank2_wr_en_i),
        .ctrl_bank3_wr_en_i(ctrl_FM_bank3_wr_en_i),
        .ctrl_bank4_wr_en_i(ctrl_FM_bank4_wr_en_i),
        .ctrl_bank0_addr_i(ctrl_FM_bank0_addr_i),
        .ctrl_bank1_addr_i(ctrl_FM_bank1_addr_i),
        .ctrl_bank2_addr_i(ctrl_FM_bank2_addr_i),
        .ctrl_bank3_addr_i(ctrl_FM_bank3_addr_i),
        .ctrl_bank4_addr_i(ctrl_FM_bank4_addr_i),
        .bank0_mem_ofmap_i(bank0_mem_ofmap_i),
        .bank1_mem_ofmap_i(bank1_mem_ofmap_i),
        .bank2_mem_ofmap_i(bank2_mem_ofmap_i),
        .bank3_mem_ofmap_i(bank3_mem_ofmap_i),
        .bank4_mem_ofmap_i(bank4_mem_ofmap_i),
        .bank0_mem_ofmap_valid_i(bank0_mem_ofmap_valid_i),
        .bank1_mem_ofmap_valid_i(bank1_mem_ofmap_valid_i),
        .bank2_mem_ofmap_valid_i(bank2_mem_ofmap_valid_i),
        .bank3_mem_ofmap_valid_i(bank3_mem_ofmap_valid_i),
        .bank4_mem_ofmap_valid_i(bank4_mem_ofmap_valid_i),
        .bank0_mem_ifmap_o(bank0_mem_ifmap_o),
        .bank1_mem_ifmap_o(bank1_mem_ifmap_o),
        .bank2_mem_ifmap_o(bank2_mem_ifmap_o),
        .bank3_mem_ifmap_o(bank3_mem_ifmap_o),
        .bank4_mem_ifmap_o(bank4_mem_ifmap_o),
        .bank0_mem_ifmap_valid_o(bank0_mem_ifmap_valid_o),
        .bank1_mem_ifmap_valid_o(bank1_mem_ifmap_valid_o),
        .bank2_mem_ifmap_valid_o(bank2_mem_ifmap_valid_o),
        .bank3_mem_ifmap_valid_o(bank3_mem_ifmap_valid_o),
        .bank4_mem_ifmap_valid_o(bank4_mem_ifmap_valid_o)
    );

    // Clock Generation
    always #10 CLK = ~CLK; // 50 MHz Clock

    // Test Variables
    logic [TOTAL_DWIDTH-1:0] expected_data;
    logic [DWIDTH-1:0] expected_word;
    logic error_flag;

    initial begin
        CLK = 0;
        error_flag = 0;

        // Initialize signals
        arbiter_WM_wvalid_i = 0;
        arbiter_WM_waddr_i  = 0;
        arbiter_WM_wdata_i  = 0;

        ctrl_WM_bank0_rd_en_i = 0;
        ctrl_WM_bank1_rd_en_i = 0;
        ctrl_WM_bank2_rd_en_i = 0;
        ctrl_WM_bank3_rd_en_i = 0;
        ctrl_WM_bank4_rd_en_i = 0;

        ctrl_WM_bank0_addr_i = 0;
        ctrl_WM_bank1_addr_i = 0;
        ctrl_WM_bank2_addr_i = 0;
        ctrl_WM_bank3_addr_i = 0;
        ctrl_WM_bank4_addr_i = 0;

        arbiter_BM_wvalid_i = 0;
        arbiter_BM_waddr_i  = 0;
        arbiter_BM_wdata_i  = 0;

        ctrl_BM_bank0_rd_en_i = 0;
        ctrl_BM_bank1_rd_en_i = 0;
        ctrl_BM_bank2_rd_en_i = 0;
        ctrl_BM_bank3_rd_en_i = 0;
        ctrl_BM_bank4_rd_en_i = 0;

        ctrl_BM_bank0_addr_i = 0;
        ctrl_BM_bank1_addr_i = 0;
        ctrl_BM_bank2_addr_i = 0;
        ctrl_BM_bank3_addr_i = 0;
        ctrl_BM_bank4_addr_i = 0;

        arbiter_FM_wvalid_i = 0;
        arbiter_FM_waddr_i  = 0;
        arbiter_FM_wdata_i  = 0;
        arbiter_FM_arvalid_i = 0;
        arbiter_FM_raddr_i  = 0;

        ctrl_FM_bank0_rd_en_i = 0;
        ctrl_FM_bank1_rd_en_i = 0;
        ctrl_FM_bank2_rd_en_i = 0;
        ctrl_FM_bank3_rd_en_i = 0;
        ctrl_FM_bank4_rd_en_i = 0;

        ctrl_FM_bank0_wr_en_i = 0;
        ctrl_FM_bank1_wr_en_i = 0;
        ctrl_FM_bank2_wr_en_i = 0;
        ctrl_FM_bank3_wr_en_i = 0;
        ctrl_FM_bank4_wr_en_i = 0;

        ctrl_FM_bank0_addr_i = 0;
        ctrl_FM_bank1_addr_i = 0;
        ctrl_FM_bank2_addr_i = 0;
        ctrl_FM_bank3_addr_i = 0;
        ctrl_FM_bank4_addr_i = 0;

        bank0_mem_ofmap_i = 0;
        bank1_mem_ofmap_i = 0;
        bank2_mem_ofmap_i = 0;
        bank3_mem_ofmap_i = 0;
        bank4_mem_ofmap_i = 0;

        bank0_mem_ofmap_valid_i = 0;
        bank1_mem_ofmap_valid_i = 0;
        bank2_mem_ofmap_valid_i = 0;
        bank3_mem_ofmap_valid_i = 0;
        bank4_mem_ofmap_valid_i = 0;

        #50;

        //================================================================//
        // TEST CASE 1: Weight Bank Memory Verification
        //================================================================//
        $display("[TEST] Case 1: Write and Read Weight Bank Memory");
        @(posedge CLK);
        #1;
        arbiter_WM_wvalid_i = 1;
        arbiter_WM_waddr_i  = 10'd42;
        arbiter_WM_wdata_i  = 80'h1111_2222_3333_4444_5555;

        @(posedge CLK);
        #1;
        arbiter_WM_wvalid_i = 0;

        @(posedge CLK);
        #1;
        // Verify Read Latency & Gating
        // Enable read on all banks
        ctrl_WM_bank0_rd_en_i = 1;
        ctrl_WM_bank1_rd_en_i = 1;
        ctrl_WM_bank2_rd_en_i = 1;
        ctrl_WM_bank3_rd_en_i = 1;
        ctrl_WM_bank4_rd_en_i = 1;

        ctrl_WM_bank0_addr_i = 10'd42;
        ctrl_WM_bank1_addr_i = 10'd42;
        ctrl_WM_bank2_addr_i = 10'd42;
        ctrl_WM_bank3_addr_i = 10'd42;
        ctrl_WM_bank4_addr_i = 10'd42;

        @(posedge CLK);
        #1;
        // Check output values (read latency is 1 cycle)
        if (bank0_mem_weight_o !== 16'h5555 || !bank0_mem_weight_valid_o) begin
            $display("  [FAIL] Weight Bank 0 read failed. expected=5555, actual=%h, valid=%b", bank0_mem_weight_o, bank0_mem_weight_valid_o);
            error_flag = 1;
        end
        if (bank1_mem_weight_o !== 16'h4444 || !bank1_mem_weight_valid_o) begin
            $display("  [FAIL] Weight Bank 1 read failed. expected=4444, actual=%h, valid=%b", bank1_mem_weight_o, bank1_mem_weight_valid_o);
            error_flag = 1;
        end
        if (bank2_mem_weight_o !== 16'h3333 || !bank2_mem_weight_valid_o) begin
            $display("  [FAIL] Weight Bank 2 read failed. expected=3333, actual=%h, valid=%b", bank2_mem_weight_o, bank2_mem_weight_valid_o);
            error_flag = 1;
        end
        if (bank3_mem_weight_o !== 16'h2222 || !bank3_mem_weight_valid_o) begin
            $display("  [FAIL] Weight Bank 3 read failed. expected=2222, actual=%h, valid=%b", bank3_mem_weight_o, bank3_mem_weight_valid_o);
            error_flag = 1;
        end
        if (bank4_mem_weight_o !== 16'h1111 || !bank4_mem_weight_valid_o) begin
            $display("  [FAIL] Weight Bank 4 read failed. expected=1111, actual=%h, valid=%b", bank4_mem_weight_o, bank4_mem_weight_valid_o);
            error_flag = 1;
        end

        // Deassert read enables and verify outputs return to 0 next cycle
        ctrl_WM_bank0_rd_en_i = 0;
        ctrl_WM_bank1_rd_en_i = 0;
        ctrl_WM_bank2_rd_en_i = 0;
        ctrl_WM_bank3_rd_en_i = 0;
        ctrl_WM_bank4_rd_en_i = 0;

        @(posedge CLK);
        #1;
        if (bank0_mem_weight_o !== 16'h0000 || bank0_mem_weight_valid_o) begin
            $display("  [FAIL] Weight Bank 0 disable failed. actual=%h, valid=%b", bank0_mem_weight_o, bank0_mem_weight_valid_o);
            error_flag = 1;
        end

        if (!error_flag) $display("  [PASS] Weight Bank Memory Verified Successfully!");

        #50;

        //================================================================//
        // TEST CASE 2: Bias Bank Memory Verification
        //================================================================//
        $display("[TEST] Case 2: Write and Read Bias Bank Memory");
        @(posedge CLK);
        #1;
        arbiter_BM_wvalid_i = 1;
        arbiter_BM_waddr_i  = 10'd100;
        arbiter_BM_wdata_i  = 80'hAAAA_BBBB_CCCC_DDDD_EEEE;

        @(posedge CLK);
        #1;
        arbiter_BM_wvalid_i = 0;

        @(posedge CLK);
        #1;
        // Enable read
        ctrl_BM_bank0_rd_en_i = 1;
        ctrl_BM_bank1_rd_en_i = 1;
        ctrl_BM_bank2_rd_en_i = 1;
        ctrl_BM_bank3_rd_en_i = 1;
        ctrl_BM_bank4_rd_en_i = 1;

        ctrl_BM_bank0_addr_i = 10'd100;
        ctrl_BM_bank1_addr_i = 10'd100;
        ctrl_BM_bank2_addr_i = 10'd100;
        ctrl_BM_bank3_addr_i = 10'd100;
        ctrl_BM_bank4_addr_i = 10'd100;

        @(posedge CLK);
        #1;
        // Verify outputs
        if (bank0_mem_bias_o !== 16'hEEEE || !bank0_mem_bias_valid_o) begin
            $display("  [FAIL] Bias Bank 0 read failed. expected=EEEE, actual=%h, valid=%b", bank0_mem_bias_o, bank0_mem_bias_valid_o);
            error_flag = 1;
        end
        if (bank1_mem_bias_o !== 16'hDDDD || !bank1_mem_bias_valid_o) begin
            $display("  [FAIL] Bias Bank 1 read failed. expected=DDDD, actual=%h, valid=%b", bank1_mem_bias_o, bank1_mem_bias_valid_o);
            error_flag = 1;
        end
        if (bank2_mem_bias_o !== 16'hCCCC || !bank2_mem_bias_valid_o) begin
            $display("  [FAIL] Bias Bank 2 read failed. expected=CCCC, actual=%h, valid=%b", bank2_mem_bias_o, bank2_mem_bias_valid_o);
            error_flag = 1;
        end
        if (bank3_mem_bias_o !== 16'hBBBB || !bank3_mem_bias_valid_o) begin
            $display("  [FAIL] Bias Bank 3 read failed. expected=BBBB, actual=%h, valid=%b", bank3_mem_bias_o, bank3_mem_bias_valid_o);
            error_flag = 1;
        end
        if (bank4_mem_bias_o !== 16'hAAAA || !bank4_mem_bias_valid_o) begin
            $display("  [FAIL] Bias Bank 4 read failed. expected=AAAA, actual=%h, valid=%b", bank4_mem_bias_o, bank4_mem_bias_valid_o);
            error_flag = 1;
        end

        // Deassert read enables
        ctrl_BM_bank0_rd_en_i = 0;
        ctrl_BM_bank1_rd_en_i = 0;
        ctrl_BM_bank2_rd_en_i = 0;
        ctrl_BM_bank3_rd_en_i = 0;
        ctrl_BM_bank4_rd_en_i = 0;

        @(posedge CLK);
        #1;
        if (bank0_mem_bias_o !== 16'h0000 || bank0_mem_bias_valid_o) begin
            $display("  [FAIL] Bias Bank 0 disable failed. actual=%h, valid=%b", bank0_mem_bias_o, bank0_mem_bias_valid_o);
            error_flag = 1;
        end

        if (!error_flag) $display("  [PASS] Bias Bank Memory Verified Successfully!");

        #50;

        //================================================================//
        // TEST CASE 3: Ping Pong FMAP Bank Memory - Port A (Arbiter Path)
        //================================================================//
        $display("[TEST] Case 3: Arbiter Read/Write to Ping Pong FMAP Memory");
        @(posedge CLK);
        #1;
        arbiter_FM_wvalid_i = 1;
        arbiter_FM_waddr_i  = 10'd200;
        arbiter_FM_wdata_i  = 80'h9999_8888_7777_6666_5555;

        @(posedge CLK);
        #1;
        arbiter_FM_wvalid_i = 0;

        @(posedge CLK);
        #1;
        arbiter_FM_arvalid_i = 1;
        arbiter_FM_raddr_i   = 10'd200;

        @(posedge CLK);
        #1;
        arbiter_FM_arvalid_i = 0;
        if (arbiter_FM_rdata_o !== 80'h9999_8888_7777_6666_5555) begin
            $display("  [FAIL] Arbiter read back from FMAP failed. expected=9999_8888_7777_6666_5555, actual=%h", arbiter_FM_rdata_o);
            error_flag = 1;
        end

        if (!error_flag) $display("  [PASS] FMAP Arbiter read/write path passed.");

        #50;

        //================================================================//
        // TEST CASE 4: Ping Pong FMAP Bank Memory - Port B (Controller/PEA Path)
        //================================================================//
        $display("[TEST] Case 4: Controller Read / PEA Writeback to Ping Pong FMAP Memory");
        
        // Let's do a Controller read from address 200 (which was written by arbiter in Case 3)
        @(posedge CLK);
        #1;
        ctrl_FM_bank0_rd_en_i = 1;
        ctrl_FM_bank1_rd_en_i = 1;
        ctrl_FM_bank2_rd_en_i = 1;
        ctrl_FM_bank3_rd_en_i = 1;
        ctrl_FM_bank4_rd_en_i = 1;

        ctrl_FM_bank0_addr_i = 10'd200;
        ctrl_FM_bank1_addr_i = 10'd200;
        ctrl_FM_bank2_addr_i = 10'd200;
        ctrl_FM_bank3_addr_i = 10'd200;
        ctrl_FM_bank4_addr_i = 10'd200;

        @(posedge CLK);
        #1;
        if (bank0_mem_ifmap_o !== 16'h5555 || !bank0_mem_ifmap_valid_o ||
            bank1_mem_ifmap_o !== 16'h6666 || !bank1_mem_ifmap_valid_o ||
            bank2_mem_ifmap_o !== 16'h7777 || !bank2_mem_ifmap_valid_o ||
            bank3_mem_ifmap_o !== 16'h8888 || !bank3_mem_ifmap_valid_o ||
            bank4_mem_ifmap_o !== 16'h9999 || !bank4_mem_ifmap_valid_o) begin
            $display("  [FAIL] Controller read from FMAP bank failed.");
            $display("  bank0=%h, valid0=%b (expected 5555)", bank0_mem_ifmap_o, bank0_mem_ifmap_valid_o);
            $display("  bank1=%h, valid1=%b (expected 6666)", bank1_mem_ifmap_o, bank1_mem_ifmap_valid_o);
            $display("  bank2=%h, valid2=%b (expected 7777)", bank2_mem_ifmap_o, bank2_mem_ifmap_valid_o);
            $display("  bank3=%h, valid3=%b (expected 8888)", bank3_mem_ifmap_o, bank3_mem_ifmap_valid_o);
            $display("  bank4=%h, valid4=%b (expected 9999)", bank4_mem_ifmap_o, bank4_mem_ifmap_valid_o);
            error_flag = 1;
        end

        // Deassert read enables
        ctrl_FM_bank0_rd_en_i = 0;
        ctrl_FM_bank1_rd_en_i = 0;
        ctrl_FM_bank2_rd_en_i = 0;
        ctrl_FM_bank3_rd_en_i = 0;
        ctrl_FM_bank4_rd_en_i = 0;

        #50;

        // PEA Writeback test to address 300
        @(posedge CLK);
        #1;
        ctrl_FM_bank0_wr_en_i = 1;
        ctrl_FM_bank1_wr_en_i = 1;
        ctrl_FM_bank2_wr_en_i = 1;
        ctrl_FM_bank3_wr_en_i = 1;
        ctrl_FM_bank4_wr_en_i = 1;

        ctrl_FM_bank0_addr_i = 10'd300;
        ctrl_FM_bank1_addr_i = 10'd300;
        ctrl_FM_bank2_addr_i = 10'd300;
        ctrl_FM_bank3_addr_i = 10'd300;
        ctrl_FM_bank4_addr_i = 10'd300;

        bank0_mem_ofmap_i = 16'hA001;
        bank1_mem_ofmap_i = 16'hB002;
        bank2_mem_ofmap_i = 16'hC003;
        bank3_mem_ofmap_i = 16'hD004;
        bank4_mem_ofmap_i = 16'hE005;

        bank0_mem_ofmap_valid_i = 1;
        bank1_mem_ofmap_valid_i = 1;
        bank2_mem_ofmap_valid_i = 1;
        bank3_mem_ofmap_valid_i = 1;
        bank4_mem_ofmap_valid_i = 1;

        @(posedge CLK);
        #1;
        // Deassert writeback
        ctrl_FM_bank0_wr_en_i = 0;
        ctrl_FM_bank1_wr_en_i = 0;
        ctrl_FM_bank2_wr_en_i = 0;
        ctrl_FM_bank3_wr_en_i = 0;
        ctrl_FM_bank4_wr_en_i = 0;

        bank0_mem_ofmap_valid_i = 0;
        bank1_mem_ofmap_valid_i = 0;
        bank2_mem_ofmap_valid_i = 0;
        bank3_mem_ofmap_valid_i = 0;
        bank4_mem_ofmap_valid_i = 0;

        @(posedge CLK);
        #1;
        // Read back address 300 via arbiter read path (Port A) to confirm write was successful
        arbiter_FM_arvalid_i = 1;
        arbiter_FM_raddr_i   = 10'd300;

        @(posedge CLK);
        #1;
        arbiter_FM_arvalid_i = 0;
        if (arbiter_FM_rdata_o !== 80'hE005_D004_C003_B002_A001) begin
            $display("  [FAIL] PEA Writeback read verification failed. expected=E005_D004_C003_B002_A001, actual=%h", arbiter_FM_rdata_o);
            error_flag = 1;
        end

        if (!error_flag) $display("  [PASS] FMAP Controller/PEA access paths passed.");

        #50;

        // Final Report
        if (error_flag) begin
            $display("\n==========================================");
            $display("[RESULT] tb_memory_banks: [FAIL]");
            $display("==========================================\n");
        end else begin
            $display("\n==========================================");
            $display("[RESULT] tb_memory_banks: [PASS]");
            $display("==========================================\n");
        end

        $finish;
    end

endmodule
