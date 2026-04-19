//------------------------------------------------------------------------------
// Input Buffer - Reset Behavior Focused Testbench
//------------------------------------------------------------------------------
// Focus:
//   1) Reset while loading bytes into buffer.
//   2) Reset while reading bit-serial outputs (D0..D7).
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import input_buffer_pkg::*;

module input_buffer_reset_behavior_tb;

    localparam int CLK_PERIOD = 10;
    localparam int RESET_ADDR = 20;

    // Wave helpers (explicitly show load trigger and pixel counter)
    logic       tb_pi_load_trigger;
    logic [3:0] tb_load_pixel_count;

    logic clk, rst_n;
    logic [7:0] data_in;
    logic [2:0] reg_ctrl;
    logic buf_read_write;
    logic [5:0] buf_reg_add;
    logic [2:0] bit_sel;
    logic ready;
    logic [7:0] buf_data;
    logic D0, D1, D2, D3, D4, D5, D6, D7;

    logic [7:0] load_vals [0:7];
    int pass_count, fail_count;

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

    assign tb_pi_load_trigger = (reg_ctrl == CTRL_DATA_LOAD) && buf_read_write;

    task automatic check(input bit cond, input string pass_msg, input string fail_msg);
        begin
            if (cond) begin
                pass_count++;
                $display("  PASS: %s", pass_msg);
            end else begin
                fail_count++;
                $display("  FAIL: %s", fail_msg);
            end
        end
    endtask

    initial begin
        // Init
        rst_n = 0;
        reg_ctrl = CTRL_IDLE;
        buf_read_write = 0;
        buf_reg_add = 0;
        data_in = 0;
        bit_sel = 0;
        tb_load_pixel_count = 0;
        pass_count = 0;
        fail_count = 0;

        for (int i = 0; i < 8; i++) begin
            load_vals[i] = 8'((i + 1) * 8'h13); // deterministic non-zero pattern
        end

        repeat (2) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("----------------------------------------------------");
        $display("Input Buffer Reset Behavior Test");
        $display("----------------------------------------------------");

        // ------------------------------------------------------------
        // A) Reset while loading
        // ------------------------------------------------------------
        $display("A) Reset while DATA_LOAD is active");
        reg_ctrl = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        tb_load_pixel_count = 0;

        // Write first 4 pixels (addr 16..19)
        for (int i = 0; i < 4; i++) begin
            buf_reg_add = 6'(16 + i);
            data_in = load_vals[i];
            @(posedge clk);
            @(posedge clk);
            tb_load_pixel_count = 4'(i + 1);
        end

        // Write addr20, then assert reset
        buf_reg_add = RESET_ADDR[5:0];
        data_in = 8'hA5;
        @(posedge clk);
        @(posedge clk);
        tb_load_pixel_count = 4'd5;

        rst_n = 1'b0;
        tb_load_pixel_count = 4'd0;
        @(posedge clk);
        @(posedge clk);
        // Prevent immediate rewrite of addr20 after reset deassertion.
        reg_ctrl = CTRL_IDLE;
        buf_read_write = 1'b0;
        rst_n = 1'b1;
        @(posedge clk);

        // Verify address cleared by reset
        reg_ctrl = CTRL_WEIGHT_READ;
        buf_read_write = 1'b0;
        buf_reg_add = RESET_ADDR[5:0];
        @(posedge clk);
        check(
            buf_data == 8'h00,
            $sformatf("addr %0d cleared to 0 after reset during load", RESET_ADDR),
            $sformatf("addr %0d expected 0x00, got 0x%02x", RESET_ADDR, buf_data)
        );

        // ------------------------------------------------------------
        // B) Load 8 pixels and verify bit-serial baseline
        // ------------------------------------------------------------
        $display("B) Baseline bit-serial before reset");
        reg_ctrl = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        tb_load_pixel_count = 4'd0;
        for (int i = 0; i < 8; i++) begin
            buf_reg_add = 6'(24 + i); // 24..31
            data_in = load_vals[i];
            @(posedge clk);
            @(posedge clk);
            tb_load_pixel_count = 4'(i + 1);
        end

        reg_ctrl = CTRL_COMPUTE;
        buf_read_write = 1'b0;
        tb_load_pixel_count = 4'd0;
        buf_reg_add = 6'd24;
        bit_sel = 3'd0;
        @(posedge clk);
        check(
            {D7,D6,D5,D4,D3,D2,D1,D0} ==
            {load_vals[7][0],load_vals[6][0],load_vals[5][0],load_vals[4][0],
             load_vals[3][0],load_vals[2][0],load_vals[1][0],load_vals[0][0]},
            "bit-serial matches loaded bytes before reset",
            "bit-serial mismatch before reset"
        );

        // ------------------------------------------------------------
        // C) Reset during bit-serial
        // ------------------------------------------------------------
        $display("C) Reset while COMPUTE/bit-serial is active");
        bit_sel = 3'd3;
        @(posedge clk);
        rst_n = 1'b0;
        @(posedge clk);
        check(
            D0==1'b0 && D1==1'b0 && D2==1'b0 && D3==1'b0 &&
            D4==1'b0 && D5==1'b0 && D6==1'b0 && D7==1'b0,
            "D0..D7 forced low during reset",
            "D0..D7 not all zero during reset"
        );
        rst_n = 1'b1;
        @(posedge clk);

        // Confirm memory cleared after reset by reading from 24
        reg_ctrl = CTRL_WEIGHT_READ;
        buf_read_write = 1'b0;
        buf_reg_add = 6'd24;
        @(posedge clk);
        check(
            buf_data == 8'h00,
            "buffer content cleared after reset during compute",
            $sformatf("buffer[24] expected 0x00 after reset, got 0x%02x", buf_data)
        );

        // TB REPORT: printed last so it appears at the end of target/input_buffer/<tb>_log.txt
        $display("");
        $display("//==============================================================================");
        $display("// TB REPORT  input_buffer_reset_behavior_tb");
        $display("// Reset during CTRL_DATA_LOAD and during COMPUTE/bit-serial");
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
