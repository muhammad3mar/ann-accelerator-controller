//------------------------------------------------------------------------------
// ann_controller unit TB: DUT only; behavioral buffer BFM + op_done model.
// Log: target/Controller/tb_ann_controller_unit.txt
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module ann_controller_unit_tb;

    localparam int CLK_PERIOD = 5;
    localparam string LOG_FILE = "target/Controller/tb_ann_controller_unit.txt";

    logic clk, rst_n;
    logic valid;
    logic [7:0] data;
    logic [15:0] address;
    logic [CMD_WIDTH-1:0] cmd;
    logic ann_reset, op_done, busy;
    logic [31:0] ann_core_word;
    logic [2:0] pulses;
    logic [5:0] buf_reg_add;
    logic [2:0] buf_reg_ctrl;
    logic buf_read_write;
    logic [2:0] buf_bit_sel;
    logic [7:0] buf_data_out;
    logic buf_ready;
    logic [7:0] buf_data;
    logic [3:0] weight_read_data;

    logic [7:0] bmem[0:BUFFER_SIZE-1];
    wire write_en_bfm = buf_read_write && (buf_reg_ctrl == CTRL_DATA_LOAD);
    wire read_en_bfm  = !buf_read_write && ((buf_reg_ctrl == CTRL_COMPUTE) ||
                        (buf_reg_ctrl == CTRL_RESULT_OUT) || (buf_reg_ctrl == CTRL_WEIGHT_READ));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < BUFFER_SIZE; i++)
                bmem[i] <= '0;
        end else if (write_en_bfm && buf_reg_add < BUFFER_SIZE) begin
            bmem[buf_reg_add] <= buf_data_out;
        end
    end

    always_comb begin
        buf_data = '0;
        if (read_en_bfm && buf_reg_add < BUFFER_SIZE)
            buf_data = bmem[buf_reg_add];
    end

    assign       buf_ready = 1'b1;
    assign       weight_read_data = buf_data[3:0];

    logic        in_prog_core_phase;
    assign       in_prog_core_phase = (pulses == PULSE_MODE_PROG) && (buf_reg_ctrl == CTRL_WEIGHT_READ);

    int          op_done_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_done <= 0;
            op_done_cnt <= 0;
        end else begin
            if (in_prog_core_phase) begin
                if (op_done_cnt >= TPROG - 1) begin
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

    ann_controller dut (
        .clk(clk), .rst_n(rst_n),
        .valid(valid), .data(data), .address(address), .cmd(cmd),
        .ann_reset(ann_reset),
        .op_done(op_done),
        .ann_core_word(ann_core_word),
        .pulses(pulses),
        .weight_read_data(weight_read_data),
        .buf_reg_add(buf_reg_add),
        .buf_reg_ctrl(buf_reg_ctrl),
        .buf_read_write(buf_read_write),
        .buf_bit_sel(buf_bit_sel),
        .buf_data_out(buf_data_out),
        .buf_ready(buf_ready),
        .buf_data(buf_data),
        .busy(busy)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    function automatic logic [31:0] exp_word(logic [15:0] a, logic [7:0] d);
        logic [1:0] blk, sb;
        logic [2:0] rw, cl;
        blk = a[9:8];
        sb  = a[7:6];
        cl  = a[5:3];
        rw  = a[2:0];
        return pack_ann_core_word(d, blk, sb, rw, cl);
    endfunction

    task automatic reset_dut;
        rst_n = 0;
        valid = 0;
        data = 0;
        address = 0;
        cmd = CMD_HIZ;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
    endtask

    task automatic send_idle;
        valid = 0;
        data = 0;
        address = 0;
        cmd = CMD_HIZ;
        @(posedge clk);
    endtask

    task automatic send_cmd(input logic [CMD_WIDTH-1:0] c, input logic [15:0] a, input logic [7:0] d);
        valid = 1;
        cmd = c;
        address = a;
        data = d;
        @(posedge clk);
        valid = 0;
    endtask

    int fd;
    int pass_c, fail_c;

    task automatic check_busy_word(input logic [31:0] exp, input string ctx);
        int             to;
        logic [31:0]    saw;
        to = 0;
        saw = '0;
        wait (busy);
        while (busy) begin
            if (ann_core_word !== '0)
                saw = ann_core_word;
            @(posedge clk);
            to++;
            if (to > 500_000)
                break;
        end
        if (saw !== exp) begin
            fail_c++;
            $fdisplay(fd, "FAIL %s: captured=%h exp=%h", ctx, saw, exp);
        end else begin
            pass_c++;
            $fdisplay(fd, "PASS %s: ann_core_word=%h", ctx, saw);
        end
        if (busy)
            $fdisplay(fd, "WARN %s: busy timeout @%0t", ctx, $time);
    endtask

    initial begin
        pass_c = 0;
        fail_c = 0;
        fd = $fopen(LOG_FILE, "w");
        if (!fd) begin
            $error("Cannot open %s", LOG_FILE);
            $finish;
        end
        $fdisplay(fd, "// ann_controller unit TB (behavioral buffer)");
        $fdisplay(fd, "");

        reset_dut();
        repeat(20) @(posedge clk);

        send_cmd(CMD_READ, 16'h0249, 8'h00);
        check_busy_word(exp_word(16'h0249, 8'h00), "01_READ_0249");
        send_idle();

        send_cmd(CMD_PROG, 16'h0180, 8'h0A);
        check_busy_word(exp_word(16'h0180, 8'h0A), "02_PROG_0180");
        send_idle();

        send_cmd(CMD_ERASE, 16'h0307, 8'h00);
        check_busy_word(exp_word(16'h0307, 8'h00), "03_ERASE_0307");
        send_idle();

        send_cmd(CMD_READ, 16'h0000, 8'h00);
        check_busy_word(exp_word(16'h0000, 8'h00), "04_READ_0000");
        send_idle();

        send_cmd(CMD_PROG, 16'h0000, 8'h05);
        check_busy_word(exp_word(16'h0000, 8'h05), "05_PROG_0000");
        send_idle();

        send_cmd(CMD_READ, 16'h01E7, 8'h00);
        check_busy_word(exp_word(16'h01E7, 8'h00), "06_READ_01E7");
        send_idle();

        send_cmd(CMD_PROG, 16'h01E7, 8'h0B);
        check_busy_word(exp_word(16'h01E7, 8'h0B), "07_PROG_01E7");
        send_idle();

        send_cmd(CMD_ERASE, 16'h01E7, 8'h00);
        check_busy_word(exp_word(16'h01E7, 8'h00), "08_ERASE_01E7");
        send_idle();

        send_cmd(CMD_PROG, 16'h2000, 8'h03);
        check_busy_word(exp_word(16'h2000, 8'h03), "09_PROG_2000");
        send_idle();

        send_cmd(CMD_READ, 16'h2000, 8'h00);
        check_busy_word(exp_word(16'h2000, 8'h00), "10_READ_2000");
        send_idle();

        send_cmd(CMD_ERASE, 16'h00FF, 8'h00);
        check_busy_word(exp_word(16'h00FF, 8'h00), "11_ERASE_00FF");
        send_idle();

        send_cmd(CMD_PROG, 16'h0FFF, 8'h0F);
        check_busy_word(exp_word(16'h0FFF, 8'h0F), "12_PROG_0FFF");
        send_idle();

        send_cmd(CMD_READ, 16'h0FFF, 8'h00);
        check_busy_word(exp_word(16'h0FFF, 8'h00), "13_READ_0FFF");
        send_idle();

        send_cmd(CMD_PROG, 16'h0068, 8'h07);
        check_busy_word(exp_word(16'h0068, 8'h07), "14_PROG_0068");
        send_idle();

        send_cmd(CMD_ERASE, 16'h0180, 8'h00);
        check_busy_word(exp_word(16'h0180, 8'h00), "15_ERASE_0180");
        send_idle();

        $fdisplay(fd, "// Summary: PASS=%0d FAIL=%0d", pass_c, fail_c);
        $fclose(fd);
        $display("[%0t] ann_controller_unit_tb: PASS=%0d FAIL=%0d -> %s",
                 $time, pass_c, fail_c, LOG_FILE);
        if (fail_c != 0)
            $fatal(1, "ann_controller_unit_tb failures");
        $finish;
    end

endmodule
