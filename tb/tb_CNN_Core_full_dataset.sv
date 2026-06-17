`timescale 1 ns / 1 ps

module tb_CNN_Core_full_dataset;

    parameter MEM_AWIDTH          = 16;
    parameter AXI_WORD_ADDR_WIDTH = 17;
    parameter AXI_ADDR_WIDTH      = AXI_WORD_ADDR_WIDTH + 3;
    parameter AXI_DATA_DWIDTH     = 16;
    parameter DWIDTH              = 16;
    parameter NBANKS              = 5;
    parameter TOTAL_DWIDTH        = NBANKS * DWIDTH;

    // Default to 20 samples for fast simulation; change to 10000 for full MNIST test set.
    parameter NUM_SAMPLES         = 100;
    parameter TIMEOUT_CYCLES      = 300000;
    parameter PROGRESS_EVERY      = 10;      // print every sample; set 100 for less log

    parameter [8*512-1:0] INPUT_ROWS_FILE = "fixed_q16_params/mnist_test_inputs_q16_rows.txt";
    parameter [8*512-1:0] LABEL_FILE      = "fixed_q16_params/mnist_test_labels.txt";

    localparam [2:0] W_LOAD_CTRL = 3'd0;
    localparam [2:0] W_START     = 3'd1;
    localparam [2:0] W_DONE_CLR  = 3'd2;
    localparam [2:0] W_PING_FM   = 3'd3;
    localparam [2:0] W_PONG_FM   = 3'd4;
    localparam [2:0] W_WEIGHT    = 3'd5;
    localparam [2:0] W_BIAS      = 3'd6;

    localparam [2:0] R_STATUS    = 3'd0;

    localparam integer CONV1_W_BASE = 0;
    localparam integer CONV2_W_BASE = 200;
    localparam integer FC1_W_BASE   = 4200;
    localparam integer FC2_W_BASE   = 55400;
    localparam integer FC3_W_BASE   = 68840;

    localparam integer CONV1_B_BASE = 0;
    localparam integer CONV2_B_BASE = 8;
    localparam integer FC1_B_BASE   = 28;
    localparam integer FC2_B_BASE   = 156;
    localparam integer FC3_B_BASE   = 240;

    reg CLK;
    reg RST;

    reg  [AXI_ADDR_WIDTH-1:0]  axi_waddr_i;
    reg  [AXI_DATA_DWIDTH-1:0] axi_wdata_i;
    reg                        axi_wvalid_i;

    reg  [AXI_ADDR_WIDTH-1:0]  axi_raddr_i;
    reg                        axi_arvalid_i;
    wire [AXI_DATA_DWIDTH-1:0] axi_rdata_o;

    wire                       predict_valid_o;
    wire [3:0]                 predict_value_o;
    wire [2:0]                 state_o;
    wire                       done_o;

    reg [15:0] sample_pixels [0:783];

    integer i;
    integer j;
    integer fd_input;
    integer fd_label;
    integer fd;
    integer code;
    integer val;
    integer addr;
    integer sample_idx;
    integer timeout_idx;
    integer label;
    integer pred;
    integer current_correct;
    integer acc_int;
    integer acc_frac;
    integer total_correct;
    integer total_count;

    integer label_total [0:9];
    integer label_correct [0:9];

    reg [8*256-1:0] line_r;

    cnn_core #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_DWIDTH(AXI_DATA_DWIDTH),
        .AWIDTH(MEM_AWIDTH),
        .DWIDTH(DWIDTH),
        .NBANKS(NBANKS)
    ) dut (
        .CLK(CLK),
        .RST(RST),
        .axi_waddr_i(axi_waddr_i),
        .axi_wdata_i(axi_wdata_i),
        .axi_wvalid_i(axi_wvalid_i),
        .axi_raddr_i(axi_raddr_i),
        .axi_arvalid_i(axi_arvalid_i),
        .axi_rdata_o(axi_rdata_o),
        .predict_valid_o(predict_valid_o),
        .predict_value_o(predict_value_o),
        .state_o(state_o),
        .done_o(done_o)
    );

    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    task axi_write;
        input [2:0] sel_i;
        input [AXI_WORD_ADDR_WIDTH-1:0] addr_i;
        input [AXI_DATA_DWIDTH-1:0] data_i;
        begin
            @(negedge CLK);
            axi_waddr_i  = {sel_i, addr_i};
            axi_wdata_i  = data_i;
            axi_wvalid_i = 1'b1;
            @(posedge CLK);
            #1;
            @(negedge CLK);
            axi_wvalid_i = 1'b0;
            axi_waddr_i  = {AXI_ADDR_WIDTH{1'b0}};
            axi_wdata_i  = {AXI_DATA_DWIDTH{1'b0}};
        end
    endtask

    task axi_read;
        input [2:0] sel_i;
        input [AXI_WORD_ADDR_WIDTH-1:0] addr_i;
        begin
            @(negedge CLK);
            axi_raddr_i   = {sel_i, addr_i};
            axi_arvalid_i = 1'b1;
            @(posedge CLK);
            #1;
            @(negedge CLK);
            axi_arvalid_i = 1'b0;
        end
    endtask

    task load_bias_file;
        input [8*384-1:0] file_name_i;
        input integer base_addr_i;
        begin
            fd = $fopen(file_name_i, "r");
            if (fd == 0) begin
                $display("[FATAL] cannot open %0s", file_name_i);
                $finish;
            end
            else begin
                addr = base_addr_i;
                while ($fgets(line_r, fd)) begin
                    code = $sscanf(line_r, "%h", val);
                    if (code == 1) begin
                        axi_write(W_BIAS, addr[AXI_WORD_ADDR_WIDTH-1:0], val[15:0]);
                        addr = addr + 1;
                    end
                end
                $fclose(fd);
                $display("[INFO] loaded bias file %0s, count=%0d", file_name_i, addr - base_addr_i);
            end
        end
    endtask

    task load_conv_weight_file;
        input [8*384-1:0] file_name_i;
        input integer base_addr_i;
        input integer out_ch_i;
        input integer in_ch_i;
        input integer kernel_i;
        integer oc;
        integer ic;
        integer ky;
        integer kx;
        integer weight_addr;
        begin
            fd = $fopen(file_name_i, "r");
            if (fd == 0) begin
                $display("[FATAL] cannot open %0s", file_name_i);
                $finish;
            end
            else begin
                for (oc = 0; oc < out_ch_i; oc = oc + 1) begin
                    for (ic = 0; ic < in_ch_i; ic = ic + 1) begin
                        for (ky = 0; ky < kernel_i; ky = ky + 1) begin
                            for (kx = 0; kx < kernel_i; kx = kx + 1) begin
                                code = 0;
                                while ((code != 1) && !$feof(fd)) begin
                                    code = $fgets(line_r, fd);
                                    if (code != 0) begin
                                        code = $sscanf(line_r, "%h", val);
                                    end
                                end
                                if (code == 1) begin
                                    weight_addr = base_addr_i + (((oc * in_ch_i + ic) * kernel_i * kernel_i) + (ky * kernel_i) + kx);
                                    axi_write(W_WEIGHT, weight_addr[AXI_WORD_ADDR_WIDTH-1:0], val[15:0]);
                                end
                                else begin
                                    $display("[FATAL] unexpected EOF in conv weight file %0s", file_name_i);
                                    $finish;
                                end
                            end
                        end
                    end
                end
                $fclose(fd);
                $display("[INFO] loaded conv weight file %0s", file_name_i);
            end
        end
    endtask

    task load_fc1_weight_file;
        input [8*384-1:0] file_name_i;
        input integer base_addr_i;
        input integer out_len_i;
        input integer in_len_i;
        integer o;
        integer chunk;
        integer bank;
        integer ii;
        integer block_base;
        integer local_col;
        integer weight_addr;
        integer packed_addr;
        integer chunk_count;
        integer weight_count;
        integer expect_count;
        reg [15:0] fc_weight_mem [0:65535];
        begin
            fd = $fopen(file_name_i, "r");
            if (fd == 0) begin
                $display("[FATAL] cannot open %0s", file_name_i);
                $finish;
            end
            else begin
                weight_count = 0;
                while ($fgets(line_r, fd)) begin
                    code = $sscanf(line_r, "%h", val);
                    if (code == 1) begin
                        fc_weight_mem[weight_count] = val[15:0];
                        weight_count = weight_count + 1;
                    end
                end
                $fclose(fd);
                expect_count = out_len_i * in_len_i;
                if (weight_count < expect_count) begin
                    $display("[FATAL] fc1 weight file %0s has only %0d values, expected %0d", file_name_i, weight_count, expect_count);
                    $finish;
                end
                chunk_count = (in_len_i + 3) / 4;
                for (o = 0; o < out_len_i; o = o + 1) begin
                    for (chunk = 0; chunk < chunk_count; chunk = chunk + 1) begin
                        packed_addr = (base_addr_i / NBANKS) + (o * chunk_count) + chunk;
                        block_base  = (chunk / 4) * 16;
                        local_col   = chunk % 4;
                        for (bank = 0; bank < 4; bank = bank + 1) begin
                            ii = block_base + (bank * 4) + local_col;
                            weight_addr = (packed_addr * NBANKS) + bank;
                            if (ii < in_len_i) begin
                                axi_write(W_WEIGHT, weight_addr[AXI_WORD_ADDR_WIDTH-1:0], fc_weight_mem[(o * in_len_i) + ii]);
                            end
                            else begin
                                axi_write(W_WEIGHT, weight_addr[AXI_WORD_ADDR_WIDTH-1:0], {AXI_DATA_DWIDTH{1'b0}});
                            end
                        end
                        weight_addr = (packed_addr * NBANKS) + 4;
                        axi_write(W_WEIGHT, weight_addr[AXI_WORD_ADDR_WIDTH-1:0], {AXI_DATA_DWIDTH{1'b0}});
                    end
                end
                $display("[INFO] loaded fc1 block16-transposed weight file %0s, count=%0d", file_name_i, weight_count);
            end
        end
    endtask

    task load_fc_linear_weight_file;
        input [8*384-1:0] file_name_i;
        input integer base_addr_i;
        input integer out_len_i;
        input integer in_len_i;
        integer o;
        integer chunk;
        integer bank;
        integer ii;
        integer weight_addr;
        integer packed_addr;
        integer chunk_count;
        integer weight_count;
        integer expect_count;
        reg [15:0] fc_weight_mem [0:65535];
        begin
            fd = $fopen(file_name_i, "r");
            if (fd == 0) begin
                $display("[FATAL] cannot open %0s", file_name_i);
                $finish;
            end
            else begin
                weight_count = 0;
                while ($fgets(line_r, fd)) begin
                    code = $sscanf(line_r, "%h", val);
                    if (code == 1) begin
                        fc_weight_mem[weight_count] = val[15:0];
                        weight_count = weight_count + 1;
                    end
                end
                $fclose(fd);
                expect_count = out_len_i * in_len_i;
                if (weight_count < expect_count) begin
                    $display("[FATAL] fc linear weight file %0s has only %0d values, expected %0d", file_name_i, weight_count, expect_count);
                    $finish;
                end
                chunk_count = (in_len_i + 3) / 4;
                for (o = 0; o < out_len_i; o = o + 1) begin
                    for (chunk = 0; chunk < chunk_count; chunk = chunk + 1) begin
                        packed_addr = (base_addr_i / NBANKS) + (o * chunk_count) + chunk;
                        for (bank = 0; bank < 4; bank = bank + 1) begin
                            ii = (chunk * 4) + bank;
                            weight_addr = (packed_addr * NBANKS) + bank;
                            if (ii < in_len_i) begin
                                axi_write(W_WEIGHT, weight_addr[AXI_WORD_ADDR_WIDTH-1:0], fc_weight_mem[(o * in_len_i) + ii]);
                            end
                            else begin
                                axi_write(W_WEIGHT, weight_addr[AXI_WORD_ADDR_WIDTH-1:0], {AXI_DATA_DWIDTH{1'b0}});
                            end
                        end
                        weight_addr = (packed_addr * NBANKS) + 4;
                        axi_write(W_WEIGHT, weight_addr[AXI_WORD_ADDR_WIDTH-1:0], {AXI_DATA_DWIDTH{1'b0}});
                    end
                end
                $display("[INFO] loaded fc linear weight file %0s, count=%0d", file_name_i, weight_count);
            end
        end
    endtask

    task load_one_input_to_ping_from_sample_mem;
        input integer height_i;
        input integer width_i;
        integer bank_idx;
        integer row_block_idx;
        integer row_idx;
        integer col_idx;
        integer bank_depth;
        integer axi_addr;
        integer pixel_idx;
        begin
            bank_depth = ((height_i + NBANKS - 1) / NBANKS) * width_i;
            for (addr = 0; addr < bank_depth; addr = addr + 1) begin
                row_block_idx = addr / width_i;
                col_idx       = addr % width_i;
                for (bank_idx = 0; bank_idx < NBANKS; bank_idx = bank_idx + 1) begin
                    row_idx   = (row_block_idx * NBANKS) + bank_idx;
                    axi_addr  = (addr * NBANKS) + bank_idx;
                    pixel_idx = (row_idx * width_i) + col_idx;
                    if (row_idx < height_i) begin
                        axi_write(W_PING_FM, axi_addr[AXI_WORD_ADDR_WIDTH-1:0], sample_pixels[pixel_idx]);
                    end
                    else begin
                        axi_write(W_PING_FM, axi_addr[AXI_WORD_ADDR_WIDTH-1:0], {AXI_DATA_DWIDTH{1'b0}});
                    end
                end
            end
        end
    endtask

    task read_next_sample;
        output integer ok_o;
        integer p;
        integer rc;
        begin
            ok_o = 1;
            for (p = 0; p < 784; p = p + 1) begin
                rc = $fscanf(fd_input, "%h", val);
                if (rc != 1) begin
                    ok_o = 0;
                    sample_pixels[p] = 16'd0;
                end
                else begin
                    sample_pixels[p] = val[15:0];
                end
            end
            rc = $fscanf(fd_label, "%d", label);
            if (rc != 1) begin
                ok_o = 0;
                label = 0;
            end
        end
    endtask

    task load_all_weights_and_biases_once;
        begin
            load_bias_file("fixed_q16_params/conv1_bias_q16.txt", CONV1_B_BASE);
            load_conv_weight_file("fixed_q16_params/conv1_weight_q16.txt", CONV1_W_BASE, 8, 1, 5);
            load_bias_file("fixed_q16_params/conv2_bias_q16.txt", CONV2_B_BASE);
            load_conv_weight_file("fixed_q16_params/conv2_weight_q16.txt", CONV2_W_BASE, 20, 8, 5);
            load_bias_file("fixed_q16_params/fc1_bias_q16.txt", FC1_B_BASE);
            load_fc1_weight_file("fixed_q16_params/fc1_weight_q16.txt", FC1_W_BASE, 128, 320);
            load_bias_file("fixed_q16_params/fc2_bias_q16.txt", FC2_B_BASE);
            load_fc_linear_weight_file("fixed_q16_params/fc2_weight_q16.txt", FC2_W_BASE, 84, 128);
            load_bias_file("fixed_q16_params/fc3_bias_q16.txt", FC3_B_BASE);
            load_fc_linear_weight_file("fixed_q16_params/fc3_weight_q16.txt", FC3_W_BASE, 10, 84);
        end
    endtask

    initial begin
        RST           = 1'b0;
        axi_waddr_i   = {AXI_ADDR_WIDTH{1'b0}};
        axi_wdata_i   = {AXI_DATA_DWIDTH{1'b0}};
        axi_wvalid_i  = 1'b0;
        axi_raddr_i   = {AXI_ADDR_WIDTH{1'b0}};
        axi_arvalid_i = 1'b0;

        total_correct = 0;
        total_count   = 0;
        for (i = 0; i < 10; i = i + 1) begin
            label_total[i]   = 0;
            label_correct[i] = 0;
        end

        repeat (5) @(posedge CLK);
        @(negedge CLK);
        RST = 1'b1;

        fd_input = $fopen(INPUT_ROWS_FILE, "r");
        if (fd_input == 0) begin
            $display("[FATAL] cannot open input rows file %0s", INPUT_ROWS_FILE);
            $finish;
        end
        fd_label = $fopen(LABEL_FILE, "r");
        if (fd_label == 0) begin
            $display("[FATAL] cannot open label file %0s", LABEL_FILE);
            $finish;
        end

        load_all_weights_and_biases_once();

        $display("[INFO] start full dataset test NUM_SAMPLES=%0d PROGRESS_EVERY=%0d", NUM_SAMPLES, PROGRESS_EVERY);

        for (sample_idx = 0; sample_idx < NUM_SAMPLES; sample_idx = sample_idx + 1) begin
            read_next_sample(code);
            if (code != 1) begin
                $display("[WARN] stopped early at sample %0d because input/label file ended", sample_idx);
                sample_idx = NUM_SAMPLES;
            end
            else begin
                axi_write(W_DONE_CLR, 0, 16'd1);
                load_one_input_to_ping_from_sample_mem(28, 28);
                axi_write(W_LOAD_CTRL, 0, 16'd1);
                axi_write(W_START,     0, 16'd1);

                pred = 0;
                for (timeout_idx = 0; timeout_idx < TIMEOUT_CYCLES; timeout_idx = timeout_idx + 1) begin
                    axi_read(R_STATUS, 0);
                    if (axi_rdata_o[0]) begin
                        pred = axi_rdata_o[4:1];
                        timeout_idx = TIMEOUT_CYCLES;
                    end
                end

                if (!axi_rdata_o[0]) begin
                    total_count = total_count + 1;
                    if ((label >= 0) && (label < 10)) begin
                        label_total[label] = label_total[label] + 1;
                    end
                    acc_int  = (total_correct * 100) / total_count;
                    acc_frac = ((total_correct * 10000) / total_count) % 100;
                    $display("[PROGRESS] sample=%0d/%0d total_acc=%0d.%02d%% last_label=%0d last_pred=TIMEOUT correct=0",
                             sample_idx + 1,
                             NUM_SAMPLES,
                             acc_int,
                             acc_frac,
                             label);
                    $display("[FAIL] timeout sample=%0d label=%0d", sample_idx, label);
                end
                else begin
                    current_correct = (pred == label);

                    total_count = total_count + 1;
                    if ((label >= 0) && (label < 10)) begin
                        label_total[label] = label_total[label] + 1;
                    end

                    if (current_correct) begin
                        total_correct = total_correct + 1;
                        if ((label >= 0) && (label < 10)) begin
                            label_correct[label] = label_correct[label] + 1;
                        end
                    end

                    acc_int  = (total_correct * 100) / total_count;
                    acc_frac = ((total_correct * 10000) / total_count) % 100;

                    if ((PROGRESS_EVERY <= 1) || (((sample_idx + 1) % PROGRESS_EVERY) == 0) || ((sample_idx + 1) == NUM_SAMPLES)) begin
                        $display("[PROGRESS] sample=%0d/%0d total_acc=%0d.%02d%% last_label=%0d last_pred=%0d correct=%0d",
                                 sample_idx + 1,
                                 NUM_SAMPLES,
                                 acc_int,
                                 acc_frac,
                                 label,
                                 pred,
                                 current_correct);
                    end
                end
            end
        end

        $fclose(fd_input);
        $fclose(fd_label);

        $display("============================================================");
        if (total_count != 0) begin
            $display("[RESULT] total_correct=%0d total_count=%0d accuracy=%0d.%02d%%",
                     total_correct,
                     total_count,
                     (total_correct * 100) / total_count,
                     ((total_correct * 10000) / total_count) % 100);
        end
        else begin
            $display("[RESULT] total_correct=0 total_count=0 accuracy=N/A");
        end

        for (j = 0; j < 10; j = j + 1) begin
            if (label_total[j] != 0) begin
                $display("[RESULT] label %0d: correct=%0d total=%0d accuracy=%0d.%02d%%",
                         j,
                         label_correct[j],
                         label_total[j],
                         (label_correct[j] * 100) / label_total[j],
                         ((label_correct[j] * 10000) / label_total[j]) % 100);
            end
            else begin
                $display("[RESULT] label %0d: correct=0 total=0 accuracy=N/A", j);
            end
        end
        $display("============================================================");

        axi_write(W_DONE_CLR, 0, 16'd1);
        #50;
        $finish;
    end

endmodule
