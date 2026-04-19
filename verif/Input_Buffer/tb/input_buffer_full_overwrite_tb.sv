//------------------------------------------------------------------------------
// Input Buffer - Full Load then Overwrite Behavior Testbench
//------------------------------------------------------------------------------
// Goal:
//   1) Fill all 64 buffer locations (rows 0..7, cols 0..7).
//   2) Show full-buffer contents.
//   3) Load 10 new pixels to addresses 0..9 and dump all rows after each write
//      to visualize replacement behavior.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import input_buffer_pkg::*;

module input_buffer_full_overwrite_tb;

    localparam int CLK_PERIOD = 10;

    logic clk, rst_n;
    logic [7:0] data_in;
    logic [2:0] reg_ctrl;
    logic       buf_read_write;
    logic [5:0] buf_reg_add;
    logic [2:0] bit_sel;
    logic       ready;
    logic [7:0] buf_data;
    logic D0, D1, D2, D3, D4, D5, D6, D7;

    int pass_count, fail_count;
    logic [7:0] expected [0:63];
    logic [7:0] new_px [0:9];

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

    task automatic dump_all_rows(input string tag);
        int r;
        $display("%s", tag);
        for (r = 0; r < 8; r++) begin
            $display("  row%0d: %02h %02h %02h %02h %02h %02h %02h %02h",
                r,
                dut.buffer_reg[r*8 + 0], dut.buffer_reg[r*8 + 1],
                dut.buffer_reg[r*8 + 2], dut.buffer_reg[r*8 + 3],
                dut.buffer_reg[r*8 + 4], dut.buffer_reg[r*8 + 5],
                dut.buffer_reg[r*8 + 6], dut.buffer_reg[r*8 + 7]);
        end
    endtask

    task automatic write_byte(input logic [5:0] addr, input logic [7:0] val);
        begin
            reg_ctrl = CTRL_DATA_LOAD;
            buf_read_write = 1'b1;
            buf_reg_add = addr;
            data_in = val;
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    task automatic check_addr(input int idx);
        begin
            reg_ctrl = CTRL_WEIGHT_READ;
            buf_read_write = 1'b0;
            buf_reg_add = idx[5:0];
            @(posedge clk);
            if (buf_data === expected[idx]) begin
                pass_count++;
            end else begin
                fail_count++;
                $display("  FAIL check addr=%0d exp=%02h got=%02h", idx, expected[idx], buf_data);
            end
        end
    endtask

    initial begin
        rst_n = 0;
        reg_ctrl = CTRL_IDLE;
        buf_read_write = 1'b0;
        buf_reg_add = 6'd0;
        data_in = 8'd0;
        bit_sel = 3'd0;
        pass_count = 0;
        fail_count = 0;

        for (int i = 0; i < 64; i++) expected[i] = 8'd0;
        for (int i = 0; i < 10; i++) new_px[i] = 8'(8'hA0 + i);

        repeat (2) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("------------------------------------------------------------");
        $display("Input Buffer Full Overwrite Behavior Test");
        $display("Phase 1: Fill all 64 addresses");
        $display("Phase 2: Write 10 new bytes to addr 0..9, dump rows each write");
        $display("------------------------------------------------------------");

        // Phase 1: fill all entries
        for (int a = 0; a < 64; a++) begin
            logic [7:0] v;
            v = 8'((a * 3) + 8'h11);
            write_byte(a[5:0], v);
            expected[a] = v;
        end

        dump_all_rows("After full load (64/64):");

        // Quick verification after full load
        for (int a = 0; a < 64; a++) begin
            check_addr(a);
        end

        // Phase 2: overwrite first 10 addresses
        $display("");
        $display("Overwrite phase: loading 10 new pixels to addr 0..9");
        for (int i = 0; i < 10; i++) begin
            write_byte(i[5:0], new_px[i]);
            expected[i] = new_px[i];
            dump_all_rows($sformatf("After overwrite #%0d (addr=%0d, data=%02h):", i+1, i, new_px[i]));
        end

        // Verify overwritten and untouched ranges
        for (int a = 0; a < 64; a++) begin
            check_addr(a);
        end

        reg_ctrl = CTRL_IDLE;
        buf_read_write = 1'b0;

        // TB REPORT at end of log
        $display("");
        $display("//==============================================================================");
        $display("// TB REPORT  input_buffer_full_overwrite_tb");
        $display("// Full load then overwrite 10 pixels (addr 0..9) with row dumps after each write");
        $display("//==============================================================================");
        $display("SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");

        # (2*CLK_PERIOD);
        $finish;
    end

endmodule
