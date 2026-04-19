//------------------------------------------------------------------------------
// Input Buffer - Bit-Serial Read (D0-D7) Testbench
//------------------------------------------------------------------------------
// Tests:
//   (1) 4 load/read blocks: addrs 0-7, 8-15, 16-23, 24-31 (adds 16 pixels).
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import input_buffer_pkg::*;

module input_buffer_bit_serial_tb;

    localparam int CLK_PERIOD = 10;

    // Wave: 8 latched lanes — each load block overwrites same lanes with current addr group
    logic [7:0] tb_captured_din_0, tb_captured_din_1, tb_captured_din_2, tb_captured_din_3;
    logic [7:0] tb_captured_din_4, tb_captured_din_5, tb_captured_din_6, tb_captured_din_7;

    // Wave helpers
    logic       tb_pi_load_trigger;   // High while TB drives data-load writes (PI-like load phase)
    logic [3:0] tb_load_pixel_count;  // Counts loaded pixels in current load block: 0..8

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

    assign tb_pi_load_trigger = (reg_ctrl == CTRL_DATA_LOAD) && buf_read_write;

    int pass_count, fail_count;
    logic [7:0] stored [0:7];      // expected values at addr 0..7
    logic [7:0] stored_grp2 [0:7]; // expected values at addr 8..15
    logic [7:0] stored_grp3 [0:7]; // expected values at addr 16..23
    logic [7:0] stored_grp4 [0:7]; // expected values at addr 24..31

    task automatic capture_lane(input int i, input logic [7:0] v);
        begin
            unique case (i)
                0: tb_captured_din_0 = v;
                1: tb_captured_din_1 = v;
                2: tb_captured_din_2 = v;
                3: tb_captured_din_3 = v;
                4: tb_captured_din_4 = v;
                5: tb_captured_din_5 = v;
                6: tb_captured_din_6 = v;
                7: tb_captured_din_7 = v;
            endcase
        end
    endtask

    task automatic check_block_bits(
        input string tag,
        input logic [7:0] exp [0:7]
    );
        for (int b = 0; b < 8; b++) begin
            bit_sel = 3'(b);
            @(posedge clk);
            if (D0 == exp[0][b] && D1 == exp[1][b] && D2 == exp[2][b] &&
                D3 == exp[3][b] && D4 == exp[4][b] && D5 == exp[5][b] &&
                D6 == exp[6][b] && D7 == exp[7][b]) begin
                pass_count++;
                $display("  Test: bit_sel=%0d (%s) | Expected: %b%b%b%b%b%b%b%b | Actual: %b%b%b%b%b%b%b%b | PASS", b, tag,
                    exp[0][b],exp[1][b],exp[2][b],exp[3][b],exp[4][b],exp[5][b],exp[6][b],exp[7][b],
                    D0,D1,D2,D3,D4,D5,D6,D7);
            end else begin
                fail_count++;
                $display("  Test: bit_sel=%0d (%s) | Expected: %b%b%b%b%b%b%b%b | Actual: %b%b%b%b%b%b%b%b | FAIL", b, tag,
                    exp[0][b],exp[1][b],exp[2][b],exp[3][b],exp[4][b],exp[5][b],exp[6][b],exp[7][b],
                    D0,D1,D2,D3,D4,D5,D6,D7);
            end
        end
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
        tb_load_pixel_count = 4'd0;
        for (int i = 0; i < 8; i++) begin
            stored[i] = 0; stored_grp2[i] = 0; stored_grp3[i] = 0; stored_grp4[i] = 0;
        end
        tb_captured_din_0 = '0; tb_captured_din_1 = '0; tb_captured_din_2 = '0; tb_captured_din_3 = '0;
        tb_captured_din_4 = '0; tb_captured_din_5 = '0; tb_captured_din_6 = '0; tb_captured_din_7 = '0;
        #(2*CLK_PERIOD);
        rst_n = 1;
        #(2*CLK_PERIOD);

        $display("----------------------------------------");
        $display("Input Buffer Bit-Serial (D0-D7) Tests");
        $display("Summary: 32 pixels, bit-serial read over 4 address blocks");
        $display("----------------------------------------");

        // ---- Block 1: addr 0..7 ----
        reg_ctrl = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        tb_load_pixel_count = 4'd0;
        for (int i = 0; i < 8; i++) begin
            stored[i] = 8'(i * 17 + 1); // 0x01, 0x12, ...
            buf_reg_add = 6'(i);
            data_in = stored[i];
            @(posedge clk); @(posedge clk);
            capture_lane(i, data_in);
            tb_load_pixel_count = 4'(i + 1);
        end
        reg_ctrl = CTRL_COMPUTE;
        buf_read_write = 1'b0;
        tb_load_pixel_count = 4'd0;
        buf_reg_add = 6'd0;
        $display("--- Block 1: buf_reg_add=0, addr 0-7 ---");
        check_block_bits("addr 0-7", stored);

        // ---- Block 2: addr 8..15 ----
        reg_ctrl = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        tb_load_pixel_count = 4'd0;
        for (int i = 0; i < 8; i++) begin
            stored_grp2[i] = 8'((i + 2) * 13); // 0x1A, 0x27, ...
            buf_reg_add = 6'(8 + i);
            data_in = stored_grp2[i];
            @(posedge clk); @(posedge clk);
            capture_lane(i, data_in);
            tb_load_pixel_count = 4'(i + 1);
        end
        reg_ctrl = CTRL_COMPUTE;
        buf_read_write = 1'b0;
        tb_load_pixel_count = 4'd0;
        buf_reg_add = 6'd8;
        $display("--- Block 2: buf_reg_add=8, addr 8-15 ---");
        check_block_bits("addr 8-15", stored_grp2);

        // ---- Block 3: addr 16..23 ----
        reg_ctrl = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        tb_load_pixel_count = 4'd0;
        for (int i = 0; i < 8; i++) begin
            stored_grp3[i] = 8'((i + 5) * 9 + 3);
            buf_reg_add = 6'(16 + i);
            data_in = stored_grp3[i];
            @(posedge clk); @(posedge clk);
            capture_lane(i, data_in);
            tb_load_pixel_count = 4'(i + 1);
        end
        reg_ctrl = CTRL_COMPUTE;
        buf_read_write = 1'b0;
        tb_load_pixel_count = 4'd0;
        buf_reg_add = 6'd16;
        $display("--- Block 3: buf_reg_add=16, addr 16-23 ---");
        check_block_bits("addr 16-23", stored_grp3);

        // ---- Block 4: addr 24..31 ----
        reg_ctrl = CTRL_DATA_LOAD;
        buf_read_write = 1'b1;
        tb_load_pixel_count = 4'd0;
        for (int i = 0; i < 8; i++) begin
            stored_grp4[i] = 8'((i + 7) * 11 + 5);
            buf_reg_add = 6'(24 + i);
            data_in = stored_grp4[i];
            @(posedge clk); @(posedge clk);
            capture_lane(i, data_in);
            tb_load_pixel_count = 4'(i + 1);
        end
        reg_ctrl = CTRL_COMPUTE;
        buf_read_write = 1'b0;
        tb_load_pixel_count = 4'd0;
        buf_reg_add = 6'd24;
        $display("--- Block 4: buf_reg_add=24, addr 24-31 ---");
        check_block_bits("addr 24-31", stored_grp4);

        #(2*CLK_PERIOD);
        // TB REPORT: printed last so it appears at the end of target/input_buffer/<tb>_log.txt
        $display("");
        $display("//==============================================================================");
        $display("// TB REPORT  input_buffer_bit_serial_tb");
        $display("// Bit-serial D0..D7: four 8-pixel blocks (addrs 0-7, 8-15, 16-23, 24-31)");
        $display("//==============================================================================");
        $display("SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: PASS (bit-serial checks)");
        else
            $display("RESULT: FAIL (%0d passed, %0d failed)", pass_count, fail_count);
        $finish;
    end

endmodule
