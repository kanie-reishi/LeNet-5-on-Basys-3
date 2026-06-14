`timescale 1 ns / 1 ps

module top_level #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115200
)(
    input  logic       CLK,     // 100 MHz oscillator pin W5
    input  logic       btnC,    // Center button for reset (active-high)
    input  logic       RsRx,    // UART RX pin B18
    output logic       RsTx,    // UART TX pin A18
    output logic [6:0] seg,     // 7-segment cathode segments (active-low)
    output logic       dp,      // Decimal point (active-low)
    output logic [3:0] an       // Digit anodes (active-low)
);

    // Active-low internal reset
    wire rst_n = ~btnC;

    //================================================================//
    // UART signals
    //================================================================//
    wire [7:0] rx_data_w;
    wire       rx_valid_w;
    wire [7:0] tx_data_w;
    wire       tx_start_w;
    wire       tx_busy_w;

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_rx (
        .CLK(CLK),
        .RST(rst_n),
        .rxd_i(RsRx),
        .rx_data_o(rx_data_w),
        .rx_valid_o(rx_valid_w)
    );

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .CLK(CLK),
        .RST(rst_n),
        .tx_data_i(tx_data_w),
        .tx_start_i(tx_start_w),
        .txd_o(RsTx),
        .tx_busy_o(tx_busy_w)
    );

    //================================================================//
    // AXI Bus sharing between UART Bridge and Argmax Unit
    //================================================================//
    wire [12:0] bridge_axi_waddr_w;
    wire [79:0] bridge_axi_wdata_w;
    wire        bridge_axi_wvalid_w;

    wire [12:0] bridge_axi_raddr_w;
    wire        bridge_axi_arvalid_w;

    wire [12:0] argmax_axi_raddr_w;
    wire        argmax_axi_arvalid_w;
    wire        argmax_busy_w;

    // AXI signals to CNN Core
    wire [12:0] core_axi_waddr_w;
    wire [79:0] core_axi_wdata_w;
    wire        core_axi_wvalid_w;

    wire [12:0] core_axi_raddr_w;
    wire        core_axi_arvalid_w;
    wire [79:0] core_axi_rdata_w;

    // Multiplexer logic for AXI Read Sharing
    assign core_axi_raddr_w   = argmax_busy_w ? argmax_axi_raddr_w   : bridge_axi_raddr_w;
    assign core_axi_arvalid_w = argmax_busy_w ? argmax_axi_arvalid_w : bridge_axi_arvalid_w;

    // Direct write routing from bridge
    assign core_axi_waddr_w   = bridge_axi_waddr_w;
    assign core_axi_wdata_w   = bridge_axi_wdata_w;
    assign core_axi_wvalid_w  = bridge_axi_wvalid_w;

    uart_to_axi_bridge #(
        .AWIDTH(10),
        .AXI_WADDR_WIDTH(13),
        .AXI_RADDR_WIDTH(13),
        .AXI_WDATA_DWIDTH(80),
        .AXI_RDATA_DWIDTH(80)
    ) u_uart_to_axi_bridge (
        .CLK(CLK),
        .RST(rst_n),
        .rx_data_i(rx_data_w),
        .rx_valid_i(rx_valid_w),
        .tx_data_o(tx_data_w),
        .tx_start_o(tx_start_w),
        .tx_busy_i(tx_busy_w),
        .axi_waddr_o(bridge_axi_waddr_w),
        .axi_wdata_o(bridge_axi_wdata_w),
        .axi_wvalid_o(bridge_axi_wvalid_w),
        .axi_raddr_o(bridge_axi_raddr_w),
        .axi_arvalid_o(bridge_axi_arvalid_w),
        .axi_rdata_i(core_axi_rdata_w),
        .bridge_active_o()
    );

    //================================================================//
    // CNN Core
    //================================================================//
    wire [2:0] cnn_state_w;
    wire       cnn_complete_w;

    cnn_core #(
        .AWIDTH(10),
        .DWIDTH(16),
        .INST_DWIDTH(64),
        .AXI_WADDR_WIDTH(13),
        .AXI_RADDR_WIDTH(13),
        .AXI_WDATA_DWIDTH(80),
        .AXI_RDATA_DWIDTH(80),
        .FRAC_BITS(8)
    ) u_cnn_core (
        .CLK(CLK),
        .RST(rst_n),
        .axi_waddr_i(core_axi_waddr_w),
        .axi_wdata_i(core_axi_wdata_w),
        .axi_wvalid_i(core_axi_wvalid_w),
        .axi_raddr_i(core_axi_raddr_w),
        .axi_arvalid_i(core_axi_arvalid_w),
        .axi_rdata_o(core_axi_rdata_w)
    );

    // Connect CNN state wires
    assign cnn_state_w    = u_cnn_core.state_w;
    assign cnn_complete_w = u_cnn_core.complete_w;

    //================================================================//
    // Argmax Logic
    //================================================================//
    wire [3:0] predicted_digit_w;
    wire       predicted_valid_w;

    argmax_unit #(
        .AWIDTH(10),
        .AXI_RADDR_WIDTH(13),
        .AXI_RDATA_DWIDTH(80)
    ) u_argmax_unit (
        .CLK(CLK),
        .RST(rst_n),
        .inference_done_i(cnn_complete_w),
        .axi_rdata_i(core_axi_rdata_w),
        .axi_raddr_o(argmax_axi_raddr_w),
        .axi_arvalid_o(argmax_axi_arvalid_w),
        .predicted_digit_o(predicted_digit_w),
        .predicted_valid_o(predicted_valid_w),
        .argmax_busy_o(argmax_busy_w)
    );

    //================================================================//
    // Seven Segment Display
    //================================================================//
    seven_segment_controller u_seven_segment_controller (
        .CLK(CLK),
        .RST(rst_n),
        .state_i(cnn_state_w),
        .predicted_digit_i(predicted_digit_w),
        .predicted_valid_i(predicted_valid_w),
        .seg_o(seg),
        .dp_o(dp),
        .an_o(an)
    );

endmodule
