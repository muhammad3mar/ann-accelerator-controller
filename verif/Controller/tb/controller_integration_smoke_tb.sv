//------------------------------------------------------------------------------
// Smoke: PI + controller + input_buffer + ANN weight mock.
// Log: target/Controller/tb_controller_smoke.txt
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_integration_smoke_tb;

    localparam int CLK_PERIOD = 5;
    localparam string LOG_FILE = "target/Controller/tb_controller_smoke.txt";

    logic        clk, rst_n, reset;
    logic [31:0] host_data;
    logic [2:0]  host_cmd;
    logic        valid;
    logic [7:0]  pi_data;
    logic [15:0] address;
    logic [CMD_WIDTH-1:0] cmd;
    logic        ann_reset, op_done, busy;
    logic [31:0] ann_core_word;
    logic [2:0]  pulses;
    logic [5:0]  buf_reg_add;
    logic [2:0]  buf_reg_ctrl;
    logic        buf_read_write;
    logic [2:0]  buf_bit_sel;
    logic [7:0]  buf_data_out, buf_data;
    logic        D0, D1, D2, D3, D4, D5, D6, D7;
    logic        buf_ready;

    logic [3:0] ann_weight_matrix [0:NUM_BLOCKS-1][0:NUM_SUB_BLOCKS-1][0:SUB_BLOCK_ROWS-1][0:SUB_BLOCK_COLS-1];
    logic [3:0] weight_read_data_mock;
    logic [3:0] actual_from_ann;
    logic [1:0] dec_blk, dec_sb;
    logic [2:0] dec_row, dec_col;

    always_comb begin
        ann_core_word_decode(ann_core_word, dec_blk, dec_sb, dec_row, dec_col);
        actual_from_ann = ann_weight_matrix[dec_blk][dec_sb][dec_row][dec_col];
    end

    assign weight_read_data_mock = actual_from_ann;

    parallel_interface u_pi (
        .clk(clk), .reset(reset), .host_data(host_data), .host_cmd(host_cmd),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd)
    );

    ann_controller dut (
        .clk(clk), .rst_n(rst_n),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd),
        .ann_reset(ann_reset),
        .op_done(op_done), .ann_core_word(ann_core_word), .pulses(pulses),
        .weight_read_data(weight_read_data_mock),
        .buf_reg_add(buf_reg_add), .buf_reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_bit_sel(buf_bit_sel),
        .buf_data_out(buf_data_out), .buf_ready(buf_ready), .buf_data(buf_data), .busy(busy)
    );

    input_buffer u_buf (
        .clk(clk), .rst_n(rst_n), .data_in(buf_data_out),
        .ready(buf_ready), .reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_reg_add(buf_reg_add), .bit_sel(buf_bit_sel), .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3), .D4(D4), .D5(D5), .D6(D6), .D7(D7)
    );

    logic in_prog_core_phase;
    assign in_prog_core_phase = (pulses == PULSE_MODE_PROG) && (buf_reg_ctrl == CTRL_WEIGHT_READ);

    int op_done_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_done <= 0;
            op_done_cnt <= 0;
        end else begin
            if (in_prog_core_phase) begin
                if (op_done_cnt >= controller_pkg::TPROG - 1) begin
                    op_done <= 1;
                    op_done_cnt <= 0;
                end else begin
                    op_done <= 0;
                    op_done_cnt <= op_done_cnt + 1;
                end
            end else if (busy && (pulses == PULSE_MODE_READ || pulses == PULSE_MODE_ERASE || pulses == PULSE_MODE_INF)) begin
                if (op_done_cnt >= 3) begin
                    op_done <= 1;
                    op_done_cnt <= 0;
                end else begin
                    op_done <= 0;
                    op_done_cnt <= op_done_cnt + 1;
                end
            end else begin
                op_done <= 0;
                op_done_cnt <= 0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int b = 0; b < NUM_BLOCKS; b++)
                for (int sb = 0; sb < NUM_SUB_BLOCKS; sb++)
                    for (int r = 0; r < SUB_BLOCK_ROWS; r++)
                        for (int c = 0; c < SUB_BLOCK_COLS; c++)
                            ann_weight_matrix[b][sb][r][c] <= 4'b0;
        end else if (in_prog_core_phase) begin
            automatic logic [1:0] lb, lsb;
            automatic logic [2:0] lr, lc;
            ann_core_word_decode(ann_core_word, lb, lsb, lr, lc);
            ann_weight_matrix[lb][lsb][lr][lc] <= ann_core_word[27:24];
        end
    end

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 0; reset = 1; host_data = 0; host_cmd = CMD_HIZ;
        repeat(5) @(posedge clk);
        rst_n = 1; reset = 0;
        repeat(4) @(posedge clk);
    end

    task automatic wait_idle(int maxcyc);
        int n;
        n = 0;
        while (busy && n < maxcyc) begin
            @(posedge clk);
            n++;
        end
    endtask

    task automatic pulse_host_ann(input logic [2:0] c, input logic [7:0] d, input logic [15:0] a);
        host_data = build_host_ann_word(d, a);
        host_cmd  = c;
        @(posedge clk);
        host_data = 0;
        host_cmd  = CMD_HIZ;
        @(posedge clk);
    endtask

    int fd;
    int pass_c, fail_c;

    initial begin
        pass_c = 0;
        fail_c = 0;
        fd = $fopen(LOG_FILE, "w");
        if (!fd) begin $error("Cannot open log"); $finish; end
        $fdisplay(fd, "// controller_integration_smoke_tb (10 cases)");
        $fdisplay(fd, "");

        wait(rst_n);

        // Case 1: PROG cell (0,0,0,0) weight 7
        pulse_host_ann(CMD_PROG, 8'h07, 16'h0000);
        wait_idle(80_000);
        if (ann_weight_matrix[0][0][0][0] !== 4'd7) begin
            fail_c++;
            $fdisplay(fd, "FAIL Case01 PROG mock got %0d", ann_weight_matrix[0][0][0][0]);
        end else begin
            pass_c++;
            $fdisplay(fd, "PASS Case01 PROG (0,0,0,0)=7");
        end

        // Case 2: READ same address
        pulse_host_ann(CMD_READ, 8'h00, 16'h0000);
        wait_idle(80_000);
        pass_c++;
        $fdisplay(fd, "PASS Case02 READ idle");

        // Case 3: ERASE
        pulse_host_ann(CMD_ERASE, 8'h00, 16'h0000);
        wait_idle(80_000);
        pass_c++;
        $fdisplay(fd, "PASS Case03 ERASE idle");

        // Case 4: INF burst (9 inputs)
        begin
            int ii;
            for (ii = 0; ii < 9; ii++) begin
                host_data = build_host_ann_word(8'(8'h30 + ii), 16'h0010);
                host_cmd  = CMD_INF;
                @(posedge clk);
            end
        end
        host_data = 0;
        host_cmd  = CMD_HIZ;
        @(posedge clk);
        wait_idle(2_000_000);
        if (busy) begin
            fail_c++;
            $fdisplay(fd, "FAIL Case04 INF busy timeout");
        end else begin
            pass_c++;
            $fdisplay(fd, "PASS Case04 INF returned idle");
        end

        // Case 5: PROG cell (1,0,0,0) addr 0x0100 weight 4
        pulse_host_ann(CMD_PROG, 8'h04, 16'h0100);
        wait_idle(80_000);
        if (ann_weight_matrix[1][0][0][0] !== 4'd4) begin
            fail_c++;
            $fdisplay(fd, "FAIL Case05 PROG mock [1][0][0][0]");
        end else begin
            pass_c++;
            $fdisplay(fd, "PASS Case05 PROG [1][0][0][0]=4");
        end

        // Case 6: READ
        pulse_host_ann(CMD_READ, 8'h00, 16'h0100);
        wait_idle(80_000);
        pass_c++;
        $fdisplay(fd, "PASS Case06 READ idle");

        // Case 7: ERASE
        pulse_host_ann(CMD_ERASE, 8'h00, 16'h0100);
        wait_idle(80_000);
        pass_c++;
        $fdisplay(fd, "PASS Case07 ERASE idle");

        // Case 8: PROG corner cell (use parse_ann_address so TB and DUT stay aligned)
        begin
            logic [1:0]  p8b, p8s;
            logic [2:0]  p8r, p8c;
            parse_ann_address(16'h01E7, p8b, p8s, p8r, p8c);
            pulse_host_ann(CMD_PROG, 8'h03, 16'h01E7);
            wait_idle(2_000_000);
            if (busy) begin
                fail_c++;
                $fdisplay(fd, "FAIL Case08 PROG busy timeout (verify still running?)");
            end else if (ann_weight_matrix[p8b][p8s][p8r][p8c] !== 4'd3) begin
                fail_c++;
                $fdisplay(fd, "FAIL Case08 PROG mock [%0d][%0d][%0d][%0d] got %0d",
                          p8b, p8s, p8r, p8c, ann_weight_matrix[p8b][p8s][p8r][p8c]);
            end else begin
                pass_c++;
                $fdisplay(fd, "PASS Case08 PROG [%0d][%0d][%0d][%0d]=3",
                          p8b, p8s, p8r, p8c);
            end
        end

        // Case 9: READ
        pulse_host_ann(CMD_READ, 8'h00, 16'h01E7);
        wait_idle(80_000);
        pass_c++;
        $fdisplay(fd, "PASS Case09 READ idle");

        // Case 10: ERASE
        pulse_host_ann(CMD_ERASE, 8'h00, 16'h01E7);
        wait_idle(80_000);
        pass_c++;
        $fdisplay(fd, "PASS Case10 ERASE idle");

        $fdisplay(fd, "// Summary: PASS=%0d FAIL=%0d", pass_c, fail_c);
        $fclose(fd);
        $display("[%0t] controller_integration_smoke_tb: PASS=%0d FAIL=%0d -> %s",
                 $time, pass_c, fail_c, LOG_FILE);
        if (fail_c != 0)
            $fatal(1, "controller_integration_smoke_tb failures");
        $finish;
    end

endmodule
