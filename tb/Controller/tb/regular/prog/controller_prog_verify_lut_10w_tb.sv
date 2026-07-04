//------------------------------------------------------------------------------
// Compact Program-Verify TB (10 weights) for fast waveform bring-up.
// Covers: verify match (equal), read<expected (re-PROG), read>expected (ERASE->PROG),
// and idx5 forced ERASE-recovery looping until DUT raises erase_max_retries_exhausted.
//
// Note: ERASE max-retry give-up (retry_cnt) in RTL is not reachable in this direct-address flow because
// PROG_COMPLETE clears retry_cnt whenever buffer_idx_reg < weight_count_reg-1 (default 640), so erase
// retry never accumulates across PROG cycles. Waves still show retry_cnt / prog_retry_cnt from the DUT.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "rtl/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_prog_verify_lut_10w_tb;

    localparam int NUM_WEIGHTS   = 10;
    localparam int CLK_PERIOD    = 5;
    localparam string WEIGHT_FILE  = "target/Controller/programming_inputs/weight_matrix.txt";
    localparam string REPORT_FILE  = "target/Controller/prog/prog_verify_10w_report.txt";

    logic clk, rst_n, reset;
    logic [31:0] host_data;
    logic [2:0]  host_cmd;
    logic valid;
    logic [7:0] data;
    logic [15:0] address;
    logic [CMD_WIDTH-1:0] cmd;
    logic ann_reset, op_done, busy;
    logic [31:0] ann_address;
    logic [2:0] pulses;
    logic [5:0] buf_reg_add;
    logic [2:0] buf_reg_ctrl;
    logic buf_read_write;
    logic [2:0] buf_bit_sel;
    logic [7:0] buf_data_out, buf_data;
    logic D0, D1, D2, D3, D4, D5, D6, D7;
    logic buf_ready;

    logic [3:0] ann_weight_matrix [0:NUM_BLOCKS-1][0:NUM_SUB_BLOCKS-1][0:SUB_BLOCK_ROWS-1][0:SUB_BLOCK_COLS-1];
    logic [3:0] weight_read_data_mock;
    logic [3:0] actual_from_ann;
    logic [1:0] dec_blk, dec_sb;
    logic [2:0] dec_row, dec_col;

    always_comb begin
        ann_address_decode(ann_address, dec_blk, dec_sb, dec_row, dec_col);
        actual_from_ann = ann_weight_matrix[dec_blk][dec_sb][dec_row][dec_col];
    end

    logic [3:0] weight_matrix [0:NUM_WEIGHTS-1];
    logic [15:0] weight_addresses [0:NUM_WEIGHTS-1];

    int current_weight_idx = -1;
    int verify_cycle_cnt = 0;
    logic was_in_verify;

    always_ff @(posedge clk) begin
        was_in_verify <= (pulses == 3'b001) && busy;
        if (busy && (pulses == 3'b001) && !was_in_verify)
            verify_cycle_cnt <= verify_cycle_cnt + 1;
        else if (!busy)
            verify_cycle_cnt <= 0;
    end

    logic in_verify_phase;
    assign in_verify_phase = busy && (pulses == 3'b001 || pulses == 3'b000);

    // Keep idx5 mismatch-active until erase_max_retries_exhausted is observed, then release.
    logic w5_release_under;
    controller_state_t prev_dut_state;
    logic w5_seen_erase_exhausted;

    // Scenario map (first row, cols 0..9 of weight_matrix.txt):
    //   0: equal | 1: read< (re-PROG) | 2: read> (ERASE) | 3-4,6-9: happy
    //   5: force VERIFY mismatch toward ERASE path until erase retry budget is exhausted, then release
    always_comb begin
        weight_read_data_mock = actual_from_ann;
        if (current_weight_idx >= 0 && in_verify_phase) begin
            if (current_weight_idx == 1 && verify_cycle_cnt <= 1 && weight_matrix[1] > 0)
                weight_read_data_mock = weight_matrix[1] - 1;
            else if (current_weight_idx == 2 && verify_cycle_cnt <= 1 && weight_matrix[2] < 15)
                weight_read_data_mock = weight_matrix[2] + 1;
            else if (current_weight_idx == 5 && !w5_release_under)
                weight_read_data_mock = (weight_matrix[5] == 4'hF) ? 4'hE : (weight_matrix[5] + 1'b1);
        end
    end

    parallel_interface u_pi (.clk(clk), .reset(reset), .host_data(host_data), .host_cmd(host_cmd),
        .valid(valid), .data(data), .address(address), .cmd(cmd));

    ann_controller #(
        .USE_WEIGHT_PULSE_LUT(1'b1),
        .WEIGHT_PULSE_LUT_FILE("target/Controller/programming_inputs/weight_pulse_lut.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n), .valid(valid), .data(data), .address(address), .cmd(cmd),
        .ann_reset(ann_reset),
        .op_done(op_done), .ann_address(ann_address), .pulses(pulses),
        .weight_read_data(weight_read_data_mock),
        .buf_reg_add(buf_reg_add), .buf_reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_bit_sel(buf_bit_sel),
        .buf_data_out(buf_data_out), .buf_ready(buf_ready), .buf_data(buf_data), .busy(busy));

    always_ff @(posedge clk) prev_dut_state <= dut.state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            w5_release_under <= 1'b0;
        else if (current_weight_idx != 5)
            w5_release_under <= 1'b0;
        else if (w5_seen_erase_exhausted)
            w5_release_under <= 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            w5_seen_erase_exhausted <= 1'b0;
        else if (current_weight_idx != 5)
            w5_seen_erase_exhausted <= 1'b0;
        else if (dut.erase_max_retries_exhausted)
            w5_seen_erase_exhausted <= 1'b1;
    end

    // Keep retry_cnt accumulation reachable in direct-address flow while idx5 stress case is active.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            release dut.weight_count_reg;
        end else if (current_weight_idx == 5 && !w5_release_under) begin
            force dut.weight_count_reg = 10'd1;
        end else begin
            release dut.weight_count_reg;
        end
    end

    input_buffer u_buf (.clk(clk), .rst_n(rst_n), .data_in(buf_data_out), .ready(buf_ready),
        .reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write), .buf_reg_add(buf_reg_add),
        .bit_sel(buf_bit_sel), .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3), .D4(D4), .D5(D5), .D6(D6), .D7(D7));

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic in_prog_core_phase;
    assign in_prog_core_phase = (pulses == PULSE_MODE_PROG) && (buf_reg_ctrl == CTRL_WEIGHT_READ);

    // op_done mock: DUT waits on op_done in PROG_SELECT, PROG_WAIT_ACK, ERASE_SELECT, ERASE_WAIT_ACK.
    int op_done_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_done <= 0;
            op_done_cnt <= 0;
        end else begin
            if (dut.state == S_PROGRAM && (dut.prog_state == PROG_SELECT || dut.prog_state == PROG_WAIT_ACK)) begin
                op_done <= 1'b1;
                op_done_cnt <= 0;
            end else if (dut.state == S_ERASE && (dut.erase_state == ERASE_SELECT || dut.erase_state == ERASE_WAIT_ACK)) begin
                op_done <= 1'b1;
                op_done_cnt <= 0;
            end else if (busy && (pulses == 3'b001 || pulses == 3'b011 || pulses == 3'b100)) begin
                if (op_done_cnt >= 3) begin
                    op_done <= 1;
                    op_done_cnt <= 0;
                end else begin
                    op_done <= 0;
                    op_done_cnt <= op_done_cnt + 1;
                end
            end else begin
                op_done <= 0;
                op_done_cnt <= 0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int b = 0; b < NUM_BLOCKS; b++)
                for (int sb = 0; sb < NUM_SUB_BLOCKS; sb++)
                    for (int r = 0; r < SUB_BLOCK_ROWS; r++)
                        for (int c = 0; c < SUB_BLOCK_COLS; c++)
                            ann_weight_matrix[b][sb][r][c] <= 4'b0;
        end else if (in_prog_core_phase) begin
            automatic logic [1:0] lb, lsb;
            automatic logic [2:0] lr, lc;
            ann_address_decode(ann_address, lb, lsb, lr, lc);
            ann_weight_matrix[lb][lsb][lr][lc] <= ann_address[27:24];
        end
    end

    function automatic logic [15:0] matrix_coords_to_address(int matrix_row, int matrix_col);
        logic [BLOCK_ID_WIDTH-1:0] block_id;
        logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id;
        logic [ROW_ID_WIDTH-1:0] row_id;
        logic [COL_ID_WIDTH-1:0] col_id;
        logic [3:0] col_within_block;
        block_id = matrix_col[5:4];
        col_within_block = matrix_col[3:0];
        if (matrix_row < 8) begin
            sub_block_id = col_within_block[3] ? 2'd1 : 2'd0;
            row_id = matrix_row[2:0];
        end else begin
            sub_block_id = col_within_block[3] ? 2'd3 : 2'd2;
            row_id = {2'b0, matrix_row[0]};
        end
        col_id = col_within_block[2:0];
        return {6'b0, block_id, sub_block_id, col_id, row_id};
    endfunction

    task automatic load_weights_10();
        automatic int fh, weight_count = 0;
        automatic string line;
        automatic int pos, binary_val, bit_idx, found_binary, bracket_start, bracket_end;
        automatic int content_start, content_end, weight_in_row;

        fh = $fopen(WEIGHT_FILE, "r");
        if (fh == 0) begin $error("Cannot open %s", WEIGHT_FILE); $finish; end

        while (!$feof(fh) && weight_count < NUM_WEIGHTS) begin
            if ($fgets(line, fh) <= 0) continue;
            if (line.len() > 1 && line[0] == "/" && line[1] == "/") continue;
            if (line == "[\n" || line == "]\n") continue;

            bracket_start = -1;
            bracket_end = -1;
            for (int i = 0; i < line.len(); i++) begin
                if (line[i] == "[" && bracket_start < 0) bracket_start = i;
                if (line[i] == "]") begin bracket_end = i; break; end
            end
            if (bracket_start < 0 || bracket_end <= bracket_start) continue;

            content_start = bracket_start + 1;
            content_end = bracket_end - 1;
            pos = content_start;
            weight_in_row = 0;

            while (pos <= content_end && weight_in_row < 64 && weight_count < NUM_WEIGHTS) begin
                while (pos <= content_end && (line[pos] == " " || line[pos] == "\t")) pos++;
                if (pos > content_end) break;
                binary_val = 0;
                found_binary = 0;
                for (bit_idx = 0; bit_idx < 4 && pos <= content_end; bit_idx++) begin
                    if (line[pos] == "0") begin binary_val = binary_val << 1; pos++; found_binary = 1; end
                    else if (line[pos] == "1") begin binary_val = (binary_val << 1) | 1; pos++; found_binary = 1; end
                    else break;
                end
                if (found_binary && bit_idx == 4) begin
                    weight_matrix[weight_count] = binary_val[3:0];
                    weight_count++;
                    weight_in_row++;
                end else begin
                    while (pos <= content_end && line[pos] != " " && line[pos] != "\t") pos++;
                end
            end
        end
        $fclose(fh);
        if (weight_count != NUM_WEIGHTS) begin
            $error("Expected %0d weights from first matrix row, got %0d", NUM_WEIGHTS, weight_count);
            $finish;
        end

        for (int i = 0; i < NUM_WEIGHTS; i++)
            weight_addresses[i] = matrix_coords_to_address(0, i);

        $display("[%0t] Loaded %0d weights from %s (row 0, cols 0..%0d)", $time, weight_count, WEIGHT_FILE,
                 NUM_WEIGHTS - 1);
    endtask

    task send_prog_and_wait(int weight_idx);
        logic [31:0] packet;
        logic [7:0] wval;
        logic [15:0] addr;
        int timeout;

        current_weight_idx = weight_idx;
        wval = {4'b0, weight_matrix[weight_idx]};
        addr = weight_addresses[weight_idx];
        packet = build_host_ann_word(wval, addr);

        // Issue next packet immediately once controller is idle.
        timeout = 0;
        while (busy && timeout < 50000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 50000) begin
            $error("Timeout waiting idle before weight %0d", weight_idx);
            $fatal(1, "Stop: controller did not return idle before next PROG.");
        end

        host_data = packet;
        host_cmd = CMD_PROG;
        @(posedge clk);
        host_cmd = CMD_HIZ;
        host_data = 0;

        // Wait for command acceptance (busy rises), then operation completion (busy drops).
        timeout = 0;
        while (!busy && timeout < 50000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 50000) begin
            $error("Timeout waiting busy high for weight %0d", weight_idx);
            $fatal(1, "Stop: command was not accepted by DUT.");
        end

        timeout = 0;
        while (busy && timeout < 50000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 50000) begin
            $error("Timeout for weight %0d (DUT still busy)", weight_idx);
            $fatal(1, "Stop: starting the next PROG while busy corrupts later checks.");
        end
    endtask

    int fd;
    int errs;
    logic [1:0] blk, sb;
    logic [2:0] row_id, col_id;

    initial begin
        rst_n = 0; reset = 1; host_cmd = CMD_HIZ; host_data = 0;
        repeat(5) @(posedge clk);
        rst_n = 1; reset = 0;
        repeat(5) @(posedge clk);

        load_weights_10();

        fd = $fopen(REPORT_FILE, "w");
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Compact PROG/VERIFY report (%0d weights)", NUM_WEIGHTS);
        $fdisplay(fd, "// idx0 equal | idx1 read< | idx2 read> | idx3-4,6-9 happy | idx5 force ERASE-retry exhaustion flag");
        $fdisplay(fd, "//------------------------------------------------------------------------------");

        errs = 0;
        $display("[%0t] Programming %0d weights...", $time, NUM_WEIGHTS);
        for (int i = 0; i < NUM_WEIGHTS; i++)
            send_prog_and_wait(i);

        repeat(5) @(posedge clk);

        for (int i = 0; i < NUM_WEIGHTS; i++) begin
            logic [15:0] addr;
            logic [3:0] expected, actual;
            addr = weight_addresses[i];
            expected = weight_matrix[i];
            parse_ann_address(addr, blk, sb, row_id, col_id);
            actual = ann_weight_matrix[blk][sb][row_id][col_id];
            if (actual !== expected) begin
                $fdisplay(fd, "  ERROR idx=%0d addr=0x%04X expected=%0d actual=%0d", i, addr, expected, actual);
                errs++;
            end else
                $fdisplay(fd, "  PASS idx=%0d addr=0x%04X weight=%0d", i, addr, expected);
        end

        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Summary: %0d errors", errs);
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        begin automatic int fd_save = fd; fd = 0; $fclose(fd_save); end

        if (errs != 0)
            $error("10w TB: %0d matrix mismatches", errs);
        $display("[%0t] Done. Report: %s", $time, REPORT_FILE);
        repeat(10) @(posedge clk);
        $finish;
    end

    initial begin
        #(200000 * CLK_PERIOD);
        $error("Timeout");
        $finish;
    end

endmodule
