`timescale 1 ns / 1 ps

module tb_sram_tdp;

    // Parameters
    localparam int AWIDTH = 10;
    localparam int DWIDTH = 32;

    // Signals
    logic                 clka;
    logic                 ena;
    logic                 wea;
    logic [AWIDTH-1:0]    addra;
    logic [DWIDTH-1:0]    dina;
    logic [DWIDTH-1:0]    douta;

    logic                 clkb;
    logic                 enb;
    logic                 web;
    logic [AWIDTH-1:0]    addrb;
    logic [DWIDTH-1:0]    dinb;
    logic [DWIDTH-1:0]    doutb;

    // Instantiate UUT
    sram_tdp #(
        .AWIDTH(AWIDTH),
        .DWIDTH(DWIDTH)
    ) uut (
        .*
    );

    // Independent Clocks
    always #10 clka = ~clka; // 50 MHz
    always #12.5 clkb = ~clkb; // 40 MHz

    initial begin
        // Initialize
        clka = 0;
        ena = 0;
        wea = 0;
        addra = 0;
        dina = 0;

        clkb = 0;
        enb = 0;
        web = 0;
        addrb = 0;
        dinb = 0;

        #50;

        // Test Case 1: Write and Read on Port A
        $display("[TEST] Case 1: Write and Read on Port A");
        @(posedge clka);
        #1;
        ena = 1;
        wea = 1;
        addra = 10'd55;
        dina = 32'hDEADBEEF;
        
        @(posedge clka);
        #1;
        wea = 0;
        
        @(posedge clka);
        #1;
        if (douta == 32'hDEADBEEF) begin
            $display("  [PASS] Port A write/read passed. douta = 32'h%h", douta);
        end else begin
            $display("  [FAIL] Port A write/read failed. douta = 32'h%h", douta);
        end
        ena = 0;
        #50;

        // Test Case 2: Same-port Write and Read concurrently on Port A (Read-First)
        $display("[TEST] Case 2: Same-port Write and Read on address 128 (Read-First)");
        // Write 32'hFEEDFACE to address 128, while reading it concurrently
        @(posedge clka);
        #1;
        ena = 1;
        wea = 1;
        addra = 10'd128;
        dina = 32'hFEEDFACE;

        @(posedge clka); // This triggers the write and concurrent read
        #1;
        // In Read-First mode, douta should return the OLD value (0)
        if (douta == 32'h0) begin
            $display("  [PASS] Port A returned old value (0) during concurrent write (Read-First). douta = 32'h%h", douta);
        end else begin
            $display("  [FAIL] Port A returned unexpected value. douta = 32'h%h (Expected: 0)", douta);
        end

        // Wait another cycle with wea cleared to let it read the newly written value
        wea = 0;
        @(posedge clka);
        #1;
        if (douta == 32'hFEEDFACE) begin
            $display("  [PASS] Port A read newly written value successfully. douta = 32'h%h", douta);
        end else begin
            $display("  [FAIL] Port A failed to read new value. douta = 32'h%h (Expected: FEEDFACE)", douta);
        end
        ena = 0;
        #50;

        $display("[INFO] tb_sram_tdp complete.");
        $finish;
    end

endmodule
