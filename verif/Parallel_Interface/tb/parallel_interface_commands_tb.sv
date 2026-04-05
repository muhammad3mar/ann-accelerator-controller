//------------------------------------------------------------------------------
// Parallel Interface - All Commands and Boundary Testbench
//------------------------------------------------------------------------------
// Tests: Each command on host_cmd with ann-format host_data; CMD_HIZ is not valid.
//        Boundary: max address and max data.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import parallel_interface_pkg::*;

module parallel_interface_commands_tb;

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
        $display("Parallel Interface Commands Tests");
        $display("Summary: host_cmd selects command; host_data is ann_core_word layout.");
        $display("----------------------------------------");

        // CMD_HIZ: valid=0; cmd and decoded payload still driven for observation
        host_cmd  = CMD_HIZ;
        host_data = build_host_ann_word(8'hAA, 16'h00FF);
        #1;
        if (!valid && cmd == CMD_HIZ && address == 16'h00FF && data == 8'hAA)
            begin pass_count++; $display("  Test: CMD_HIZ + payload | valid=0 | PASS"); end
        else
            begin fail_count++; $display("  Test: CMD_HIZ | FAIL valid=%0d", valid); end

        host_cmd  = CMD_READ;
        host_data = build_host_ann_word(8'h11, 16'h1100);
        #1;
        if (valid && cmd == CMD_READ && address == 16'h1100 && data == 8'h11)
            begin pass_count++; $display("  Test: CMD_READ | PASS"); end
        else
            begin fail_count++; $display("  Test: CMD_READ | FAIL"); end

        host_cmd  = CMD_PROG;
        host_data = build_host_ann_word(8'h22, 16'h2233);
        #1;
        if (valid && cmd == CMD_PROG && address == 16'h2233 && data == 8'h22)
            begin pass_count++; $display("  Test: CMD_PROG | PASS"); end
        else
            begin fail_count++; $display("  Test: CMD_PROG | FAIL"); end

        host_cmd  = CMD_ERASE;
        host_data = build_host_ann_word(8'h33, 16'h4455);
        #1;
        if (valid && cmd == CMD_ERASE && address == 16'h4455 && data == 8'h33)
            begin pass_count++; $display("  Test: CMD_ERASE | PASS"); end
        else
            begin fail_count++; $display("  Test: CMD_ERASE | FAIL"); end

        host_cmd  = CMD_INF;
        host_data = build_host_ann_word(8'h44, 16'h6677);
        #1;
        if (valid && cmd == CMD_INF && address == 16'h6677 && data == 8'h44)
            begin pass_count++; $display("  Test: CMD_INF | PASS"); end
        else
            begin fail_count++; $display("  Test: CMD_INF | FAIL"); end

        host_cmd  = CMD_INF;
        host_data = build_host_ann_word(8'hFF, 16'hFFFC);
        #1;
        if (valid && cmd == CMD_INF && address == 16'hFFFC && data == 8'hFF)
            begin pass_count++; $display("  Test: boundary max addr/data | PASS"); end
        else
            begin fail_count++; $display("  Test: boundary | FAIL"); end

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
