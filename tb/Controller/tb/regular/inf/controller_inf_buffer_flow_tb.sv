//------------------------------------------------------------------------------
// Controller INF -> Input Buffer Flow Testbench
//------------------------------------------------------------------------------
// Shows:
//   1) Host INF packets entering PI.
//   2) How bytes are stored into input_buffer while collecting data.
//   3) Bit-serial D0..D7 flow starts only after 8 received pixels.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../../../rtl/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_inf_buffer_flow_tb;

    localparam int CLK_PERIOD = 5;
    localparam string LOG_FILE = "target/Controller/inf/controller_inf_buffer_flow_tb_log.txt";

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
    logic [3:0]  weight_read_data_mock;

    logic [7:0] px_stream [0:15];
    int fd;
    int pass_count, fail_count;

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

    input_buffer u_input_buffer (
        .clk(clk), .rst_n(rst_n), .data_in(buf_data_out),
        .ready(buf_ready), .reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_reg_add(buf_reg_add), .bit_sel(buf_bit_sel), .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3), .D4(D4), .D5(D5), .D6(D6), .D7(D7)
    );

    assign weight_read_data_mock = buf_data[3:0];

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Not used by current controller RTL, keep low.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) op_done <= 1'b0;
        else op_done <= 1'b0;
    end

    task automatic dump_row0(input string tag);
        $fdisplay(fd, "%s row0[addr0..7] = %02h %02h %02h %02h %02h %02h %02h %02h",
            tag,
            u_input_buffer.buffer_reg[0], u_input_buffer.buffer_reg[1],
            u_input_buffer.buffer_reg[2], u_input_buffer.buffer_reg[3],
            u_input_buffer.buffer_reg[4], u_input_buffer.buffer_reg[5],
            u_input_buffer.buffer_reg[6], u_input_buffer.buffer_reg[7]);
    endtask

    task automatic send_inf_beat(
        input logic [7:0] data_byte,
        input logic [15:0] par_addr,
        input string label
    );
        logic [31:0] pkt;
        pkt = build_host_ann_word(data_byte, par_addr);
        host_data = pkt;
        host_cmd  = CMD_INF;
        @(posedge clk);
        #1;
        $fdisplay(fd, "%s", label);
        $fdisplay(fd, "  host_data: 0x%08h (%08b-%04b-%04b-%08b-%08b), cmd=%b",
            pkt, pkt[31:24], pkt[23:20], pkt[19:16], pkt[15:8], pkt[7:0], CMD_INF);
        $fdisplay(fd, "  PI->CTRL : valid=%0d data=0x%02h addr=0x%04h cmd=%b", valid, pi_data, address, cmd);
        $fdisplay(fd, "  CTRL     : state_busy=%0d buf_ctrl=%0d buf_rw=%0d buf_addr=%0d pulses=%b bit_sel=%0d",
            busy, buf_reg_ctrl, buf_read_write, buf_reg_add, pulses, buf_bit_sel);
        dump_row0("  BUFFER  :");
    endtask

    initial begin
        int beat_idx;
        int writes_seen;
        logic [7:0] row0_snap [0:7];

        // Deterministic stream (longer than needed). TB drives until 8 writes are observed.
        px_stream[0]  = 8'h3C; px_stream[1]  = 8'hA5; px_stream[2]  = 8'h7E; px_stream[3]  = 8'h19;
        px_stream[4]  = 8'hC3; px_stream[5]  = 8'h5A; px_stream[6]  = 8'hE1; px_stream[7]  = 8'h0F;
        px_stream[8]  = 8'h44; px_stream[9]  = 8'hB2; px_stream[10] = 8'h27; px_stream[11] = 8'h9D;
        px_stream[12] = 8'h6C; px_stream[13] = 8'h11; px_stream[14] = 8'hD8; px_stream[15] = 8'h73;

        rst_n = 0; reset = 1;
        host_data = 0; host_cmd = CMD_HIZ;
        pass_count = 0; fail_count = 0;

        fd = $fopen(LOG_FILE, "w");
        if (!fd) begin
            $error("Cannot open log file: %s", LOG_FILE);
            $finish;
        end

        $fdisplay(fd, "// Controller INF buffer-flow behavior");
        $fdisplay(fd, "// TB drives INF beats continuously and tracks actual writes (CTRL_DATA_LOAD + buf_rw=1).");
        $fdisplay(fd, "// Expected behavior: COMPUTE/INF pulses start only after 8 writes are observed.");
        $fdisplay(fd, "");

        repeat(5) @(posedge clk);
        rst_n = 1; reset = 0;
        repeat(2) @(posedge clk);

        writes_seen = 0;
        beat_idx = 0;
        while (writes_seen < 8 && beat_idx < 16) begin
            send_inf_beat(px_stream[beat_idx], 16'h0055, $sformatf("Beat%0d:", beat_idx));
            if (buf_reg_ctrl == CTRL_DATA_LOAD && buf_read_write)
                writes_seen++;
            if ((buf_reg_ctrl == CTRL_COMPUTE || pulses == PULSE_MODE_INF) && writes_seen < 8) begin
                fail_count++;
                $fdisplay(fd, "  FAIL: compute started before 8 writes (writes_seen=%0d)", writes_seen);
            end
            beat_idx++;
        end

        if (writes_seen == 8) begin
            pass_count++;
            $fdisplay(fd, "PASS: observed exactly 8 data-load writes before compute");
            // Keep INF valid for one extra beat so controller can transition to COMPUTE.
            if (beat_idx < 16) begin
                send_inf_beat(px_stream[beat_idx], 16'h0055, $sformatf("Beat%0d (compute trigger):", beat_idx));
                beat_idx++;
            end
        end else begin
            fail_count++;
            $fdisplay(fd, "FAIL: did not observe 8 writes (writes_seen=%0d)", writes_seen);
        end

        // Deassert valid after enough writes were observed.
        host_data = '0;
        host_cmd  = CMD_HIZ;
        @(posedge clk);
        #1;

        $fdisplay(fd, "");
        $fdisplay(fd, "After collect phase (row0 snapshot):");
        dump_row0("  BUFFER  :");

        // Snapshot row0 bytes as actually stored.
        for (int i = 0; i < 8; i++) begin
            row0_snap[i] = u_input_buffer.buffer_reg[i];
        end

        // Wait for compute (INF pulses), with timeout to avoid hang.
        begin
            bit saw_compute;
            saw_compute = 0;
            for (int t = 0; t < 200; t++) begin
                if (busy && pulses == PULSE_MODE_INF) begin
                    saw_compute = 1;
                    break;
                end
                @(posedge clk);
            end

            if (!saw_compute) begin
                fail_count++;
                $fdisplay(fd, "FAIL: compute phase (pulses=INF) not observed within timeout");
            end else begin
                bit seen_bit [0:7];
                int seen_count;
                $fdisplay(fd, "");
                $fdisplay(fd, "Compute phase starts (after 8 pixels): D0..D7 bit-serial view");
                for (int i = 0; i < 8; i++) seen_bit[i] = 0;
                seen_count = 0;
                for (int s = 0; s < 40 && seen_count < 8; s++) begin
                    int b;
                    logic [7:0] exp_bits;
                    @(posedge clk);
                    #1;
                    if (!(busy && pulses == PULSE_MODE_INF))
                        continue;
                    b = buf_bit_sel;
                    if (seen_bit[b])
                        continue;
                    seen_bit[b] = 1;
                    seen_count++;
                    exp_bits = {row0_snap[7][b], row0_snap[6][b], row0_snap[5][b], row0_snap[4][b],
                                row0_snap[3][b], row0_snap[2][b], row0_snap[1][b], row0_snap[0][b]};
                    $fdisplay(fd,
                        "  bit_sel=%0d D7..D0=%b%b%b%b%b%b%b%b exp(D7..D0)=%b",
                        b, D7,D6,D5,D4,D3,D2,D1,D0, exp_bits);
                    if ({D7,D6,D5,D4,D3,D2,D1,D0} === exp_bits)
                        pass_count++;
                    else
                        fail_count++;
                end
                if (seen_count < 8) begin
                    $fdisplay(fd, "NOTE: observed %0d unique bit_sel samples before compute ended", seen_count);
                end
            end
        end

        // Final summary
        $fdisplay(fd, "");
        $fdisplay(fd, "//==============================================================================");
        $fdisplay(fd, "// TB REPORT  controller_inf_buffer_flow_tb");
        $fdisplay(fd, "// Shows collect-before-compute behavior and D0..D7 bit-serial output after 8 pixels");
        $fdisplay(fd, "//==============================================================================");
        $fdisplay(fd, "SUMMARY: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $fdisplay(fd, "RESULT: PASS");
        else
            $fdisplay(fd, "RESULT: FAIL");

        $fclose(fd);
        $finish;
    end

endmodule
