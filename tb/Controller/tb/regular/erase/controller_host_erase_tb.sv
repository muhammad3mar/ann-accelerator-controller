//------------------------------------------------------------------------------
// Host-directed CMD_ERASE on one memristor cell: pulse trace + mock matrix before/after.
// Report: target/Controller/erase/controller_host_erase_report.txt
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "rtl/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_host_erase_tb;

    localparam int CLK_PERIOD = 5;
    localparam string REPORT_FILE = "target/Controller/erase/controller_host_erase_report.txt";

    localparam logic [15:0] ADDR_A = 16'h01E7;
    localparam logic [7:0]  WEIGHT_A = 8'h03;
    localparam logic [15:0] ADDR_B = 16'h0100;
    localparam logic [7:0]  WEIGHT_B = 8'h04;

    logic        clk, rst_n, reset;
    logic [31:0] host_data;
    logic [2:0]  host_cmd;
    logic        valid;
    logic [7:0]  pi_data;
    logic [15:0] address;
    logic [CMD_WIDTH-1:0] cmd;
    logic        ann_reset, op_done, busy;
    logic [31:0] ann_address;
    logic [2:0]  pulses;
    logic [5:0]  buf_reg_add;
    logic [2:0]  buf_reg_ctrl;
    logic        buf_read_write;
    logic [2:0]  buf_bit_sel;
    logic [7:0]  buf_data_out, buf_data;
    logic        D0, D1, D2, D3, D4, D5, D6, D7;
    logic        buf_ready;

    logic [3:0] ann_weight_matrix [0:NUM_BLOCKS-1][0:NUM_SUB_BLOCKS-1][0:SUB_BLOCK_ROWS-1][0:SUB_BLOCK_COLS-1];
    logic [3:0] weight_read_data_mock;
    logic [3:0] actual_from_ann;
    logic [1:0] dec_blk, dec_sb;
    logic [2:0] dec_row, dec_col;

    logic [1:0] idx_A_b, idx_A_sb, idx_B_b, idx_B_sb;
    logic [2:0] idx_A_r, idx_A_c, idx_B_r, idx_B_c;
    logic [3:0] cell_A_value, cell_B_value;

    always_comb begin
        ann_address_decode(ann_address, dec_blk, dec_sb, dec_row, dec_col);
        actual_from_ann = ann_weight_matrix[dec_blk][dec_sb][dec_row][dec_col];
    end

    assign weight_read_data_mock = actual_from_ann;

    always_comb begin
        parse_ann_address(ADDR_A, idx_A_b, idx_A_sb, idx_A_r, idx_A_c);
        parse_ann_address(ADDR_B, idx_B_b, idx_B_sb, idx_B_r, idx_B_c);
        cell_A_value = ann_weight_matrix[idx_A_b][idx_A_sb][idx_A_r][idx_A_c];
        cell_B_value = ann_weight_matrix[idx_B_b][idx_B_sb][idx_B_r][idx_B_c];
    end

    parallel_interface u_pi (
        .clk(clk), .reset(reset), .host_data(host_data), .host_cmd(host_cmd),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd)
    );

    ann_controller dut (
        .clk(clk), .rst_n(rst_n),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd),
        .ann_reset(ann_reset),
        .op_done(op_done), .ann_address(ann_address), .pulses(pulses),
        .weight_read_data(weight_read_data_mock),
        .buf_reg_add(buf_reg_add), .buf_reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_bit_sel(buf_bit_sel),
        .buf_data_out(buf_data_out), .buf_ready(buf_ready), .buf_data(buf_data), .busy(busy)
    );

    input_buffer u_buf (
        .clk(clk), .rst_n(rst_n), .data_in(buf_data_out),
        .ready(buf_ready), .reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_reg_add(buf_reg_add), .bit_sel(buf_bit_sel), .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3), .D4(D4), .D5(D5), .D6(D6), .D7(D7)
    );

    logic in_prog_core_phase;
    assign in_prog_core_phase = (pulses == PULSE_MODE_PROG) && (buf_reg_ctrl == CTRL_WEIGHT_READ);

    logic [2:0] prev_erase_state;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            prev_erase_state <= 3'b0;
        else
            prev_erase_state <= dut.erase_state;
    end

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
            end else if (busy && pulses == PULSE_MODE_READ) begin
                if (op_done_cnt >= PULSE_TOTAL_READ - 1) begin
                    op_done <= 1;
                    op_done_cnt <= 0;
                end else begin
                    op_done <= 0;
                    op_done_cnt <= op_done_cnt + 1;
                end
            end else if (busy && pulses == PULSE_MODE_ERASE) begin
                if (op_done_cnt >= PULSE_TOTAL_ERASE - 1) begin
                    op_done <= 1;
                    op_done_cnt <= 0;
                end else begin
                    op_done <= 0;
                    op_done_cnt <= op_done_cnt + 1;
                end
            end else if (busy && pulses == PULSE_MODE_INF) begin
                if (op_done_cnt >= PULSE_TOTAL_INF - 1) begin
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
        end else if (prev_erase_state == ERASE_PULSE && dut.erase_state == ERASE_WAIT_ACK) begin
            automatic logic [1:0] lb, lsb;
            automatic logic [2:0] lr, lc;
            ann_address_decode(ann_address, lb, lsb, lr, lc);
            ann_weight_matrix[lb][lsb][lr][lc] <= 4'b0;
        end
    end

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 0; reset = 1; host_data = 0; host_cmd = CMD_HIZ;
        repeat(5) @(posedge clk);
        rst_n = 1; reset = 0;
        repeat(4) @(posedge clk);
    end

    task automatic wait_idle(int maxcyc);
        int n;
        n = 0;
        while (busy && n < maxcyc) begin
            @(posedge clk);
            n++;
        end
        if (busy)
            $fatal(1, "wait_idle timeout");
    endtask

    task automatic pulse_host_ann(input logic [2:0] c, input logic [7:0] d, input logic [15:0] a);
        host_data = build_host_ann_word(d, a);
        host_cmd  = c;
        @(posedge clk);
        host_data = 0;
        host_cmd  = CMD_HIZ;
        @(posedge clk);
    endtask

    function automatic void fprint_cell_snapshot(int fd, string title);
        $fdisplay(fd, "// %s", title);
        $fdisplay(fd, "// Cell A: addr=0x%04h  indices [%0d][%0d][%0d][%0d]  weight=%0d",
                  ADDR_A, idx_A_b, idx_A_sb, idx_A_r, idx_A_c,
                  ann_weight_matrix[idx_A_b][idx_A_sb][idx_A_r][idx_A_c]);
        $fdisplay(fd, "// Cell B: addr=0x%04h  indices [%0d][%0d][%0d][%0d]  weight=%0d",
                  ADDR_B, idx_B_b, idx_B_sb, idx_B_r, idx_B_c,
                  ann_weight_matrix[idx_B_b][idx_B_sb][idx_B_r][idx_B_c]);
        $fdisplay(fd, "");
    endfunction

    // Log every posedge while DUT is busy after a command (PROG / ERASE / etc.)
    // pulses: 3-bit mode (b2b1b0, no separators); ann_address: data-PE-SA-col-row with '-' between fields
    task automatic log_busy_trace(int fd, string phase_title, bit host_erase_only = 0);
        $fdisplay(fd, "// --- %s ---", phase_title);
        $fdisplay(fd, "// Columns: time(ns) | busy | pulses[2:0] | ann_address: data-PE-SA-col-row (binary) | state | erase_state");
        $fdisplay(fd, "// ann_address fields: data[31:24] - PE[23:20] - SA[19:16] - col[15:8] - row[7:0]");
        $fdisplay(fd, "// state: 0=IDLE 2=PROGRAM 3=VERIFY 4=ERASE ...  | erase_state: 0=HIZ .. 3=PULSE .. 5=COMPLETE");
        while (!busy)
            @(posedge clk);
        while (busy) begin
            if (host_erase_only && (dut.state == S_PROGRAM || dut.state == S_VERIFY)) begin
                $fdisplay(fd, "FAIL: host erase entered PROG/VERIFY (state=%0d) — RTL erase_from_host?", dut.state);
                $fatal(1, "host CMD_ERASE must not run PROG/VERIFY");
            end
            $fdisplay(fd, "[%0t] | %b | %03b | %08b-%04b-%04b-%08b-%08b | %0d | %0d",
                      $time, busy, pulses,
                      ann_address[31:24], ann_address[23:20], ann_address[19:16],
                      ann_address[15:8], ann_address[7:0],
                      dut.state, dut.erase_state);
            @(posedge clk);
        end
        $fdisplay(fd, "[%0t] | %b | %03b | %08b-%04b-%04b-%08b-%08b | %0d | %0d | (idle)",
                  $time, busy, pulses,
                  ann_address[31:24], ann_address[23:20], ann_address[19:16],
                  ann_address[15:8], ann_address[7:0],
                  dut.state, dut.erase_state);
        $fdisplay(fd, "");
    endtask

    int fd;

    initial begin
        fd = $fopen(REPORT_FILE, "w");
        if (!fd) begin $error("Cannot open %s", REPORT_FILE); $finish; end

        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// controller_host_erase_tb — host CMD_ERASE on cell A, cell B untouched");
        $fdisplay(fd, "//");
        $fdisplay(fd, "// NOTE: Phases 1 and 2 use CMD_PROG. In this controller, every PROG runs");
        $fdisplay(fd, "//       S_PROGRAM then S_VERIFY — that is normal weight programming, not erase.");
        $fdisplay(fd, "// Phase 3 is CMD_ERASE only (RTL erase_from_host): expect state=4 (ERASE) only,");
        $fdisplay(fd, "//       then idle — no PROG/VERIFY after host erase.");
        $fdisplay(fd, "//");
        $fdisplay(fd, "// Cell A: addr 0x%04h  PROG weight %0d", ADDR_A, WEIGHT_A[3:0]);
        $fdisplay(fd, "// Cell B: addr 0x%04h  PROG weight %0d", ADDR_B, WEIGHT_B[3:0]);
        $fdisplay(fd, "// Pulse encoding (binary b2b1b0): HIZ=000 READ=001 PROG=010 ERASE=011 INF=100");
        $fdisplay(fd, "//");
        $fdisplay(fd, "// TB: CLK_PERIOD=%0d ns (timescale 1ns/1ps)", CLK_PERIOD);
        $fdisplay(fd, "// controller_pkg (ann_controller defaults unless overridden):");
        $fdisplay(fd, "//   TREAD=%0d  PULSE_NUM_READ=%0d  PULSE_TOTAL_READ=%0d",
                  TREAD, PULSE_NUM_READ, PULSE_TOTAL_READ);
        $fdisplay(fd, "//   TPROG=%0d  PULSE_NUM_PROG=%0d  PULSE_TOTAL_PROG=%0d",
                  TPROG, PULSE_NUM_PROG, PULSE_TOTAL_PROG);
        $fdisplay(fd, "//   TERASE=%0d  PULSE_NUM_ERASE=%0d  PULSE_TOTAL_ERASE=%0d",
                  TERASE, PULSE_NUM_ERASE, PULSE_TOTAL_ERASE);
        $fdisplay(fd, "//   TINF=%0d  PULSE_NUM_INF=%0d  PULSE_TOTAL_INF=%0d",
                  TINF, PULSE_NUM_INF, PULSE_TOTAL_INF);
        $fdisplay(fd, "//   MAX_PROG_RETRIES=%0d", MAX_PROG_RETRIES);
        $fdisplay(fd, "//   USE_WEIGHT_PULSE_LUT=%0d (DUT param; 1 => PROG_WRITE length from weight_pulse_lut.mem)",
                  dut.USE_WEIGHT_PULSE_LUT);
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "");

        wait(rst_n);

        $fdisplay(fd, "// ======================================================================");
        $fdisplay(fd, "// PHASE 1: PROG cell A");
        $fdisplay(fd, "// ======================================================================");
        $fdisplay(fd, "");
        pulse_host_ann(CMD_PROG, WEIGHT_A, ADDR_A);
        log_busy_trace(fd, "Pulse trace: PROG cell A (wait busy -> idle)");
        if (ann_weight_matrix[idx_A_b][idx_A_sb][idx_A_r][idx_A_c] !== WEIGHT_A[3:0])
            $fatal(1, "After PROG A: mock matrix mismatch");

        $fdisplay(fd, "// ======================================================================");
        $fdisplay(fd, "// PHASE 2: PROG cell B");
        $fdisplay(fd, "// ======================================================================");
        $fdisplay(fd, "");
        pulse_host_ann(CMD_PROG, WEIGHT_B, ADDR_B);
        log_busy_trace(fd, "Pulse trace: PROG cell B (wait busy -> idle)");
        if (ann_weight_matrix[idx_B_b][idx_B_sb][idx_B_r][idx_B_c] !== WEIGHT_B[3:0])
            $fatal(1, "After PROG B: mock matrix mismatch");

        fprint_cell_snapshot(fd, "BEFORE ERASE (expect A=PROG value, B=PROG value)");

        $fdisplay(fd, "// ======================================================================");
        $fdisplay(fd, "// PHASE 3: Host CMD_ERASE cell A only (RTL: erase_from_host -> idle, no PROG/VERIFY)");
        $fdisplay(fd, "// ======================================================================");
        $fdisplay(fd, "");
        pulse_host_ann(CMD_ERASE, 8'h00, ADDR_A);
        log_busy_trace(fd, "Pulse trace: CMD_ERASE cell A", 1'b1);

        fprint_cell_snapshot(fd, "AFTER ERASE (expect A=0, B unchanged)");

        if (ann_weight_matrix[idx_A_b][idx_A_sb][idx_A_r][idx_A_c] !== 4'd0) begin
            $fdisplay(fd, "FAIL: cell A not zero after erase (got %0d)",
                      ann_weight_matrix[idx_A_b][idx_A_sb][idx_A_r][idx_A_c]);
            $fclose(fd);
            $fatal(1, "cell A not cleared");
        end
        if (ann_weight_matrix[idx_B_b][idx_B_sb][idx_B_r][idx_B_c] !== WEIGHT_B[3:0]) begin
            $fdisplay(fd, "FAIL: cell B changed after erase on A");
            $fclose(fd);
            $fatal(1, "cell B corrupted");
        end

        $fdisplay(fd, "PASS: cell A cleared, cell B still %0d", WEIGHT_B[3:0]);
        $fclose(fd);
        $display("[%0t] controller_host_erase_tb PASS -> %s", $time, REPORT_FILE);
        $finish;
    end

endmodule
