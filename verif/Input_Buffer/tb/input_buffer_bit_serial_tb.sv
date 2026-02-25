//------------------------------------------------------------------------------
// Input Buffer - Bit-Serial Read (D0-D7) Testbench
//------------------------------------------------------------------------------
// Tests: (1) First 8 pixels (addr 0-7): D0-D7 bit-serial LSB-first.
//       (2) Next 8 pixels (addr 8-15): buf_reg_add=8, D0-D7 output second group.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import input_buffer_pkg::*;

module input_buffer_bit_serial_tb;

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
    logic [7:0] stored [0:7];      // expected values at addr 0..7
    logic [7:0] stored_grp2 [0:7]; // expected values at addr 8..15

    initial begin
        rst_n = 0;
        reg_ctrl = CTRL_IDLE;
        buf_read_write = 0;
        buf_reg_add = 0;
        data_in = 0;
        bit_sel = 0;
        pass_count = 0;
        fail_count = 0;
        for (int i = 0; i < 8; i++) begin stored[i] = 0; stored_grp2[i] = 0; end
        #(2*CLK_PERIOD);
        rst_n = 1;
        #(2*CLK_PERIOD);

        $display("----------------------------------------");
        $display("Input Buffer Bit-Serial (D0-D7) Tests");
        $display("Summary: Tests bit-serial read: D0-D7 output one bit per channel per cycle");
        $display("         (LSB-first). Block 1: addr 0-7. Block 2: addr 8-15 (buf_reg_add=8).");
        $display("----------------------------------------");
        // ---- Block 1: First 8 pixels (addr 0..7) ----
        reg_ctrl    = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        for (int i = 0; i < 8; i++) begin
            stored[i] = 8'(i * 17 + 1);  // 0x01, 0x12, 0x23, ...
            buf_reg_add = 6'(i);
            data_in     = stored[i];
            @(posedge clk);
            @(posedge clk);
        end

        // Read in bit-serial mode: set COMPUTE, addr=0, cycle bit_sel 0..7
        reg_ctrl    = CTRL_COMPUTE;
        buf_read_write = 1'b0;
        buf_reg_add = 6'd0;

        $display("--- Block 1: buf_reg_add=0, addr 0-7 ---");
        for (int b = 0; b < 8; b++) begin
            bit_sel = 3'(b);
            @(posedge clk);
            if (D0 == stored[0][b] && D1 == stored[1][b] && D2 == stored[2][b] &&
                D3 == stored[3][b] && D4 == stored[4][b] && D5 == stored[5][b] &&
                D6 == stored[6][b] && D7 == stored[7][b]) begin
                pass_count++;
                $display("  Test: bit_sel=%0d (addr 0-7) | Expected: %b%b%b%b%b%b%b%b | Actual: %b%b%b%b%b%b%b%b | PASS", b,
                    stored[0][b],stored[1][b],stored[2][b],stored[3][b],stored[4][b],stored[5][b],stored[6][b],stored[7][b],
                    D0,D1,D2,D3,D4,D5,D6,D7);
            end else begin
                fail_count++;
                $display("  Test: bit_sel=%0d (addr 0-7) | Expected: %b%b%b%b%b%b%b%b | Actual: %b%b%b%b%b%b%b%b | FAIL", b,
                    stored[0][b],stored[1][b],stored[2][b],stored[3][b],stored[4][b],stored[5][b],stored[6][b],stored[7][b],
                    D0,D1,D2,D3,D4,D5,D6,D7);
            end
        end

        // ---- Block 2: Next 8 pixels (addr 8..15), buf_reg_add=8 ----
        reg_ctrl    = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        for (int i = 0; i < 8; i++) begin
            stored_grp2[i] = 8'((i + 2) * 13);  // 0x1A, 0x27, 0x34, ...
            buf_reg_add = 6'(8 + i);
            data_in     = stored_grp2[i];
            @(posedge clk);
            @(posedge clk);
        end

        reg_ctrl    = CTRL_COMPUTE;
        buf_read_write = 1'b0;
        buf_reg_add = 6'd8;  // Switch to next 8 pixels

        $display("--- Block 2: buf_reg_add=8, addr 8-15 ---");
        for (int b = 0; b < 8; b++) begin
            bit_sel = 3'(b);
            @(posedge clk);
            if (D0 == stored_grp2[0][b] && D1 == stored_grp2[1][b] && D2 == stored_grp2[2][b] &&
                D3 == stored_grp2[3][b] && D4 == stored_grp2[4][b] && D5 == stored_grp2[5][b] &&
                D6 == stored_grp2[6][b] && D7 == stored_grp2[7][b]) begin
                pass_count++;
                $display("  Test: bit_sel=%0d (addr 8-15) | Expected: %b%b%b%b%b%b%b%b | Actual: %b%b%b%b%b%b%b%b | PASS", b,
                    stored_grp2[0][b],stored_grp2[1][b],stored_grp2[2][b],stored_grp2[3][b],stored_grp2[4][b],stored_grp2[5][b],stored_grp2[6][b],stored_grp2[7][b],
                    D0,D1,D2,D3,D4,D5,D6,D7);
            end else begin
                fail_count++;
                $display("  Test: bit_sel=%0d (addr 8-15) | Expected: %b%b%b%b%b%b%b%b | Actual: %b%b%b%b%b%b%b%b | FAIL", b,
                    stored_grp2[0][b],stored_grp2[1][b],stored_grp2[2][b],stored_grp2[3][b],stored_grp2[4][b],stored_grp2[5][b],stored_grp2[6][b],stored_grp2[7][b],
                    D0,D1,D2,D3,D4,D5,D6,D7);
            end
        end
        #(2*CLK_PERIOD);
        $display("----------------------------------------");
        $display("SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: PASS (bit-serial: %0d checks, both blocks)", pass_count);
        else
            $display("RESULT: FAIL (%0d passed, %0d failed)", pass_count, fail_count);
        $finish;
    end

endmodule
