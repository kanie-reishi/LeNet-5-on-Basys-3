`timescale 1 ns / 1 ps

module argmax_unit #(
    parameter int AWIDTH           = 10,
    parameter int AXI_RADDR_WIDTH  = 13,
    parameter int AXI_RDATA_DWIDTH = 80
)(
    input  logic                          CLK,
    input  logic                          RST, // Active-low asynchronous reset
    input  logic                          inference_done_i, // High when controller is in s_READ state
    input  logic [AXI_RDATA_DWIDTH-1:0]   axi_rdata_i,
    output logic [AXI_RADDR_WIDTH-1:0]    axi_raddr_o,
    output logic                          axi_arvalid_o,
    output logic [3:0]                    predicted_digit_o,
    output logic                          predicted_valid_o,
    output logic                          argmax_busy_o
);

    // FSM States
    typedef enum logic [2:0] {
        s_IDLE     = 3'd0,
        s_READ_0   = 3'd1,
        s_WAIT_0   = 3'd2,
        s_READ_1   = 3'd3,
        s_WAIT_1   = 3'd4,
        s_COMPUTE  = 3'd5
    } state_t;

    state_t state_r;

    // Registers to store the 10 logits (each is a 16-bit signed integer)
    logic signed [15:0] logits_r [0:9];

    // Control output registers
    logic [AXI_RADDR_WIDTH-1:0] axi_raddr_r;
    logic                       axi_arvalid_r;
    logic [3:0]                 predicted_digit_r;
    logic                       predicted_valid_r;

    assign axi_raddr_o       = axi_raddr_r;
    assign axi_arvalid_o     = axi_arvalid_r;
    assign predicted_digit_o = predicted_digit_r;
    assign predicted_valid_o = predicted_valid_r;
    assign argmax_busy_o     = (state_r != s_IDLE);

    // Detect rising edge of inference_done_i
    logic inference_done_d_r;
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            inference_done_d_r <= 1'b0;
        end else begin
            inference_done_d_r <= inference_done_i;
        end
    end
    wire start_w = inference_done_i && !inference_done_d_r;

    // FSM Logic
    always_ff @(posedge CLK or negedge RST) begin
        if (!RST) begin
            state_r           <= s_IDLE;
            axi_raddr_r       <= {AXI_RADDR_WIDTH{1'b0}};
            axi_arvalid_r     <= 1'b0;
            predicted_digit_r <= 4'd0;
            predicted_valid_r <= 1'b0;
            for (int i = 0; i < 10; i++) begin
                logits_r[i] <= 16'sd0;
            end
        end else begin
            axi_arvalid_r <= 1'b0; // default pulse

            case (state_r)
                s_IDLE: begin
                    if (start_w) begin
                        predicted_valid_r <= 1'b0;
                        state_r           <= s_READ_0;
                    end
                end

                s_READ_0: begin
                    // Address: block 2 (Pong FM), offset 0
                    axi_raddr_r   <= {3'd2, {AWIDTH{1'b0}}};
                    axi_arvalid_r <= 1'b1;
                    state_r       <= s_WAIT_0;
                end

                s_WAIT_0: begin
                    // Read data is valid at the end of this cycle
                    logits_r[0] <= $signed(axi_rdata_i[15:0]);
                    logits_r[1] <= $signed(axi_rdata_i[31:16]);
                    logits_r[2] <= $signed(axi_rdata_i[47:32]);
                    logits_r[3] <= $signed(axi_rdata_i[63:48]);
                    logits_r[4] <= $signed(axi_rdata_i[79:64]);
                    state_r     <= s_READ_1;
                end

                s_READ_1: begin
                    // Address: block 2 (Pong FM), offset 1
                    axi_raddr_r   <= {3'd2, 10'd1};
                    axi_arvalid_r <= 1'b1;
                    state_r       <= s_WAIT_1;
                end

                s_WAIT_1: begin
                    logits_r[5] <= $signed(axi_rdata_i[15:0]);
                    logits_r[6] <= $signed(axi_rdata_i[31:16]);
                    logits_r[7] <= $signed(axi_rdata_i[47:32]);
                    logits_r[8] <= $signed(axi_rdata_i[63:48]);
                    logits_r[9] <= $signed(axi_rdata_i[79:64]);
                    state_r     <= s_COMPUTE;
                end

                s_COMPUTE: begin
                    // Combinatorial Argmax
                    logic signed [15:0] max_val;
                    logic [3:0]         max_idx;
                    max_val = logits_r[0];
                    max_idx = 4'd0;
                    
                    for (int i = 1; i < 10; i++) begin
                        if (logits_r[i] > max_val) begin
                            max_val = logits_r[i];
                            max_idx = i[3:0];
                        end
                    end

                    predicted_digit_r <= max_idx;
                    predicted_valid_r <= 1'b1;
                    state_r           <= s_IDLE;
                end

                default: state_r <= s_IDLE;
            endcase
        end
    end

endmodule
