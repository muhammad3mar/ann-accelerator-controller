//------------------------------------------------------------------------------
// Parallel Interface - All Commands and Boundary Testbench
//------------------------------------------------------------------------------
// Tests: Each command (HIZ, READ, PROG, ERASE, INF) with non-zero addr/data;
//       boundary: max address and max data.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import parallel_interface_pkg::*;

module parallel_interface_commands_tb;

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
        $display("Parallel Interface Commands Tests");
        $display("Summary: Tests each command (HIZ, READ, PROG, ERASE, INF) with non-zero");
        $display("         addr/data; boundary: max address (0xFFFC) and max data (0xFF).");
        $display("----------------------------------------");

        // CMD_HIZ with non-zero data and address
        host_data = {5'd0, CMD_HIZ, 16'h00FF, 8'hAA};
        #1;
        if (valid && cmd == CMD_HIZ && address == 16'h00FF && data == 8'hAA) begin pass_count++; $display("  Test: CMD_HIZ addr=0x00FF data=0xAA | Expected: valid=1 cmd=HIZ addr=0x00FF data=0xAA | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | PASS", valid, cmd, address, data); end
        else begin fail_count++; $display("  Test: CMD_HIZ addr=0x00FF data=0xAA | Expected: valid=1 cmd=HIZ addr=0x00FF data=0xAA | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | FAIL", valid, cmd, address, data); end

        // CMD_READ
        host_data = {5'd0, CMD_READ, 16'h1100, 8'h11};
        #1;
        if (valid && cmd == CMD_READ && address == 16'h1100 && data == 8'h11) begin pass_count++; $display("  Test: CMD_READ addr=0x1100 data=0x11 | Expected: valid=1 cmd=READ addr=0x1100 data=0x11 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | PASS", valid, cmd, address, data); end
        else begin fail_count++; $display("  Test: CMD_READ addr=0x1100 data=0x11 | Expected: valid=1 cmd=READ addr=0x1100 data=0x11 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | FAIL", valid, cmd, address, data); end

        // CMD_PROG
        host_data = {5'd0, CMD_PROG, 16'h2233, 8'h22};
        #1;
        if (valid && cmd == CMD_PROG && address == 16'h2233 && data == 8'h22) begin pass_count++; $display("  Test: CMD_PROG addr=0x2233 data=0x22 | Expected: valid=1 cmd=PROG addr=0x2233 data=0x22 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | PASS", valid, cmd, address, data); end
        else begin fail_count++; $display("  Test: CMD_PROG addr=0x2233 data=0x22 | Expected: valid=1 cmd=PROG addr=0x2233 data=0x22 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | FAIL", valid, cmd, address, data); end

        // CMD_ERASE
        host_data = {5'd0, CMD_ERASE, 16'h4455, 8'h33};
        #1;
        if (valid && cmd == CMD_ERASE && address == 16'h4455 && data == 8'h33) begin pass_count++; $display("  Test: CMD_ERASE addr=0x4455 data=0x33 | Expected: valid=1 cmd=ERASE addr=0x4455 data=0x33 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | PASS", valid, cmd, address, data); end
        else begin fail_count++; $display("  Test: CMD_ERASE addr=0x4455 data=0x33 | Expected: valid=1 cmd=ERASE addr=0x4455 data=0x33 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | FAIL", valid, cmd, address, data); end

        // CMD_INF
        host_data = {5'd0, CMD_INF, 16'h6677, 8'h44};
        #1;
        if (valid && cmd == CMD_INF && address == 16'h6677 && data == 8'h44) begin pass_count++; $display("  Test: CMD_INF addr=0x6677 data=0x44 | Expected: valid=1 cmd=INF addr=0x6677 data=0x44 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | PASS", valid, cmd, address, data); end
        else begin fail_count++; $display("  Test: CMD_INF addr=0x6677 data=0x44 | Expected: valid=1 cmd=INF addr=0x6677 data=0x44 | Actual: valid=%0d cmd=%b addr=0x%04X data=0x%02X | FAIL", valid, cmd, address, data); end

        // Boundary: max address, max data
        host_data = {5'd0, 3'b100, 16'hFFFC, 8'hFF};
        #1;
        if (valid && cmd == 3'b100 && address == 16'hFFFC && data == 8'hFF) begin pass_count++; $display("  Test: boundary max addr=0xFFFC data=0xFF | Expected: valid=1 addr=0xFFFC data=0xFF | Actual: valid=%0d addr=0x%04X data=0x%02X | PASS", valid, address, data); end
        else begin fail_count++; $display("  Test: boundary max addr=0xFFFC data=0xFF | Expected: valid=1 addr=0xFFFC data=0xFF | Actual: valid=%0d addr=0x%04X data=0x%02X | FAIL", valid, address, data); end

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
