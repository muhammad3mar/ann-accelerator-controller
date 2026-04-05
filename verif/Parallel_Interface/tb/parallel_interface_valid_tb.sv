//------------------------------------------------------------------------------
// Parallel Interface - Valid Signal Testbench
//------------------------------------------------------------------------------
// Tests: valid = (host_cmd != CMD_HIZ). Idle: host_cmd=HIZ. Transaction: non-HIZ.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import parallel_interface_pkg::*;

module parallel_interface_valid_tb;

    logic clk, reset;
    logic [31:0] host_data;
    logic [2:0] host_cmd;
    logic valid;
    logic [7:0] data;
    logic [15:0] address;
    logic [2:0] cmd;

    parallel_interface dut (
        .clk(clk),
        .reset(reset),
        .host_data(host_data),
        .host_cmd(host_cmd),
        .valid(valid),
        .data(data),
        .address(address),
        .cmd(cmd)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int pass_count, fail_count;

    initial begin
        reset = 0;
        host_data = 32'd0;
        host_cmd = CMD_HIZ;
        pass_count = 0;
        fail_count = 0;
        #20;

        $display("----------------------------------------");
        $display("Parallel Interface Valid Signal Tests");
        $display("Summary: valid=1 iff host_cmd != CMD_HIZ.");
        $display("----------------------------------------");

        // (a) host_cmd=HIZ -> valid = 0
        host_data = 32'd0;
        host_cmd  = CMD_HIZ;
        #1;
        if (!valid) begin pass_count++; $display("  Test: HIZ host_data=0 | Expected valid=0 | PASS"); end
        else begin fail_count++; $display("  Test: HIZ host_data=0 | FAIL valid=%0d", valid); end

        // (b) host_cmd = READ/PROG/ERASE/INF -> valid = 1 (host_data may be zero)
        host_cmd = CMD_READ;
        host_data = 32'd0;
        #1;
        if (valid) begin pass_count++; $display("  Test: READ cmd | PASS"); end
        else begin fail_count++; $display("  Test: READ cmd | FAIL"); end

        host_cmd = CMD_PROG;
        #1;
        if (valid) begin pass_count++; $display("  Test: PROG cmd | PASS"); end
        else begin fail_count++; $display("  Test: PROG cmd | FAIL"); end

        host_cmd = CMD_ERASE;
        #1;
        if (valid) begin pass_count++; $display("  Test: ERASE cmd | PASS"); end
        else begin fail_count++; $display("  Test: ERASE cmd | FAIL"); end

        host_cmd = CMD_INF;
        #1;
        if (valid) begin pass_count++; $display("  Test: INF cmd | PASS"); end
        else begin fail_count++; $display("  Test: INF cmd | FAIL"); end

        // (c) host_cmd=HIZ but host_data != 0 -> valid = 0 (command lane is idle)
        host_cmd  = CMD_HIZ;
        host_data = build_host_ann_word(8'h01, 16'd0);
        #1;
        if (!valid) begin pass_count++; $display("  Test: HIZ with nonzero payload | Expected valid=0 | PASS"); end
        else begin fail_count++; $display("  Test: HIZ with nonzero payload | FAIL"); end

        // (d) HIZ with nonzero decoded address (nonzero tail) -> still valid=0
        host_cmd  = CMD_HIZ;
        host_data = build_host_ann_word(8'd0, 16'h0001);
        #1;
        if (!valid) begin pass_count++; $display("  Test: HIZ with nonzero tail | PASS"); end
        else begin fail_count++; $display("  Test: HIZ with nonzero tail | FAIL"); end

        #10;
        $display("----------------------------------------");
        $display("SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: PASS (all %0d checks passed)", pass_count);
        else
            $display("RESULT: FAIL (%0d passed, %0d failed)", pass_count, fail_count);
        $finish;
    end

endmodule
