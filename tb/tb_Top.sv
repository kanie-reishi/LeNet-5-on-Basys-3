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
        
        // 0. Send LOAD command (WRITE_MEM to address 0 to transition to s_LOAD)
        tb_payload[0] = 8'h00; // Address H
        tb_payload[1] = 8'h00; // Address L
        tb_payload[2] = 8'h00; tb_payload[3] = 8'h00;
        tb_payload[4] = 8'h00; tb_payload[5] = 8'h00; tb_payload[6] = 8'h00; tb_payload[7] = 8'h00;
        tb_payload[8] = 8'h00; tb_payload[9] = 8'h00; tb_payload[10] = 8'h00; tb_payload[11] = 8'h01;
        send_uart_packet(8'h01, 16'd12); // WRITE_MEM to address 0 (LOAD)
        #200000;

        // 1. Send instruction write packet (WRITE_MEM to Instruction memory)
        // Target address inside IM: AXI_WADDR_INST = 7 -> addr = 13'h1C00 (7 << 10) = 7168
        tb_payload[0] = 8'h1C; // Address H
        tb_payload[1] = 8'h00; // Address L
        // Data: 80'h000000001002000100651001 (padded C1 instruction)
        tb_payload[2] = 8'h00; tb_payload[3] = 8'h00;
        tb_payload[4] = 8'h10; tb_payload[5] = 8'h02; tb_payload[6] = 8'h00; tb_payload[7] = 8'h01;
        tb_payload[8] = 8'h00; tb_payload[9] = 8'h65; tb_payload[10] = 8'h10; tb_payload[11] = 8'h01;
        
        send_uart_packet(8'h01, 16'd12); // WRITE_MEM
        #200000; // Wait for transmission and bridge write
        
        // Verify write in Instruction Memory BRAM
        if (u_top_level.u_cnn_core.u_instruction_memory.u_instruction_mem.mem[0] === 64'h1002000100651001) begin
            $display("[PASS] Instruction Memory loaded correctly through UART!");
        end else begin
            $display("[FAIL] Instruction Memory mismatch! Got: %h", u_top_level.u_cnn_core.u_instruction_memory.u_instruction_mem.mem[0]);
        end
        
        // 2. Send START_INFERENCE command packet
        send_uart_packet(8'h03, 16'd0);
        #100000;
        
        // Verify state is s_LOAD or s_FETCH
        $display("[INFO] Active FSM State of CNN Controller: %d", u_top_level.u_cnn_core.state_w);
        if (u_top_level.u_cnn_core.state_w != 3'd0) begin
            $display("[PASS] CNN Controller started execution after UART START command!");
        end else begin
            $display("[FAIL] CNN Controller is still IDLE!");
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
