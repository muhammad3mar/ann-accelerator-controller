//------------------------------------------------------------------------------
// Parallel Interface - Field Extraction Testbench
//------------------------------------------------------------------------------
// Tests: data = host_data[31:24], address = decode(host_data[23:0]), cmd = host_cmd
//       for several host_data / host_cmd patterns (ann_address host layout).
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../rtl/common/macros.svh"

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

    function automatic logic [15:0] exp_packed_addr(input logic [15:0] par);
        return {6'b0, par[9:8], par[7:6], par[5:3], par[2:0]};
    endfunction

    task automatic log_decode(input string tag);
        $display("  %s", tag);
        $display("    host_data hex : 0x%08h", host_data);
        $display("    host_data bin : %08b-%04b-%04b-%08b-%08b",
                 host_data[31:24], host_data[23:20], host_data[19:16], host_data[15:8], host_data[7:0]);
        $display("    host_cmd      : %b", host_cmd);
        $display("    PI outputs    : data=0x%02h addr=0x%04h cmd=%b valid=%0d", data, address, cmd, valid);
        $display("    decoded idx   : PA(block)=%0d SA(sub)=%0d col=%0d row=%0d",
                 address[9:8], address[7:6], address[5:3], address[2:0]);
    endtask

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
        log_decode("Test: idle");
        if (data == 8'd0 && address == 16'd0 && cmd == CMD_HIZ && !valid)
            begin pass_count++; $display("    RESULT: PASS"); end
        else
            begin fail_count++; $display("    RESULT: FAIL"); end

        // Pattern 2: data MSB byte only (tail zero); command shown on cmd port
        host_data = {8'hA5, 24'd0};
        host_cmd  = CMD_READ;
        #1;
        log_decode("Test: data 0xA5 tail=0 cmd=READ");
        if (data == 8'hA5 && address == 16'd0 && cmd == CMD_READ)
            begin pass_count++; $display("    RESULT: PASS"); end
        else
            begin fail_count++; $display("    RESULT: FAIL"); end

        // Pattern 3: address via ann tail (packed parallel_addr arg to build_host_ann_word)
        begin
            logic [15:0] par;
            par = 16'h1234;
            host_data = build_host_ann_word(8'd0, par);
            host_cmd  = CMD_READ;
            #1;
            log_decode($sformatf("Test: addr tail decode (arg=%04h)", par));
            if (data == 8'd0 && address == exp_packed_addr(par) && cmd == CMD_READ)
                begin pass_count++; $display("    RESULT: PASS (exp addr=%04h)", exp_packed_addr(par)); end
            else
                begin fail_count++; $display("    RESULT: FAIL (exp addr=%04h)", exp_packed_addr(par)); end
        end

        // Pattern 4: cmd port only (payload zero)
        host_data = 32'd0;
        host_cmd  = 3'b101;
        #1;
        log_decode("Test: cmd 101 (payload zero)");
        if (data == 8'd0 && address == 16'd0 && cmd == 3'b101)
            begin pass_count++; $display("    RESULT: PASS"); end
        else
            begin fail_count++; $display("    RESULT: FAIL"); end

        // Pattern 5: all ones in host_data; illegal one-hot tail -> valid must be 0
        host_data = 32'hFFFFFFFF;
        host_cmd  = 3'b111;
        #1;
        log_decode("Test: host_data all 1s");
        if (data == 8'hFF && address == 16'd0 && cmd == 3'b111 && !valid)
            begin pass_count++; $display("    RESULT: PASS"); end
        else
            begin fail_count++; $display("    RESULT: FAIL"); end

        // Pattern 6: PROG-style payload
        begin
            logic [15:0] par;
            par = 16'hFF00;
            host_data = build_host_ann_word(8'h0F, par);
            host_cmd  = CMD_PROG;
            #1;
            log_decode($sformatf("Test: PROG packed addr (arg=%04h) data=0x0F", par));
            if (data == 8'h0F && address == exp_packed_addr(par) && cmd == CMD_PROG)
                begin pass_count++; $display("    RESULT: PASS (exp addr=%04h)", exp_packed_addr(par)); end
            else begin fail_count++; $display("    RESULT: FAIL (exp addr=%04h)", exp_packed_addr(par)); end
        end

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
