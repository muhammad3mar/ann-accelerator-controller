//------------------------------------------------------------------------------
// Input Buffer - Write and Full-Byte Read Testbench
//------------------------------------------------------------------------------
// Tests: Write path (CTRL_DATA_LOAD), full-byte read path (buf_data),
//       ready signal for write/read. Multiple addresses and data values.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import input_buffer_pkg::*;

module input_buffer_write_read_tb;

    localparam int CLK_PERIOD = 10;

    logic clk, rst_n;
    logic [7:0] data_in;
    logic [2:0] reg_ctrl;
    logic buf_read_write;
    logic [5:0] buf_reg_add;
    logic [2:0] bit_sel;
    logic ready;
    logic [7:0] buf_data;
    logic D0, D1, D2, D3, D4, D5, D6, D7;

    input_buffer dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .ready(ready),
        .reg_ctrl(reg_ctrl),
        .buf_read_write(buf_read_write),
        .buf_reg_add(buf_reg_add),
        .bit_sel(bit_sel),
        .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3),
        .D4(D4), .D5(D5), .D6(D6), .D7(D7)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    int pass_count, fail_count;

    task write_addr(input logic [5:0] addr, input logic [7:0] data);
        reg_ctrl    = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        buf_reg_add = addr;
        data_in     = data;
        bit_sel     = 3'd0;
        @(posedge clk);
        @(posedge clk);  // write happens on first posedge after enable
    endtask

    task read_addr(input logic [5:0] addr, output logic [7:0] data);
        reg_ctrl    = CTRL_WEIGHT_READ;
        buf_read_write = 1'b0;
        buf_reg_add = addr;
        bit_sel     = 3'd0;
        @(posedge clk);
        data = buf_data;  // combinational read
    endtask

    initial begin
        rst_n = 0;
        reg_ctrl = CTRL_IDLE;
        buf_read_write = 0;
        buf_reg_add = 0;
        data_in = 0;
        bit_sel = 0;
        pass_count = 0;
        fail_count = 0;
        #(2*CLK_PERIOD);
        rst_n = 1;
        #(2*CLK_PERIOD);

        $display("----------------------------------------");
        $display("Input Buffer Write/Read Tests");
        $display("Summary: Tests write path (CTRL_DATA_LOAD), full-byte read (buf_data),");
        $display("         and ready signal for multiple addresses (0, 7, 63).");
        $display("----------------------------------------");
        // Write to addr 0, 7, 63; then read back
        write_addr(6'd0,  8'hA5);
        write_addr(6'd7,  8'h3C);
        write_addr(6'd63, 8'hF0);

        begin
            logic [7:0] rd;
            read_addr(6'd0, rd);
            if (rd == 8'hA5) begin pass_count++; $display("  Test: Read addr 0 | Expected: 0xA5 | Actual: 0x%02X | PASS", rd); end
            else begin fail_count++; $display("  Test: Read addr 0 | Expected: 0xA5 | Actual: 0x%02X | FAIL", rd); end
        end
        begin
            logic [7:0] rd;
            read_addr(6'd7, rd);
            if (rd == 8'h3C) begin pass_count++; $display("  Test: Read addr 7 | Expected: 0x3C | Actual: 0x%02X | PASS", rd); end
            else begin fail_count++; $display("  Test: Read addr 7 | Expected: 0x3C | Actual: 0x%02X | FAIL", rd); end
        end
        begin
            logic [7:0] rd;
            read_addr(6'd63, rd);
            if (rd == 8'hF0) begin pass_count++; $display("  Test: Read addr 63 | Expected: 0xF0 | Actual: 0x%02X | PASS", rd); end
            else begin fail_count++; $display("  Test: Read addr 63 | Expected: 0xF0 | Actual: 0x%02X | FAIL", rd); end
        end

        // Check ready during write (valid addr)
        reg_ctrl = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        buf_reg_add = 6'd10;
        @(posedge clk);
        if (ready) begin pass_count++; $display("  Test: ready during DATA_LOAD write | Expected: 1 | Actual: %0d | PASS", ready); end
        else begin fail_count++; $display("  Test: ready during DATA_LOAD write | Expected: 1 | Actual: %0d | FAIL", ready); end

        // Check ready during read (valid addr)
        reg_ctrl = CTRL_WEIGHT_READ;
        buf_read_write = 1'b0;
        buf_reg_add = 6'd10;
        @(posedge clk);
        if (ready) begin pass_count++; $display("  Test: ready during WEIGHT_READ | Expected: 1 | Actual: %0d | PASS", ready); end
        else begin fail_count++; $display("  Test: ready during WEIGHT_READ | Expected: 1 | Actual: %0d | FAIL", ready); end

        #(2*CLK_PERIOD);
        $display("----------------------------------------");
        $display("SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: PASS (all %0d checks passed)", pass_count);
        else
            $display("RESULT: FAIL (%0d passed, %0d failed)", pass_count, fail_count);
        $finish;
    end

endmodule
