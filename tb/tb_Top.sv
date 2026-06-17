`timescale 1 ns / 1 ps

module tb_Top;

    // Simulation Clock Parameters (1 MHz clock for fast UART simulation)
    localparam int CLK_FREQ_HZ = 1_000_000;
    localparam int BAUD_RATE   = 115200;
    localparam int CLK_PERIOD  = 1000; // 1000 ns (1 MHz)
    localparam int CLK_PER_BIT = CLK_FREQ_HZ / BAUD_RATE; // 8.68 -> rounded to 9 cycles
    localparam int BIT_PERIOD  = 9 * CLK_PERIOD; // 9000 ns per bit

    // Signals
    logic       CLK;
    logic       btnC;
    logic       RsRx;
    wire        RsTx;
    wire [6:0]  seg;
    wire        dp;
    wire [3:0]  an;

    // Instantiate Top Level Module
    top_level #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_top_level (
        .CLK(CLK),
        .btnC(btnC),
        .RsRx(RsRx),
        .RsTx(RsTx),
        .seg(seg),
        .dp(dp),
        .an(an)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) CLK = ~CLK;

    // Helper task to send 1 UART byte (8 data bits, LSB first)
    task send_uart_byte(input [7:0] byte_val);
        integer bit_idx;
        // Start bit (low)
        RsRx = 1'b0;
        #(BIT_PERIOD);
        
        // Data bits
        for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
            RsRx = byte_val[bit_idx];
            #(BIT_PERIOD);
        end
        
        // Stop bit (high)
        RsRx = 1'b1;
        #(BIT_PERIOD);
        #(CLK_PERIOD * 5); // small inter-byte delay
    endtask

    // Helper task to send a full UART command packet
    // payload size must match the length parameter
    logic [7:0] tb_payload [0:15];
    task send_uart_packet(input [7:0] cmd, input [15:0] len);
        integer i;
        logic [7:0] chk;
        
        $display("[UART_HOST] Sending Packet: cmd=%h, len=%d", cmd, len);
        chk = cmd ^ len[15:8] ^ len[7:0];
        
        send_uart_byte(8'h02); // STX
        send_uart_byte(cmd);
        send_uart_byte(len[15:8]);
        send_uart_byte(len[7:0]);
        
        for (i = 0; i < len; i = i + 1) begin
            send_uart_byte(tb_payload[i]);
            chk = chk ^ tb_payload[i];
        end
        
        send_uart_byte(chk); // Checksum
        send_uart_byte(8'h03); // ETX
    endtask

    // Capture RsTx bytes transmitted from FPGA
    logic [7:0] tx_captured_byte;
    task receive_uart_byte(output [7:0] byte_val);
        integer bit_idx;
        // Wait for start bit (RsTx falling edge)
        @(negedge RsTx);
        #(BIT_PERIOD / 2); // wait to middle of start bit
        if (RsTx !== 1'b0) begin
            $display("[UART_HOST_RX] Error: Invalid start bit!");
            byte_val = 8'hFF;
        end else begin
            #(BIT_PERIOD); // skip start bit
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                byte_val[bit_idx] = RsTx;
                #(BIT_PERIOD);
            end
            #(BIT_PERIOD / 2); // wait for stop bit
            if (RsTx !== 1'b1) begin
                $display("[UART_HOST_RX] Warning: Missing stop bit!");
            end
        end
    endtask

    // Background thread to listen to RsTx and display responses
    initial begin
        logic [7:0] resp_byte;
        forever begin
            receive_uart_byte(resp_byte);
            if (resp_byte == 8'h06) begin
                $display("[UART_HOST] Received ACK (0x06)");
            end else if (resp_byte == 8'h15) begin
                $display("[UART_HOST] Received NACK (0x15)");
            end else begin
                $display("[UART_HOST] Received Byte: %h", resp_byte);
            end
        end
    end

    // Simulation Driver
    initial begin
        CLK = 0;
        btnC = 1; // Active-high reset pressed
        RsRx = 1'b1; // Idle line high
        
        #2000;
        btnC = 0; // Release reset
        #5000;
        
        $display("\n--- [START] tb_Top wrapper simulation ---");
        
        // 1. Write to Bias Memory via UART
        // W_BIAS is region 6 -> address 24'h0C0000 (region 6, word address 0)
        // Data = 16'hA5A5
        tb_payload[0] = 8'h0C; // Address [23:16]
        tb_payload[1] = 8'h00; // Address [15:8]
        tb_payload[2] = 8'h00; // Address [7:0]
        tb_payload[3] = 8'hA5; // Data [15:8]
        tb_payload[4] = 8'hA5; // Data [7:0]
        send_uart_packet(8'h01, 16'd5); // WRITE_MEM
        #250000; // Wait for transmission and bridge write
        
        // Verify write in Bias Memory
        if (u_top_level.u_cnn_core.u_bias_memory.u_bias_bank.mem[0] === 16'hA5A5) begin
            $display("[PASS] Bias Memory loaded correctly through UART!");
        end else begin
            $display("[FAIL] Bias Memory mismatch! Got: %h", u_top_level.u_cnn_core.u_bias_memory.u_bias_bank.mem[0]);
        end
        
        // 2. Write 5 words to Ping FM memory to trigger packed BRAM write (W_PING_FM is region 3)
        // Word 0: 24'h060000, Data = 16'h1111
        tb_payload[0] = 8'h06; tb_payload[1] = 8'h00; tb_payload[2] = 8'h00;
        tb_payload[3] = 8'h11; tb_payload[4] = 8'h11;
        send_uart_packet(8'h01, 16'd5);
        #250000;

        // Word 1: 24'h060001, Data = 16'h2222
        tb_payload[0] = 8'h06; tb_payload[1] = 8'h00; tb_payload[2] = 8'h01;
        tb_payload[3] = 8'h22; tb_payload[4] = 8'h22;
        send_uart_packet(8'h01, 16'd5);
        #250000;

        // Word 2: 24'h060002, Data = 16'h3333
        tb_payload[0] = 8'h06; tb_payload[1] = 8'h00; tb_payload[2] = 8'h02;
        tb_payload[3] = 8'h33; tb_payload[4] = 8'h33;
        send_uart_packet(8'h01, 16'd5);
        #250000;

        // Word 3: 24'h060003, Data = 16'h4444
        tb_payload[0] = 8'h06; tb_payload[1] = 8'h00; tb_payload[2] = 8'h03;
        tb_payload[3] = 8'h44; tb_payload[4] = 8'h44;
        send_uart_packet(8'h01, 16'd5);
        #250000;

        // Word 4: 24'h060004, Data = 16'h5555
        tb_payload[0] = 8'h06; tb_payload[1] = 8'h00; tb_payload[2] = 8'h04;
        tb_payload[3] = 8'h55; tb_payload[4] = 8'h55;
        send_uart_packet(8'h01, 16'd5);
        #250000;

        // Verify writes in Ping FM Bank Memories (5 banks)
        if (u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[0].u_fm_bank.mem[0] === 16'h1111 &&
            u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[1].u_fm_bank.mem[0] === 16'h2222 &&
            u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[2].u_fm_bank.mem[0] === 16'h3333 &&
            u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[3].u_fm_bank.mem[0] === 16'h4444 &&
            u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[4].u_fm_bank.mem[0] === 16'h5555) begin
            $display("[PASS] Ping FM Memory packed words loaded correctly through UART!");
        end else begin
            $display("[FAIL] Ping FM Memory mismatch!");
            $display("  Bank 0: %h", u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[0].u_fm_bank.mem[0]);
            $display("  Bank 1: %h", u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[1].u_fm_bank.mem[0]);
            $display("  Bank 2: %h", u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[2].u_fm_bank.mem[0]);
            $display("  Bank 3: %h", u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[3].u_fm_bank.mem[0]);
            $display("  Bank 4: %h", u_top_level.u_cnn_core.u_ping_fm_memory.FM_BANK[4].u_fm_bank.mem[0]);
        end

        // 3. Send LOAD command: WRITE_MEM to W_LOAD_CTRL
        // W_LOAD_CTRL is region 0 -> address 24'h000000 (region 0, word address 0)
        // Data = 16'h0001
        tb_payload[0] = 8'h00; // Address [23:16]
        tb_payload[1] = 8'h00; // Address [15:8]
        tb_payload[2] = 8'h00; // Address [7:0]
        tb_payload[3] = 8'h00; // Data [15:8]
        tb_payload[4] = 8'h01; // Data [7:0]
        send_uart_packet(8'h01, 16'd5); // WRITE_MEM
        #250000;

        // Verify state is S_WAIT_LOAD (1)
        $display("[INFO] Active FSM State of CNN Controller after LOAD: %d", u_top_level.u_cnn_core.state_o);
        if (u_top_level.u_cnn_core.state_o == 3'd1) begin
            $display("[PASS] CNN Controller transitioned to S_WAIT_LOAD!");
        end else begin
            $display("[FAIL] CNN Controller state mismatch! Got: %d", u_top_level.u_cnn_core.state_o);
        end
        
        // 4. Send START_INFERENCE command packet
        send_uart_packet(8'h03, 16'd0);
        #150000;
        
        // Verify state transitioned past S_WAIT_LOAD
        $display("[INFO] Active FSM State of CNN Controller after START: %d", u_top_level.u_cnn_core.state_o);
        if (u_top_level.u_cnn_core.state_o != 3'd0 && u_top_level.u_cnn_core.state_o != 3'd1) begin
            $display("[PASS] CNN Controller started execution after UART START command!");
        end else begin
            $display("[FAIL] CNN Controller is still IDLE or S_WAIT_LOAD!");
        end
        
        #200000;
        $display("--- [DONE] tb_Top wrapper simulation ---");
        $finish;
    end

    // Monitor 7-segment display updates
    always @(seg or an) begin
        $display("[7SEG_MONITOR] time=%0t | anode=%b | cathode_seg=%b", $time, an, seg);
    end

endmodule
