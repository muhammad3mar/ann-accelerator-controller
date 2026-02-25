//------------------------------------------------------------------------------
// Parallel Interface - Valid Signal Testbench
//------------------------------------------------------------------------------
// Tests: valid=0 when host_data idle (cmd 000, data 0, address 0);
//       valid=1 when cmd != 000 or data != 0 or address != 0.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import parallel_interface_pkg::*;

module parallel_interface_valid_tb;

    logic clk, reset;
    logic [31:0] host_data;
    logic valid;
    logic [7:0] data;
    logic [15:0] address;
    logic [2:0] cmd;

    parallel_interface dut (
        .clk(clk),
        .reset(reset),
        .host_data(host_data),
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
        pass_count = 0;
        fail_count = 0;
        #20;

        $display("----------------------------------------");
        $display("Parallel Interface Valid Signal Tests");
        $display("Summary: Tests valid=0 when idle (cmd 000, data 0, addr 0); valid=1 when");
        $display("         cmd != 000 or data != 0 or address != 0.");
        $display("----------------------------------------");

        // (a) host_data = 0 -> valid = 0
        host_data = 32'd0;
        #1;
        if (!valid) begin pass_count++; $display("  Test: valid when host_data=0 | Expected: 0 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when host_data=0 | Expected: 0 | Actual: %0d | FAIL", valid); end

        // (b) cmd != 000 -> valid = 1
        host_data = {5'd0, CMD_READ, 16'd0, 8'd0};
        #1;
        if (valid) begin pass_count++; $display("  Test: valid when cmd=001 (READ) | Expected: 1 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when cmd=001 (READ) | Expected: 1 | Actual: %0d | FAIL", valid); end

        host_data = {5'd0, CMD_PROG, 16'd0, 8'd0};
        #1;
        if (valid) begin pass_count++; $display("  Test: valid when cmd=010 (PROG) | Expected: 1 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when cmd=010 (PROG) | Expected: 1 | Actual: %0d | FAIL", valid); end

        host_data = {5'd0, CMD_ERASE, 16'd0, 8'd0};
        #1;
        if (valid) begin pass_count++; $display("  Test: valid when cmd=011 (ERASE) | Expected: 1 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when cmd=011 (ERASE) | Expected: 1 | Actual: %0d | FAIL", valid); end

        host_data = {5'd0, CMD_INF, 16'd0, 8'd0};
        #1;
        if (valid) begin pass_count++; $display("  Test: valid when cmd=100 (INF) | Expected: 1 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when cmd=100 (INF) | Expected: 1 | Actual: %0d | FAIL", valid); end

        // (c) cmd=000 but data != 0 -> valid = 1
        host_data = {5'd0, 3'b000, 16'd0, 8'h01};
        #1;
        if (valid) begin pass_count++; $display("  Test: valid when cmd=000 data=0x01 | Expected: 1 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when cmd=000 data=0x01 | Expected: 1 | Actual: %0d | FAIL", valid); end

        // (d) cmd=000 but address != 0 -> valid = 1
        host_data = {5'd0, 3'b000, 16'h0001, 8'd0};
        #1;
        if (valid) begin pass_count++; $display("  Test: valid when cmd=000 address!=0 | Expected: 1 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when cmd=000 address!=0 | Expected: 1 | Actual: %0d | FAIL", valid); end

        // (e) cmd=000, data=0, address=0 -> valid = 0
        host_data = 32'd0;
        #1;
        if (!valid) begin pass_count++; $display("  Test: valid when cmd=000 data=0 addr=0 (idle) | Expected: 0 | Actual: %0d | PASS", valid); end
        else begin fail_count++; $display("  Test: valid when cmd=000 data=0 addr=0 (idle) | Expected: 0 | Actual: %0d | FAIL", valid); end

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
