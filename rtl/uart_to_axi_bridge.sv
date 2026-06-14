`timescale 1 ns / 1 ps

module uart_to_axi_bridge #(
    parameter int AWIDTH           = 10,
    parameter int AXI_WADDR_WIDTH  = 13,
    parameter int AXI_RADDR_WIDTH  = 13,
    parameter int AXI_WDATA_DWIDTH = 80,
    parameter int AXI_RDATA_DWIDTH = 80
)(
    input  logic                          CLK,
    input  logic                          RST, // Active-low asynchronous reset

    // UART RX Interface
    input  logic [7:0]                    rx_data_i,
    input  logic                          rx_valid_i,

    // UART TX Interface
    output logic [7:0]                    tx_data_o,
    output logic                          tx_start_o,
    input  logic                          tx_busy_i,

    // AXI Master Write Interface
    output logic [AXI_WADDR_WIDTH-1:0]    axi_waddr_o,
    output logic [AXI_WDATA_DWIDTH-1:0]   axi_wdata_o,
    output logic                          axi_wvalid_o,

    // AXI Master Read Interface
    output logic [AXI_RADDR_WIDTH-1:0]    axi_raddr_o,
    output logic                          axi_arvalid_o,
    input  logic [AXI_RDATA_DWIDTH-1:0]   axi_rdata_i,

    // Bridge Status
    output logic                          bridge_active_o
);

    // RX FSM States
    typedef enum logic [3:0] {
        s_IDLE             = 4'd0,
        s_CMD              = 4'd1,
        s_LEN_H            = 4'd2,
        s_LEN_L            = 4'd3,
        s_PAYLOAD          = 4'd4,
        s_CHECKSUM         = 4'd5,
        s_ETX              = 4'd6,
        s_EXECUTE          = 4'd7,
        s_WAIT_READ        = 4'd8,
        s_WAIT_STATUS      = 4'd9,
        s_SEND_ACK         = 4'd10,
        s_SEND_NACK        = 4'd11,
        s_TX_PACKET        = 4'd12
    } rx_state_t;

    rx_state_t rx_state_r;

    // TX Packet FSM States
    typedef enum logic [3:0] {
        tx_IDLE      = 4'd0,
        tx_STX       = 4'd1,
        tx_CMD       = 4'd2,
        tx_LEN_H     = 4'd3,
        tx_LEN_L     = 4'd4,
        tx_PAYLOAD   = 4'd5,
        tx_CHECKSUM  = 4'd6,
        tx_ETX       = 4'd7,
        tx_WAIT_BUSY = 4'd8
    } tx_state_t;

    tx_state_t tx_state_r;
    tx_state_t tx_next_state_r;

    // Registers for RX Packet parsing
    logic [7:0]  cmd_r;
    logic [15:0] len_r;
    logic [7:0]  payload_r [0:15];
    logic [15:0] pld_idx_r;
    logic [7:0]  chk_sum_r;
    logic [7:0]  expected_chk_sum_r;

    // AXI control registers
    logic [AXI_WADDR_WIDTH-1:0]  axi_waddr_r;
    logic [AXI_WDATA_DWIDTH-1:0] axi_wdata_r;
    logic                        axi_wvalid_r;
    logic [AXI_RADDR_WIDTH-1:0]  axi_raddr_r;
    logic                        axi_arvalid_r;

    assign axi_waddr_o   = axi_waddr_r;
    assign axi_wdata_o   = axi_wdata_r;
    assign axi_wvalid_o  = axi_wvalid_r;
    assign axi_raddr_o   = axi_raddr_r;
    assign axi_arvalid_o = axi_arvalid_r;

    assign bridge_active_o = (rx_state_r != s_IDLE);

    wire [15:0] parsed_addr_w = {payload_r[0], payload_r[1]};

    // TX Packet registers
    logic [7:0]  tx_cmd_r;
    logic [15:0] tx_len_r;
    logic [7:0]  tx_payload_r [0:15];
    logic [15:0] tx_pld_idx_r;
    logic [7:0]  tx_chk_sum_r;

    logic [7:0]  tx_data_r;
    logic        tx_start_r;

    assign tx_data_o  = tx_data_r;
    assign tx_start_o = tx_start_r;

    // RX Packet Parsing FSM
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            rx_state_r          <= s_IDLE;
            cmd_r               <= 8'd0;
            len_r               <= 16'd0;
            pld_idx_r           <= 16'd0;
            chk_sum_r           <= 8'd0;
            expected_chk_sum_r  <= 8'd0;
            axi_waddr_r         <= {AXI_WADDR_WIDTH{1'b0}};
            axi_wdata_r         <= {AXI_WDATA_DWIDTH{1'b0}};
            axi_wvalid_r        <= 1'b0;
            axi_raddr_r         <= {AXI_RADDR_WIDTH{1'b0}};
            axi_arvalid_r       <= 1'b0;
            for (int i = 0; i < 16; i++) begin
                payload_r[i]    <= 8'd0;
            end
        end else begin
            axi_wvalid_r  <= 1'b0;
            axi_arvalid_r <= 1'b0;

            case (rx_state_r)
                s_IDLE: begin
                    if (rx_valid_i && rx_data_i == 8'h02) begin // STX
                        chk_sum_r <= 8'd0;
                        pld_idx_r <= 16'd0;
                        rx_state_r <= s_CMD;
                    end
                end

                s_CMD: begin
                    if (rx_valid_i) begin
                        cmd_r      <= rx_data_i;
                        chk_sum_r  <= chk_sum_r ^ rx_data_i;
                        rx_state_r <= s_LEN_H;
                    end
                end

                s_LEN_H: begin
                    if (rx_valid_i) begin
                        len_r[15:8] <= rx_data_i;
                        chk_sum_r   <= chk_sum_r ^ rx_data_i;
                        rx_state_r  <= s_LEN_L;
                    end
                end

                s_LEN_L: begin
                    if (rx_valid_i) begin
                        len_r[7:0] <= rx_data_i;
                        chk_sum_r  <= chk_sum_r ^ rx_data_i;
                        
                        // Parse length logic
                        if ({len_r[15:8], rx_data_i} == 16'd0) begin
                            rx_state_r <= s_CHECKSUM;
                        end else begin
                            rx_state_r <= s_PAYLOAD;
                        end
                    end
                end

                s_PAYLOAD: begin
                    if (rx_valid_i) begin
                        if (pld_idx_r < 16'd16) begin
                            payload_r[pld_idx_r[3:0]] <= rx_data_i;
                        end
                        chk_sum_r <= chk_sum_r ^ rx_data_i;
                        
                        if (pld_idx_r == len_r - 16'd1) begin
                            rx_state_r <= s_CHECKSUM;
                        end else begin
                            pld_idx_r <= pld_idx_r + 16'd1;
                        end
                    end
                end

                s_CHECKSUM: begin
                    if (rx_valid_i) begin
                        expected_chk_sum_r <= rx_data_i;
                        rx_state_r         <= s_ETX;
                    end
                end

                s_ETX: begin
                    if (rx_valid_i) begin
                        if (rx_data_i == 8'h03 && chk_sum_r == expected_chk_sum_r) begin
                            rx_state_r <= s_EXECUTE;
                        end else begin
                            rx_state_r <= s_SEND_NACK;
                        end
                    end
                end

                s_EXECUTE: begin
                    case (cmd_r)
                        8'h01: begin // WRITE_MEM
                            // payload[0:1] = address
                            // payload[2:11] = 80-bit data
                            axi_waddr_r  <= parsed_addr_w[AXI_WADDR_WIDTH-1:0];
                            axi_wdata_r  <= {payload_r[2], payload_r[3], payload_r[4], payload_r[5], 
                                             payload_r[6], payload_r[7], payload_r[8], payload_r[9], 
                                             payload_r[10], payload_r[11]};
                            axi_wvalid_r <= 1'b1;
                            rx_state_r   <= s_SEND_ACK;
                        end
                        
                        8'h02: begin // READ_MEM
                            axi_raddr_r   <= parsed_addr_w[AXI_RADDR_WIDTH-1:0];
                            axi_arvalid_r <= 1'b1;
                            rx_state_r    <= s_WAIT_READ;
                        end

                        8'h03: begin // START_INFERENCE
                            axi_waddr_r  <= 13'h0400; // AXI_WADDR_START << 10
                            axi_wdata_r  <= 80'h1;
                            axi_wvalid_r <= 1'b1;
                            rx_state_r   <= s_SEND_ACK;
                        end

                        8'h04: begin // CHECK_STATUS
                            axi_raddr_r   <= 13'h0C00; // AXI_RADDR_STATE << 10
                            axi_arvalid_r <= 1'b1;
                            rx_state_r    <= s_WAIT_STATUS;
                        end

                        default: begin
                            rx_state_r <= s_SEND_NACK;
                        end
                    endcase
                end

                s_WAIT_READ: begin
                    // Read data is available from AXI on this cycle
                    tx_cmd_r           <= 8'h02;
                    tx_len_r           <= 16'd10;
                    tx_payload_r[0]    <= axi_rdata_i[79:72];
                    tx_payload_r[1]    <= axi_rdata_i[71:64];
                    tx_payload_r[2]    <= axi_rdata_i[63:56];
                    tx_payload_r[3]    <= axi_rdata_i[55:48];
                    tx_payload_r[4]    <= axi_rdata_i[47:40];
                    tx_payload_r[5]    <= axi_rdata_i[39:32];
                    tx_payload_r[6]    <= axi_rdata_i[31:24];
                    tx_payload_r[7]    <= axi_rdata_i[23:16];
                    tx_payload_r[8]    <= axi_rdata_i[15:8];
                    tx_payload_r[9]    <= axi_rdata_i[7:0];
                    rx_state_r         <= s_TX_PACKET;
                end

                s_WAIT_STATUS: begin
                    tx_cmd_r           <= 8'h04;
                    tx_len_r           <= 16'd1;
                    tx_payload_r[0]    <= axi_rdata_i[7:0]; // Controller State
                    rx_state_r         <= s_TX_PACKET;
                end

                s_SEND_ACK: begin
                    if (tx_state_r == tx_IDLE && !tx_busy_i) begin
                        rx_state_r <= s_IDLE;
                    end
                end

                s_SEND_NACK: begin
                    if (tx_state_r == tx_IDLE && !tx_busy_i) begin
                        rx_state_r <= s_IDLE;
                    end
                end

                s_TX_PACKET: begin
                    if (tx_state_r == tx_IDLE && !tx_busy_i) begin
                        rx_state_r <= s_IDLE;
                    end
                end

                default: rx_state_r <= s_IDLE;
            endcase
        end
    end

    // TX Packet / Simple ACK Response FSM
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            tx_state_r      <= tx_IDLE;
            tx_next_state_r <= tx_IDLE;
            tx_pld_idx_r    <= 16'd0;
            tx_chk_sum_r    <= 8'd0;
            tx_data_r       <= 8'd0;
            tx_start_r      <= 1'b0;
        end else begin
            tx_start_r <= 1'b0; // default pulse

            case (tx_state_r)
                tx_IDLE: begin
                    tx_pld_idx_r <= 16'd0;
                    tx_chk_sum_r <= 8'd0;
                    
                    if (rx_state_r == s_SEND_ACK && !tx_busy_i) begin
                        tx_data_r  <= 8'h06; // ACK byte
                        tx_start_r <= 1'b1;
                        tx_state_r <= tx_WAIT_BUSY;
                        tx_next_state_r <= tx_IDLE;
                    end else if (rx_state_r == s_SEND_NACK && !tx_busy_i) begin
                        tx_data_r  <= 8'h15; // NACK byte
                        tx_start_r <= 1'b1;
                        tx_state_r <= tx_WAIT_BUSY;
                        tx_next_state_r <= tx_IDLE;
                    end else if (rx_state_r == s_TX_PACKET && !tx_busy_i) begin
                        tx_data_r  <= 8'h02; // STX
                        tx_start_r <= 1'b1;
                        tx_state_r <= tx_WAIT_BUSY;
                        tx_next_state_r <= tx_STX;
                    end
                end

                tx_STX: begin
                    if (!tx_busy_i) begin
                        tx_data_r    <= tx_cmd_r;
                        tx_start_r   <= 1'b1;
                        tx_chk_sum_r <= tx_cmd_r;
                        tx_state_r   <= tx_WAIT_BUSY;
                        tx_next_state_r   <= tx_CMD;
                    end
                end

                tx_CMD: begin
                    if (!tx_busy_i) begin
                        tx_data_r    <= tx_len_r[15:8];
                        tx_start_r   <= 1'b1;
                        tx_chk_sum_r <= tx_chk_sum_r ^ tx_len_r[15:8];
                        tx_state_r   <= tx_WAIT_BUSY;
                        tx_next_state_r   <= tx_LEN_H;
                    end
                end

                tx_LEN_H: begin
                    if (!tx_busy_i) begin
                        tx_data_r    <= tx_len_r[7:0];
                        tx_start_r   <= 1'b1;
                        tx_chk_sum_r <= tx_chk_sum_r ^ tx_len_r[7:0];
                        tx_state_r   <= tx_WAIT_BUSY;
                        tx_next_state_r   <= tx_LEN_L;
                    end
                end

                tx_LEN_L: begin
                    if (!tx_busy_i) begin
                        tx_data_r    <= tx_payload_r[0];
                        tx_start_r   <= 1'b1;
                        tx_chk_sum_r <= tx_chk_sum_r ^ tx_payload_r[0];
                        tx_state_r   <= tx_WAIT_BUSY;
                        if (tx_len_r == 16'd1) begin
                            tx_next_state_r <= tx_PAYLOAD;
                        end else begin
                            tx_pld_idx_r    <= 16'd1;
                            tx_next_state_r <= tx_LEN_L; // repeat this state with incremented index
                        end
                    end
                end

                // Note: tx_LEN_L is used for looping through payloads to reuse code,
                // and transitions to tx_PAYLOAD when done.
                // We use tx_PAYLOAD as the state after all payload bytes have been loaded.
                tx_PAYLOAD: begin
                    // All payload bytes sent. Send checksum.
                    if (!tx_busy_i) begin
                        tx_data_r  <= tx_chk_sum_r;
                        tx_start_r <= 1'b1;
                        tx_state_r <= tx_WAIT_BUSY;
                        tx_next_state_r <= tx_CHECKSUM;
                    end
                end

                tx_CHECKSUM: begin
                    if (!tx_busy_i) begin
                        tx_data_r  <= 8'h03; // ETX
                        tx_start_r <= 1'b1;
                        tx_state_r <= tx_WAIT_BUSY;
                        tx_next_state_r <= tx_ETX;
                    end
                end

                tx_ETX: begin
                    if (!tx_busy_i) begin
                        tx_state_r <= tx_IDLE;
                    end
                end

                tx_WAIT_BUSY: begin
                    // Wait for tx_busy_i to assert (start of transmission) then fall (end)
                    if (tx_busy_i) begin
                        // Stay here, wait for busy to go low
                    end else begin
                        // Busy is low, transition to next state
                        if (tx_next_state_r == tx_LEN_L && tx_pld_idx_r < tx_len_r) begin
                            // Continue sending payload
                            tx_data_r    <= tx_payload_r[tx_pld_idx_r[3:0]];
                            tx_start_r   <= 1'b1;
                            tx_chk_sum_r <= tx_chk_sum_r ^ tx_payload_r[tx_pld_idx_r[3:0]];
                            tx_pld_idx_r <= tx_pld_idx_r + 16'd1;
                            tx_state_r   <= tx_WAIT_BUSY;
                            if (tx_pld_idx_r == tx_len_r - 16'd1) begin
                                tx_next_state_r <= tx_PAYLOAD;
                            end else begin
                                tx_next_state_r <= tx_LEN_L;
                            end
                        end else begin
                            tx_state_r <= tx_next_state_r;
                        end
                    end
                end

                default: tx_state_r <= tx_IDLE;
            endcase
        end
    end

endmodule
