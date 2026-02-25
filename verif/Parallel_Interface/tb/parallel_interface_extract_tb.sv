//------------------------------------------------------------------------------
// Parallel Interface - Field Extraction Testbench
//------------------------------------------------------------------------------
// Tests: data = host_data[7:0], address = host_data[23:8], cmd = host_data[26:24]
//       for several host_data patterns.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import parallel_interface_pkg::*;

module parallel_interface_extract_tb;

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
        $display("Parallel Interface Field Extraction Tests");
        $display("Summary: Tests extraction of data=host_data[7:0], address=host_data[23:8],");
        $display("         cmd=host_data[26:24] for various host_data patterns.");
        $display("----------------------------------------");

        // Pattern 1: all zeros
        host_data = 32'd0;
        #1;
        if (data == 8'd0 && address == 16'd0 && cmd == 3'b000) begin pass_count++; $display("  Test: host_data=0 | Expected: data=0 addr=0 cmd=000 | Actual: data=0x%02X addr=0x%04X cmd=%b | PASS", data, address, cmd); end
        else begin fail_count++; $display("  Test: host_data=0 | Expected: data=0 addr=0 cmd=000 | Actual: data=0x%02X addr=0x%04X cmd=%b | FAIL", data, address, cmd); end

        // Pattern 2: data only
        host_data = {16'd0, 8'd0, 8'hA5};
        #1;
        if (data == 8'hA5 && address == 16'd0 && cmd == 3'b000) begin pass_count++; $display("  Test: data field 0xA5 | Expected: 0xA5 | Actual: 0x%02X | PASS", data); end
        else begin fail_count++; $display("  Test: data field 0xA5 | Expected: 0xA5 | Actual: 0x%02X | FAIL", data); end

        // Pattern 3: address only (host_data[23:8])
        host_data = {8'd0, 16'h1234, 8'd0};
        #1;
        if (data == 8'd0 && address == 16'h1234 && cmd == 3'b000) begin pass_count++; $display("  Test: address field 0x1234 | Expected: 0x1234 | Actual: 0x%04X | PASS", address); end
        else begin fail_count++; $display("  Test: address field 0x1234 | Expected: 0x1234 | Actual: 0x%04X | FAIL", address); end

        // Pattern 4: cmd only (host_data[26:24])
        host_data = {5'd0, 3'b101, 16'd0, 8'd0};
        #1;
        if (data == 8'd0 && address == 16'd0 && cmd == 3'b101) begin pass_count++; $display("  Test: cmd field 101 | Expected: 101 | Actual: %b | PASS", cmd); end
        else begin fail_count++; $display("  Test: cmd field 101 | Expected: 101 | Actual: %b | FAIL", cmd); end

        // Pattern 5: all ones (mixed)
        host_data = 32'hFFFFFFFF;
        #1;
        if (data == 8'hFF && address == 16'hFFFF && cmd == 3'b111) begin pass_count++; $display("  Test: host_data=all_ones | Expected: data=0xFF addr=0xFFFF cmd=111 | Actual: data=0x%02X addr=0x%04X cmd=%b | PASS", data, address, cmd); end
        else begin fail_count++; $display("  Test: host_data=all_ones | Expected: data=0xFF addr=0xFFFF cmd=111 | Actual: data=0x%02X addr=0x%04X cmd=%b | FAIL", data, address, cmd); end

        // Pattern 6: specific layout cmd=010, addr=0xFF00, data=0x0F
        host_data = {5'd0, 3'b010, 16'hFF00, 8'h0F};
        #1;
        if (data == 8'h0F && address == 16'hFF00 && cmd == 3'b010) begin pass_count++; $display("  Test: cmd=PROG addr=0xFF00 data=0x0F | Expected: data=0x0F addr=0xFF00 cmd=010 | Actual: data=0x%02X addr=0x%04X cmd=%b | PASS", data, address, cmd); end
        else begin fail_count++; $display("  Test: cmd=PROG addr=0xFF00 data=0x0F | Expected: data=0x0F addr=0xFF00 cmd=010 | Actual: data=0x%02X addr=0x%04X cmd=%b | FAIL", data, address, cmd); end

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
