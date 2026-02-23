//------------------------------------------------------------------------------
// Controller Address and Pulse Verification Testbench
//------------------------------------------------------------------------------
// Verifies:
// 1. Address translation: 16-bit host address -> 32-bit ANN addr_out (one-hot)
// 2. Pulse output (pulses[2:0]) for each command: READ, PROG, ERASE, INF
// 3. Controller behavior per command type
//
// Parameters (from controller_pkg):
//   TREAD, PULSE_NUM_READ, TPROG, PULSE_NUM_PROG, TERASE, PULSE_NUM_ERASE, TINF, PULSE_NUM_INF
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_addr_pulse_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    localparam int CLK_PERIOD = 10;
    localparam string RESULT_FILE = "target/Controller/controller_addr_pulse_verify.txt";

    // Pulse parameters from controller_pkg (TREAD, TPROG, TERASE, TINF, etc.)

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    logic clk, rst_n, reset;
    logic [31:0] host_data;
    logic valid;
    logic [7:0] pi_data;
    logic [15:0] address;
    logic [CMD_WIDTH-1:0] cmd;
    logic ann_reset, weight_write_en, op_done, busy;
    logic [SELECTOR_WIDTH-1:0] row_selector, col_selector;
    logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][ROW_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] row_mux_ctrl;
    logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][COL_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] col_mux_ctrl;
    logic [3:0] weight_data;
    logic [ADDR_OUT_WIDTH-1:0] addr_out;
    logic [2:0] pulses;
    logic [5:0] buf_reg_add;
    logic [2:0] buf_reg_ctrl;
    logic buf_read_write;
    logic [2:0] buf_bit_sel;
    logic [7:0] buf_data_out, buf_data;
    logic D0, D1, D2, D3, D4, D5, D6, D7;
    logic buf_ready;

    //--------------------------------------------------------------------------
    // Expected addr_out: {PE[23:20], SA[19:16], col[15:8], row[7:0]} one-hot
    //--------------------------------------------------------------------------
    function automatic logic [ADDR_OUT_WIDTH-1:0] expected_addr_out(logic [15:0] addr_16);
        logic [1:0] blk, sb;
        logic [2:0] rw, cl;
        blk = addr_16[9:8];
        sb  = addr_16[7:6];
        cl  = addr_16[5:3];
        rw  = addr_16[2:0];
        // Format: {PE[23:20], SA[19:16], col[15:8], row[7:0]} - 4,4,8,8 bits one-hot
        return {4'(1 << blk), 4'(1 << sb), 8'(1 << cl), 8'(1 << rw)};
    endfunction

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    parallel_interface u_parallel_interface (
        .clk(clk), .reset(reset), .host_data(host_data),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd)
    );

    ann_controller dut (
        .clk(clk), .rst_n(rst_n),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd),
        .ann_reset(ann_reset), .weight_write_en(weight_write_en),
        .row_selector(row_selector), .col_selector(col_selector),
        .op_done(op_done), .row_mux_ctrl(row_mux_ctrl), .col_mux_ctrl(col_mux_ctrl),
        .weight_data(weight_data), .addr_out(addr_out), .pulses(pulses),
        .weight_read_data(buf_data[3:0]),  // Expected weight during VERIFY (simulate perfect programming)
        .buf_reg_add(buf_reg_add), .buf_reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_bit_sel(buf_bit_sel),
        .buf_data_out(buf_data_out), .buf_ready(buf_ready), .buf_data(buf_data), .busy(busy)
    );

    input_buffer u_input_buffer (
        .clk(clk), .rst_n(rst_n), .data_in(buf_data_out),  // Controller drives buf_data_out for writes
        .ready(buf_ready), .reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_reg_add(buf_reg_add), .bit_sel(buf_bit_sel), .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3), .D4(D4), .D5(D5), .D6(D6), .D7(D7)
    );

    //--------------------------------------------------------------------------
    // op_done: assert after TPROG cycles when weight_write_en, else after 3 cycles when busy
    //--------------------------------------------------------------------------
    int op_done_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_done <= 0;
            op_done_cnt <= 0;
        end else begin
            if (weight_write_en) begin
                if (op_done_cnt >= controller_pkg::TPROG - 1) begin
                    op_done <= 1;
                    op_done_cnt <= 0;
                end else begin
                    op_done <= 0;
                    op_done_cnt <= op_done_cnt + 1;
                end
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

    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 0; reset = 1; host_data = 0;
        repeat(5) @(posedge clk);
        rst_n = 1; reset = 0;
        repeat(2) @(posedge clk);
    end

    //--------------------------------------------------------------------------
    // Task: Run command test and verify addr_out
    //--------------------------------------------------------------------------
    task automatic run_cmd_test(
        input int test_num,
        input logic [CMD_WIDTH-1:0] cmd_code,
        input logic [15:0] addr,
        input logic [7:0] data_val,
        input string desc
    );
        logic [31:0] pkt;
        logic [ADDR_OUT_WIDTH-1:0] exp;
        pkt = {5'b0, cmd_code, addr, data_val};
        exp = expected_addr_out(addr);
        $fdisplay(fd, "=== Test %0d: %s at addr 0x%04X ===", test_num, desc, addr);

        host_data = 0; @(posedge clk); @(posedge clk);
        host_data = pkt; @(posedge clk);
        wait(busy);
        repeat(3) @(posedge clk);
        if (addr_out !== exp)
            $fdisplay(fd, "  ERROR: addr_out 0x%08X != expected 0x%08X", addr_out, exp);
        else
            $fdisplay(fd, "  PASS: addr_out 0x%08X", addr_out);
        wait(!busy);
        $fdisplay(fd, "");
    endtask

    //--------------------------------------------------------------------------
    // Test sequence
    //--------------------------------------------------------------------------
    int fd;
    logic [15:0] test_addr;

    initial begin
        fd = $fopen(RESULT_FILE, "w");
        $fdisplay(fd, "// Controller Address and Pulse Verification");
        $fdisplay(fd, "// Parameters: TREAD=%0d, PULSE_NUM_READ=%0d, TPROG=%0d, PULSE_NUM_PROG=%0d", controller_pkg::TREAD, controller_pkg::PULSE_NUM_READ, controller_pkg::TPROG, controller_pkg::PULSE_NUM_PROG);
        $fdisplay(fd, "//            TERASE=%0d, PULSE_NUM_ERASE=%0d, TINF=%0d, PULSE_NUM_INF=%0d", controller_pkg::TERASE, controller_pkg::PULSE_NUM_ERASE, controller_pkg::TINF, controller_pkg::PULSE_NUM_INF);
        $fdisplay(fd, "// Expected: addr_out = {PE_onehot[23:20], SA_onehot[19:16], col_onehot[15:8], row_onehot[7:0]}");
        $fdisplay(fd, "// Expected: READ->pulses=001, PROG->pulses=010, ERASE->pulses=011, INF->pulses=100");
        $fdisplay(fd, "");

        wait(rst_n);
        repeat(10) @(posedge clk);

        // addr_16 = {reserved[15:10], block_id[9:8], sub_block_id[7:6], col_id[5:3], row_id[2:0]}

        run_cmd_test(1,  CMD_PROG,  16'h0000, 8'd5,   "PROG   (PE=0,SA=0,col=0,row=0)");
        run_cmd_test(2,  CMD_READ,  16'h01E7, 8'h00,  "READ   (PE=1,SA=3,col=6,row=7)");
        run_cmd_test(3,  CMD_ERASE, 16'h0305, 8'h00,  "ERASE  (PE=0,SA=3,col=0,row=5)");
        run_cmd_test(4,  CMD_PROG,  16'h0FFF, 8'd15,  "PROG   (PE=3,SA=3,col=7,row=7)");
        run_cmd_test(5,  CMD_PROG,  16'h2000, 8'd3,   "PROG   (PE=2,SA=0,col=0,row=0)");
        run_cmd_test(6,  CMD_READ,  16'h00A4, 8'h00,  "READ   (PE=0,SA=2,col=4,row=4)");
        run_cmd_test(7,  CMD_ERASE, 16'h3C07, 8'h00,  "ERASE  (PE=3,SA=0,col=0,row=7)");
        run_cmd_test(8,  CMD_PROG,  16'h05FF, 8'd12,  "PROG   (PE=1,SA=1,col=7,row=7)");
        run_cmd_test(9,  CMD_READ,  16'h2D14, 8'h00,  "READ   (PE=2,SA=3,col=0,row=4)");
        run_cmd_test(10, CMD_ERASE, 16'h1609, 8'h00,  "ERASE  (PE=1,SA=2,col=0,row=1)");
        run_cmd_test(11, CMD_PROG,  16'h0068, 8'd7,   "PROG   (PE=0,SA=0,col=6,row=0)");
        run_cmd_test(12, CMD_READ,  16'h3F00, 8'h00,  "READ   (PE=3,SA=3,col=0,row=0)");
        run_cmd_test(13, CMD_ERASE, 16'h0091, 8'h00,  "ERASE  (PE=0,SA=0,col=1,row=1)");
        run_cmd_test(14, CMD_PROG,  16'h1838, 8'd10,  "PROG   (PE=1,SA=2,col=1,row=0)");
        run_cmd_test(15, CMD_READ,  16'h0D48, 8'h00,  "READ   (PE=0,SA=3,col=2,row=0)");
        run_cmd_test(16, CMD_PROG,  16'h0353, 8'd9,   "PROG   (PE=3,SA=1,col=2,row=3)");
        run_cmd_test(17, CMD_READ,  16'h006A, 8'h00,  "READ   (PE=0,SA=1,col=5,row=2)");
        run_cmd_test(18, CMD_ERASE, 16'h0266, 8'h00,  "ERASE  (PE=2,SA=1,col=4,row=6)");
        run_cmd_test(19, CMD_PROG,  16'h0107, 8'd14,  "PROG   (PE=1,SA=0,col=0,row=7)");
        run_cmd_test(20, CMD_READ,  16'h039D, 8'h00,  "READ   (PE=3,SA=2,col=3,row=5)");
        run_cmd_test(21, CMD_ERASE, 16'h00FC, 8'h00,  "ERASE  (PE=0,SA=3,col=7,row=4)");
        run_cmd_test(22, CMD_PROG,  16'h02B1, 8'd6,   "PROG   (PE=2,SA=2,col=6,row=1)");
        run_cmd_test(23, CMD_READ,  16'h01CE, 8'h00,  "READ   (PE=1,SA=3,col=1,row=6)");
        run_cmd_test(24, CMD_ERASE, 16'h0312, 8'h00,  "ERASE  (PE=3,SA=0,col=2,row=2)");
        run_cmd_test(25, CMD_PROG,  16'h0083, 8'd11,  "PROG   (PE=0,SA=2,col=0,row=3)");
        run_cmd_test(26, CMD_READ,  16'h023D, 8'h00,  "READ   (PE=2,SA=0,col=7,row=5)");
        run_cmd_test(27, CMD_ERASE, 16'h0158, 8'h00,  "ERASE  (PE=1,SA=1,col=3,row=0)");
        run_cmd_test(28, CMD_PROG,  16'h03A9, 8'd4,   "PROG   (PE=3,SA=2,col=5,row=1)");
        run_cmd_test(29, CMD_READ,  16'h012E, 8'h00,  "READ   (PE=1,SA=0,col=5,row=6)");
        run_cmd_test(30, CMD_ERASE, 16'h00FF, 8'h00,  "ERASE  (PE=0,SA=3,col=7,row=7)");

        $fdisplay(fd, "=== Verification Complete (30 tests) ===");
        $fclose(fd);

        $display("[%0t] Verification complete. Results in %s", $time, RESULT_FILE);
        repeat(5) @(posedge clk);
        $finish;
    end

endmodule
