//------------------------------------------------------------------------------
// Controller Program-Verify Cycle Testbench (640-weight sweep, LUT PROG pulses)
//------------------------------------------------------------------------------
// Primary program/verify regression: DUT uses weight_pulse_lut.mem for PROG_WRITE length.
// Non-LUT (fixed PULSE_TOTAL_PROG) variant is archived under backup/controller_prog_verify_fixed_pulse/.
// Tests and verifies:
// 1. Load weights from weight_matrix.txt (10x64)
// 2. Program each weight via CMD_PROG with correct address
// 3. Asymmetric flow: read==expected -> next; read<expected -> re-PROG; read>expected -> ERASE->PROG
// 4. Injects verify failures for multiple weights: read<expected (re-PROG) and read>expected (ERASE)
// 5. Detailed cycle logging to verification report
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "rtl/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_prog_verify_lut_tb;

    localparam int CLK_PERIOD = 5;
    localparam string WEIGHT_FILE  = "target/Controller/programming_inputs/weight_matrix.txt";
    localparam string REPORT_FILE  = "target/Controller/prog/prog_verify_report.txt";

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

    // Mock ANN: captures programmed weights
    logic [3:0] ann_weight_matrix [0:NUM_BLOCKS-1][0:NUM_SUB_BLOCKS-1][0:SUB_BLOCK_ROWS-1][0:SUB_BLOCK_COLS-1];
    logic [3:0] weight_read_data_mock;
    logic [3:0] actual_from_ann;
    logic [1:0] dec_blk, dec_sb;
    logic [2:0] dec_row, dec_col;

    always_comb begin
        ann_address_decode(ann_address, dec_blk, dec_sb, dec_row, dec_col);
        actual_from_ann = ann_weight_matrix[dec_blk][dec_sb][dec_row][dec_col];
    end

    // Weight storage from file (declared early for inject logic)
    logic [3:0] weight_matrix [0:639];
    logic [15:0] weight_addresses [0:639];

    // Inject verify failures to test asymmetric flow (read<expected -> re-PROG, read>expected -> ERASE->PROG)
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

    // Controller samples weight_read_data in VERIFY_CHECK (pulses=000); inject covers READ/WAIT/CHECK
    logic in_verify_phase;
    assign in_verify_phase = busy && (pulses == 3'b001 || pulses == 3'b000);

    // Inject read<expected (re-PROG) for these indices; read>expected (ERASE) for those.
    // Early indices stress the start of the 640-weight sweep; high indices (~380+) stress the tail
    // so prog_verify_report.txt shows ERASE/re-PROG near the end, not only at the beginning.
    function automatic bit is_inject_read_lt(int idx);
        return (idx == 5 || idx == 15 || idx == 25 || idx == 50 || idx == 100 || idx == 200
             || idx == 385 || idx == 420 || idx == 455 || idx == 490 || idx == 535 || idx == 580
             || idx == 605 || idx == 625);
    endfunction
    function automatic bit is_inject_read_gt(int idx);
        return (idx == 10 || idx == 30 || idx == 70 || idx == 150 || idx == 250 || idx == 350
             || idx == 395 || idx == 440 || idx == 475 || idx == 510 || idx == 555 || idx == 600
             || idx == 615 || idx == 635);
    endfunction

    always_comb begin
        weight_read_data_mock = actual_from_ann;
        if (current_weight_idx >= 0 && in_verify_phase && (verify_cycle_cnt <= 1)) begin
            if (is_inject_read_lt(current_weight_idx) && weight_matrix[current_weight_idx] > 0)
                weight_read_data_mock = weight_matrix[current_weight_idx] - 1;  // read < expected -> re-PROG
            else if (is_inject_read_gt(current_weight_idx) && weight_matrix[current_weight_idx] < 15)
                weight_read_data_mock = weight_matrix[current_weight_idx] + 1;  // read > expected -> ERASE
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

    input_buffer u_buf (.clk(clk), .rst_n(rst_n), .data_in(buf_data_out), .ready(buf_ready),
        .reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write), .buf_reg_add(buf_reg_add),
        .bit_sel(buf_bit_sel), .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3), .D4(D4), .D5(D5), .D6(D6), .D7(D7));

    // Clock
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

    // Mock ANN capture
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

    //--------------------------------------------------------------------------
    // Address mapping: matrix row/col -> 16-bit host address
    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    // Load weights from file
    //--------------------------------------------------------------------------
    task automatic load_weights();
        automatic int fh, weight_count = 0;
        automatic string line;
        automatic int pos, binary_val, bit_idx, found_binary, bracket_start, bracket_end;
        automatic int content_start, content_end, weight_in_row;

        fh = $fopen(WEIGHT_FILE, "r");
        if (fh == 0) begin $error("Cannot open %s", WEIGHT_FILE); $finish; end

        while (!$feof(fh) && weight_count < 640) begin
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

            while (pos <= content_end && weight_in_row < 64 && weight_count < 640) begin
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
        if (weight_count != 640) begin $error("Expected 640 weights, got %0d", weight_count); $finish; end

        for (int row = 0; row < 10; row++)
            for (int col = 0; col < 64; col++)
                weight_addresses[row*64 + col] = matrix_coords_to_address(row, col);

        $display("[%0t] Loaded %0d weights from %s", $time, weight_count, WEIGHT_FILE);
    endtask

    //--------------------------------------------------------------------------
    // Cycle monitor: PROG / VERIFY / ERASE
    //--------------------------------------------------------------------------
    string phase_str;
    logic [2:0] prev_pulses;
    logic prev_busy;
    int prog_count, verify_count, erase_count;
    logic [15:0] current_addr;
    int retry_count_per_weight [0:639];

    initial for (int i = 0; i < 640; i++) retry_count_per_weight[i] = 0;

    always_ff @(posedge clk) begin
        prev_pulses <= pulses;
        prev_busy <= busy;
    end

    //--------------------------------------------------------------------------
    // Send single PROG command and wait for completion (PROG->VERIFY->IDLE or PROG->VERIFY->ERASE->PROG...)
    //--------------------------------------------------------------------------
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
        while (busy && timeout < 5000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 5000) $error("Timeout waiting idle before weight %0d", weight_idx);

        host_data = packet;
        host_cmd = CMD_PROG;
        @(posedge clk);
        host_cmd = CMD_HIZ;
        host_data = 0;

        // Wait for command acceptance (busy rises), then operation completion (busy drops).
        timeout = 0;
        while (!busy && timeout < 5000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 5000) $error("Timeout waiting busy high for weight %0d", weight_idx);

        timeout = 0;
        while (busy && timeout < 5000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 5000) $error("Timeout for weight %0d", weight_idx);
    endtask

    //--------------------------------------------------------------------------
    // Main test
    //--------------------------------------------------------------------------
    int fd;
    int errs;
    int erase_phase_count = 0;
    int reprog_retry_count = 0;
    logic [1:0] blk, sb;
    logic [2:0] row_id, col_id;

    initial begin
        rst_n = 0; reset = 1; host_cmd = CMD_HIZ; host_data = 0;
        repeat(5) @(posedge clk);
        rst_n = 1; reset = 0;
        repeat(5) @(posedge clk);

        load_weights();

        fd = $fopen(REPORT_FILE, "w");
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Controller Program-Verify Cycle Verification Report (PROG pulse length from weight_pulse_lut.mem)");
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Flow: PROG -> VERIFY -> (OK: next | FAIL: ERASE -> PROG retry)");
        $fdisplay(fd, "// Weights from: %s", WEIGHT_FILE);
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "");

        errs = 0;
        prog_count = 0;
        verify_count = 0;
        erase_count = 0;

        $display("[%0t] Programming 640 weights (PROG->VERIFY cycle)...", $time);

        for (int i = 0; i < 640; i++) begin
            send_prog_and_wait(i);
            prog_count++;
        end

        $fdisplay(fd, "// Total weights programmed: %0d", prog_count);
        $fdisplay(fd, "");

        repeat(5) @(posedge clk);  // Ensure last write has propagated

        // Verify each programmed weight matches expected
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Verification: Compare programmed weights to expected");
        $fdisplay(fd, "//------------------------------------------------------------------------------");

        for (int row = 0; row < 10; row++) begin
            for (int col = 0; col < 64; col++) begin
                int idx;
                logic [15:0] addr;
                logic [3:0] expected;
                logic [3:0] actual;
                idx = row * 64 + col;
                addr = weight_addresses[idx];
                expected = weight_matrix[idx];

                parse_ann_address(addr, blk, sb, row_id, col_id);
                actual = ann_weight_matrix[blk][sb][row_id][col_id];

                if (actual !== expected) begin
                    $fdisplay(fd, "  ERROR idx=%0d (row=%0d,col=%0d) addr=0x%04X: expected=%0d, actual=%0d",
                        idx, row, col, addr, expected, actual);
                    errs++;
                end
            end
        end

        $fdisplay(fd, "");
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Final ANN Core Cells Weights (10 rows x 64 cols, 4-bit each)");
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        for (int row = 0; row < 10; row++) begin
            $fwrite(fd, "// Row %0d: [", row);
            for (int col = 0; col < 64; col++) begin
                logic [1:0] blk;
                logic [1:0] sb;
                logic [2:0] row_id, col_id;
                logic [3:0] w;
                parse_ann_address(weight_addresses[row*64+col], blk, sb, row_id, col_id);
                w = ann_weight_matrix[blk][sb][row_id][col_id];
                $fwrite(fd, "%0d", w);
                if (col < 63) $fwrite(fd, " ");
            end
            $fdisplay(fd, "]");
        end
        $fdisplay(fd, "");

        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Asymmetric flow coverage:");
        $fdisplay(fd, "//   ERASE path (read>expected): %0d", erase_phase_count);
        $fdisplay(fd, "//   re-PROG path (read<expected): %0d (PROG after VERIFY)", reprog_retry_count);
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Summary: %0d errors in 640 weights", errs);
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        begin automatic int fd_save = fd; fd = 0; $fclose(fd_save); end  // Stop logger before close

        // Assert both retry paths were exercised by inject
        if (erase_phase_count == 0)
            $error("Expected ERASE path (read>expected); check is_inject_read_gt (early + high indices)");
        if (reprog_retry_count == 0)
            $error("Expected re-PROG path (read<expected); check is_inject_read_lt (early + high indices)");

        $display("[%0t] Verification complete: %0d errors", $time, errs);
        $display("[%0t] Report: %s", $time, REPORT_FILE);
        repeat(10) @(posedge clk);
        $finish;
    end

    //--------------------------------------------------------------------------
    // Cycle logger: log only PROG / REPROG / VERIFY / ERASE transactions (sample on phase changes).
    // Internal substates (PROG_PREP, CHECK_DONE, COMPUTE) update last_phase but do not print.
    //--------------------------------------------------------------------------
    string last_phase = "";
    int weights_logged = 0;
    logic saw_idle = 1;  // 1 when we just came from idle (don't count first PROG as retry)
    logic reprog_seq_active = 0;  // 1 between re-PROG START and END (avoids duplicate titles during PROG_PREP↔PROG)

    always_ff @(posedge clk) begin
        if (busy && fd != 0) begin
            if (in_prog_core_phase) phase_str = "PROG";
            else if (pulses == 3'b001) phase_str = "VERIFY";
            else if (pulses == 3'b011) phase_str = "ERASE";
            else if (pulses == 3'b010) phase_str = "PROG_PREP";
            else if (pulses == 3'b100) phase_str = "COMPUTE";
            else phase_str = "CHECK_DONE";
            if (phase_str != last_phase) begin
                if (last_phase == "ERASE" && phase_str != "ERASE") begin
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                    $fdisplay(fd, "// ERASE sequence END   [%0t]  (next phase: %s)", $time, phase_str);
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                end
                if (last_phase == "PROG" && reprog_seq_active &&
                    (phase_str == "VERIFY" || phase_str == "ERASE")) begin
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                    $fdisplay(fd, "// re-PROG sequence END [%0t]  (next phase: %s)", $time, phase_str);
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                    reprog_seq_active = 0;
                end
                if (phase_str == "ERASE" && last_phase != "ERASE") begin
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                    $fdisplay(fd, "// ERASE sequence START [%0t]", $time);
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                end
                if (phase_str == "PROG" && !reprog_seq_active && !saw_idle &&
                    (last_phase == "VERIFY" || last_phase == "CHECK_DONE" ||
                     last_phase == "PROG_PREP" || last_phase == "COMPUTE" || last_phase == "ERASE")) begin
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                    $fdisplay(fd, "// re-PROG sequence START [%0t]  (after phase: %s)", $time, last_phase);
                    $fdisplay(fd, "//------------------------------------------------------------------------------");
                    reprog_seq_active = 1;
                end

                // VERIFY: log at READ/WAIT -> CHECK (pulses 001 -> 000) with expected vs readback
                if (last_phase == "VERIFY" && phase_str == "CHECK_DONE") begin
                    automatic int exp_w;
                    exp_w = (current_weight_idx >= 0) ? int'(weight_matrix[current_weight_idx]) : 0;
                    $fdisplay(fd, "[%0t] Phase: VERIFY  ann_address=0x%08X  expected_weight=%0d  read_weight=%0d",
                        $time, ann_address, exp_w, int'(weight_read_data_mock));
                end
                if (phase_str == "PROG" || phase_str == "ERASE") begin
                    automatic string phase_log;
                    if (phase_str == "ERASE")
                        phase_log = phase_str;
                    else if (!saw_idle && (last_phase == "VERIFY" || last_phase == "CHECK_DONE" ||
                             last_phase == "PROG_PREP" || last_phase == "COMPUTE" || last_phase == "ERASE"))
                        phase_log = "REPROG";
                    else
                        phase_log = "PROG";
                    $fdisplay(fd, "[%0t] Phase: %s  ann_address=0x%08X  programmed_weight=%0d",
                        $time, phase_log, ann_address, int'(ann_address[27:24]));
                end
                if (phase_str == "PROG") begin
                    weights_logged++;
                    // re-PROG: PROG after VERIFY or CHECK_DONE/PROG_PREP (retry path), and we didn't just come from idle
                    if (!saw_idle && (last_phase == "VERIFY" || last_phase == "CHECK_DONE" || last_phase == "PROG_PREP" || last_phase == "COMPUTE"))
                        reprog_retry_count++;
                    saw_idle = 0;
                end
                if (phase_str == "ERASE") erase_phase_count++;
                last_phase = phase_str;
            end
        end else if (!busy) begin
            if (fd != 0 && last_phase == "ERASE") begin
                $fdisplay(fd, "//------------------------------------------------------------------------------");
                $fdisplay(fd, "// ERASE sequence END   [%0t]  (DUT idle)", $time);
                $fdisplay(fd, "//------------------------------------------------------------------------------");
            end
            if (fd != 0 && reprog_seq_active) begin
                $fdisplay(fd, "//------------------------------------------------------------------------------");
                $fdisplay(fd, "// re-PROG sequence END [%0t]  (DUT idle)", $time);
                $fdisplay(fd, "//------------------------------------------------------------------------------");
                reprog_seq_active = 0;
            end
            last_phase = "";
            saw_idle = 1;
        end
    end

    initial begin
        #(1000000 * CLK_PERIOD);
        $error("Timeout");
        $finish;
    end

endmodule
