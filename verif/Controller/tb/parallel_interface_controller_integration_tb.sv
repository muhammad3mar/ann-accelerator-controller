//------------------------------------------------------------------------------
// PI + ann_controller + input_buffer integration.
// Log: target/Controller/tb_pi_controller_integration.txt
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module parallel_interface_controller_integration_tb;

    localparam int CLK_PERIOD = 5;
    localparam string LOG_FILE = "target/Controller/tb_pi_controller_integration.txt";

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

    parallel_interface u_pi (
        .clk(clk), .reset(reset), .host_data(host_data), .host_cmd(host_cmd),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd)
    );

    ann_controller dut (
        .clk(clk), .rst_n(rst_n),
        .valid(valid), .data(pi_data), .address(address), .cmd(cmd),
        .ann_reset(ann_reset),
        .op_done(op_done), .ann_core_word(ann_core_word), .pulses(pulses),
        .weight_read_data(buf_data[3:0]),
        .buf_reg_add(buf_reg_add), .buf_reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_bit_sel(buf_bit_sel),
        .buf_data_out(buf_data_out), .buf_ready(buf_ready), .buf_data(buf_data), .busy(busy)
    );

    input_buffer u_input_buffer (
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
            if (dut.state == S_PROGRAM && (dut.prog_state == PROG_SELECT || dut.prog_state == PROG_WAIT_ACK)) begin
                op_done <= 1'b1;
                op_done_cnt <= 0;
            end else if (dut.state == S_ERASE && (dut.erase_state == ERASE_SELECT || dut.erase_state == ERASE_WAIT_ACK)) begin
                op_done <= 1'b1;
                op_done_cnt <= 0;
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

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 0; reset = 1; host_data = 0; host_cmd = CMD_HIZ;
        repeat(5) @(posedge clk);
        rst_n = 1; reset = 0;
        repeat(2) @(posedge clk);
    end

    function automatic logic [31:0] exp_word(logic [15:0] a, logic [7:0] d);
        logic [1:0] blk, sb;
        logic [2:0] rw, cl;
        blk = a[9:8];
        sb  = a[7:6];
        cl  = a[5:3];
        rw  = a[2:0];
        return pack_ann_core_word(d, blk, sb, rw, cl);
    endfunction

    function automatic string cmd_name(input logic [2:0] c);
        case (c)
            CMD_READ:  return "CMD_READ";
            CMD_PROG:  return "CMD_PROG";
            CMD_ERASE: return "CMD_ERASE";
            CMD_INF:   return "CMD_INF";
            CMD_HIZ:   return "CMD_HIZ";
            default:   return "CMD_???";
        endcase
    endfunction

    function automatic string pulse_name(input logic [2:0] p);
        case (p)
            PULSE_MODE_HIZ:   return "HIZ";
            PULSE_MODE_READ:  return "READ";
            PULSE_MODE_PROG:  return "PROG";
            PULSE_MODE_ERASE: return "ERASE";
            PULSE_MODE_INF:   return "INF";
            default:          return "???";
        endcase
    endfunction

    int fd;
    int pass_c, fail_c;

    // Hierarchical peek at buffer RAM for post-transaction snapshot (simulation only).
    task automatic dump_buffer_snapshot(input string ctx);
        int rr;
        $fdisplay(fd, "  // input_buffer after %s — buffer_reg[0:63], 8x8 row-major (hex):", ctx);
        for (rr = 0; rr < 8; rr++) begin
            $fdisplay(fd,
                "  //   row%0d  %02h %02h %02h %02h %02h %02h %02h %02h",
                rr,
                u_input_buffer.buffer_reg[rr * 8 + 0],
                u_input_buffer.buffer_reg[rr * 8 + 1],
                u_input_buffer.buffer_reg[rr * 8 + 2],
                u_input_buffer.buffer_reg[rr * 8 + 3],
                u_input_buffer.buffer_reg[rr * 8 + 4],
                u_input_buffer.buffer_reg[rr * 8 + 5],
                u_input_buffer.buffer_reg[rr * 8 + 6],
                u_input_buffer.buffer_reg[rr * 8 + 7]);
        end
    endtask

    task automatic log_host_and_pi(
        input logic [31:0] host_pkt,
        input logic [2:0]  host_c,
        input logic [15:0] par_a
    );
        logic [15:0] pi_addr;
        logic        pi_valid;
        pi_valid = (host_c != CMD_HIZ);
        pi_addr  = extract_address(host_pkt);
        $fdisplay(fd, "  // Host packet: host_cmd=%s (%b)", cmd_name(host_c), host_c);
        $fdisplay(fd, "  //   host_data:");
        $fdisplay(fd, "  //     %08b-%04b-%04b-%08b-%08b",
            host_pkt[31:24], host_pkt[23:20], host_pkt[19:16], host_pkt[15:8], host_pkt[7:0]);
        $fdisplay(fd, "  //     data[7:0] - PE[3:0] - SA[3:0] - col_onehot[7:0] - row_onehot[7:0]");
        $fdisplay(fd, "  //   host_data (hex): 0x%08h", host_pkt);
        $fdisplay(fd, "  // PI -> controller:");
        $fdisplay(fd, "  //   valid=%b  data(bin)=%08b  cmd=%s (%b)",
            pi_valid, host_pkt[31:24], cmd_name(host_c), host_c);
        $fdisplay(fd, "  //   address[15:0]:");
        $fdisplay(fd, "  //     %06b-%02b-%02b-%03b-%03b",
            pi_addr[15:10], pi_addr[9:8], pi_addr[7:6], pi_addr[5:3], pi_addr[2:0]);
        $fdisplay(fd, "  //     rsrv[5:0] - blk[1:0] - sub_blk[1:0] - col[2:0] - row[2:0]");
        $fdisplay(fd, "  //   address (hex): 0x%04h  |  parallel_addr idx: blk=%0d sub_blk=%0d col=%0d row=%0d",
            pi_addr, par_a[9:8], par_a[7:6], par_a[5:3], par_a[2:0]);
    endtask

    task automatic wait_until_idle(int maxcyc);
        int n;
        n = 0;
        while (busy) begin
            @(posedge clk);
            n++;
            if (n > maxcyc)
                break;
        end
    endtask

    // valid = (host_cmd != HIZ). Holding a command high for the whole transaction re-arms INF (and
    // breaks check_cmd's busy wait) every time the DUT returns to IDLE between COLLECT/COMPUTE rows.
    task automatic check_cmd(
        input logic [CMD_WIDTH-1:0] c,
        input logic [15:0] a,
        input logic [7:0] d,
        input logic [2:0] exp_pulse,
        input string ctx
    );
        logic [31:0] exp, saw_word, host_pkt;
        logic [2:0]  saw_pulse;
        int to;
        int busy_cycles;
        bit pulse_ok, word_ok;
        host_pkt = build_host_ann_word(d, a);
        exp = exp_word(a, d);
        wait_until_idle(500_000);
        repeat(8) @(posedge clk);
        host_data = 0;
        host_cmd  = CMD_HIZ;
        @(posedge clk);
        $fdisplay(fd, "");
        $fdisplay(fd, "//==============================================================================");
        $fdisplay(fd, "// %s", ctx);
        $fdisplay(fd, "//==============================================================================");
        host_data = host_pkt;
        host_cmd  = c;
        log_host_and_pi(host_pkt, c, a);
        $fdisplay(fd, "  // PI holds one-cycle beat: @(posedge) then host_cmd=HIZ (valid deasserts).");
        @(posedge clk);
        host_data = '0;
        host_cmd  = CMD_HIZ;
        @(posedge clk);
        wait (busy);
        saw_word = '0;
        saw_pulse = '0;
        pulse_ok = 0;
        word_ok = 0;
        to = 0;
        busy_cycles = 0;
        while (busy) begin
            busy_cycles++;
            if (pulses === exp_pulse)
                pulse_ok = 1;
            if (pulses !== 3'b000)
                saw_pulse = pulses;
            if (ann_core_word !== '0)
                saw_word = ann_core_word;
            if (ann_core_word === exp)
                word_ok = 1;
            @(posedge clk);
            to++;
            if (to > 500_000)
                break;
        end
        $fdisplay(fd, "  // DUT: controller busy for %0d posedge cycles (then idle)", busy_cycles);
        $fdisplay(fd, "  //   pulses: expected %s (%b)  |  last non-zero saw %s (%b)  pulse_ok=%0b",
            pulse_name(exp_pulse), exp_pulse, pulse_name(saw_pulse), saw_pulse, pulse_ok);
        $fdisplay(fd, "  //   ann_core_word: exp=0x%08h  saw_last_nonzero=0x%08h  saw_match_exp=%0b",
            exp, saw_word, word_ok);
        dump_buffer_snapshot(ctx);
        $fdisplay(fd, "  // Return to idle: busy=%0b", busy);
        if (!pulse_ok || !word_ok) begin
            fail_c++;
            $fdisplay(fd, "FAIL %s  pulse_ok=%0b word_ok=%0b  saw_pulse=%b saw_word=0x%h  exp_word=0x%h",
                      ctx, pulse_ok, word_ok, saw_pulse, saw_word, exp);
        end else begin
            pass_c++;
            $fdisplay(fd, "PASS %s", ctx);
        end
        if (busy) begin
            fail_c++;
            $fdisplay(fd, "FAIL %s: busy stuck high after case", ctx);
        end
        host_data = '0;
        host_cmd  = CMD_HIZ;
    endtask

    // One MNIST row: 9 consecutive clocks with INF (first enters COLLECT/resets ; then 8 counted
    // valids before COMPUTE — same as smoke TB). Monitor must run in parallel with the drive burst
    // or COLLECT words are missed.
    task automatic check_inf_row8(
        input logic [15:0] a,
        input logic [7:0] d,
        input string ctx
    );
        logic [31:0] exp, saw_word, host_pkt;
        logic [2:0]  saw_pulse;
        int to;
        int busy_cycles;
        bit pulse_ok, word_ok;
        host_pkt = build_host_ann_word(d, a);
        exp = exp_word(a, d);
        wait_until_idle(500_000);
        repeat(8) @(posedge clk);
        host_data = '0;
        host_cmd  = CMD_HIZ;
        @(posedge clk);
        $fdisplay(fd, "");
        $fdisplay(fd, "//==============================================================================");
        $fdisplay(fd, "// %s  (INF: 9 clk host_cmd=CMD_INF, same host_data each cycle)", ctx);
        $fdisplay(fd, "//==============================================================================");
        host_data = host_pkt;
        host_cmd  = CMD_INF;
        log_host_and_pi(host_pkt, CMD_INF, a);
        $fdisplay(fd, "  // INF: buffer loads 8 pixels (CTRL_DATA_LOAD), then COMPUTE issues INF pulses.");
        saw_word = '0;
        saw_pulse = '0;
        pulse_ok = 0;
        word_ok = 0;
        to = 0;
        busy_cycles = 0;
        fork
            begin : drive_inf_row
                repeat(9) @(posedge clk);
                host_data = '0;
                host_cmd  = CMD_HIZ;
                @(posedge clk);
            end
            begin : mon_inf_row
                wait (busy);
                while (busy) begin
                    busy_cycles++;
                    if (pulses === PULSE_MODE_INF)
                        pulse_ok = 1;
                    if (pulses !== 3'b000)
                        saw_pulse = pulses;
                    if (ann_core_word !== '0)
                        saw_word = ann_core_word;
                    if (ann_core_word === exp)
                        word_ok = 1;
                    @(posedge clk);
                    to++;
                    if (to > 500_000)
                        break;
                end
            end
        join
        $fdisplay(fd, "  // DUT: controller busy for %0d posedge cycles (INF COLLECT + COMPUTE + ...)", busy_cycles);
        $fdisplay(fd, "  //   pulses: expected %s (%b)  |  last non-zero saw %s (%b)  pulse_ok=%0b",
            pulse_name(PULSE_MODE_INF), PULSE_MODE_INF, pulse_name(saw_pulse), saw_pulse, pulse_ok);
        $fdisplay(fd, "  //   ann_core_word: exp=0x%08h  saw_last_nonzero=0x%08h  saw_match_exp=%0b  (INF may toggle word during COLLECT vs COMPUTE)",
            exp, saw_word, word_ok);
        dump_buffer_snapshot(ctx);
        $fdisplay(fd, "  // Return to idle: busy=%0b", busy);
        if (!pulse_ok || !word_ok) begin
            fail_c++;
            $fdisplay(fd, "FAIL %s  saw_inf_pulse=%0b saw_match_word=%0b saw_pulse=%b saw_word=0x%h exp_word=0x%h",
                      ctx, pulse_ok, word_ok, saw_pulse, saw_word, exp);
        end else begin
            pass_c++;
            $fdisplay(fd, "PASS %s", ctx);
        end
        if (busy) begin
            fail_c++;
            $fdisplay(fd, "FAIL %s: busy stuck high after case", ctx);
        end
        host_data = '0;
        host_cmd  = CMD_HIZ;
    endtask

    initial begin
        pass_c = 0;
        fail_c = 0;
        fd = $fopen(LOG_FILE, "w");
        if (!fd) begin $error("Cannot open log"); $finish; end
        $fdisplay(fd, "// PI + controller + input_buffer integration (verbose report)");
        $fdisplay(fd, "//");
        $fdisplay(fd, "// Per case: host 32b + host_cmd | PI->controller (valid,data,address,cmd) |");
        $fdisplay(fd, "//   busy cycle count | pulses + ann_core_word (exp vs saw) | input_buffer 8x8 dump | idle.");
        $fdisplay(fd, "");
        wait(rst_n);
        repeat(6) @(posedge clk);

        check_cmd(CMD_READ, 16'h01E7, 8'h00, PULSE_MODE_READ, "01_READ");
        @(posedge clk);

        check_cmd(CMD_PROG, 16'h0000, 8'h0C, PULSE_MODE_PROG, "02_PROG");
        @(posedge clk);

        check_cmd(CMD_ERASE, 16'h0305, 8'h00, PULSE_MODE_ERASE, "03_ERASE");
        @(posedge clk);

        check_inf_row8(16'h0055, 8'hAA, "04_INF");
        @(posedge clk);

        check_cmd(CMD_READ, 16'h0204, 8'h00, PULSE_MODE_READ, "05_READ");
        @(posedge clk);

        check_cmd(CMD_PROG, 16'h0108, 8'h0E, PULSE_MODE_PROG, "06_PROG");
        @(posedge clk);

        check_cmd(CMD_ERASE, 16'h0240, 8'h00, PULSE_MODE_ERASE, "07_ERASE");
        @(posedge clk);

        check_cmd(CMD_READ, 16'h3F00, 8'h00, PULSE_MODE_READ, "08_READ");
        @(posedge clk);

        check_cmd(CMD_PROG, 16'h05FF, 8'h0F, PULSE_MODE_PROG, "09_PROG");
        @(posedge clk);

        check_cmd(CMD_ERASE, 16'h00FC, 8'h00, PULSE_MODE_ERASE, "10_ERASE");
        @(posedge clk);

        $fdisplay(fd, "// Summary: PASS=%0d FAIL=%0d", pass_c, fail_c);
        $fclose(fd);
        $display("[%0t] parallel_interface_controller_integration_tb: PASS=%0d FAIL=%0d -> %s",
                 $time, pass_c, fail_c, LOG_FILE);
        if (fail_c != 0)
            $fatal(1, "parallel_interface_controller_integration_tb failures");
        $finish;
    end

endmodule
