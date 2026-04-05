//------------------------------------------------------------------------------
// Parallel Interface - Field Extraction Testbench
//------------------------------------------------------------------------------
// Tests: data = host_data[31:24], address = decode(host_data[23:0]), cmd = host_cmd
//       for several host_data / host_cmd patterns (ann_core_word host layout).
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import parallel_interface_pkg::*;

module parallel_interface_extract_tb;

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
        $display("Parallel Interface Field Extraction Tests");
        $display("Summary: data=host_data[31:24], addr=decode tail[23:0], cmd=host_cmd.");
        $display("----------------------------------------");

        // Pattern 1: idle
        host_data = 32'd0;
        host_cmd  = CMD_HIZ;
        #1;
        if (data == 8'd0 && address == 16'd0 && cmd == CMD_HIZ && !valid)
            begin pass_count++; $display("  Test: idle | PASS"); end
        else
            begin fail_count++; $display("  Test: idle | FAIL data=%02X addr=%04X cmd=%b valid=%0d", data, address, cmd, valid); end

        // Pattern 2: data MSB byte only (tail zero); command shown on cmd port
        host_data = {8'hA5, 24'd0};
        host_cmd  = CMD_READ;
        #1;
        if (data == 8'hA5 && address == 16'd0 && cmd == CMD_READ)
            begin pass_count++; $display("  Test: data 0xA5 tail=0 cmd=READ | PASS"); end
        else
            begin fail_count++; $display("  Test: data field | FAIL"); end

        // Pattern 3: address via ann tail
        host_data = build_host_ann_word(8'd0, 16'h1234);
        host_cmd  = CMD_READ;
        #1;
        if (data == 8'd0 && address == 16'h1234 && cmd == CMD_READ)
            begin pass_count++; $display("  Test: addr 0x1234 via tail | PASS"); end
        else
            begin fail_count++; $display("  Test: addr field | FAIL addr=%04X", address); end

        // Pattern 4: cmd port only (payload zero)
        host_data = 32'd0;
        host_cmd  = 3'b101;
        #1;
        if (data == 8'd0 && address == 16'd0 && cmd == 3'b101)
            begin pass_count++; $display("  Test: cmd 101 | PASS"); end
        else
            begin fail_count++; $display("  Test: cmd field | FAIL cmd=%b", cmd); end

        // Pattern 5: all ones in host_data; illegal one-hot tail decodes to addr 0
        host_data = 32'hFFFFFFFF;
        host_cmd  = 3'b111;
        #1;
        if (data == 8'hFF && address == 16'd0 && cmd == 3'b111)
            begin pass_count++; $display("  Test: host_data all 1s | PASS"); end
        else
            begin fail_count++; $display("  Test: host_data all 1s | FAIL data=%02X addr=%04X", data, address); end

        // Pattern 6: PROG-style payload
        host_data = build_host_ann_word(8'h0F, 16'hFF00);
        host_cmd  = CMD_PROG;
        #1;
        if (data == 8'h0F && address == 16'hFF00 && cmd == CMD_PROG)
            begin pass_count++; $display("  Test: PROG addr=0xFF00 data=0x0F | PASS"); end
        else
            begin fail_count++; $display("  Test: PROG pattern | FAIL"); end

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
