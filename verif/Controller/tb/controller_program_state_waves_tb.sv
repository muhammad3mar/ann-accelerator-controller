//------------------------------------------------------------------------------
// Controller programming-state waveform TB (S_PROGRAM -> S_VERIFY -> retry paths)
//------------------------------------------------------------------------------
// Dense host + DUT activity for wave debug:
//   - Multi-address PROG sweep (distinct cmd/data/address on parallel_interface).
//   - Standalone CMD_READ and CMD_ERASE from idle (extra controller states).
//   - PROG->VERIFY regular / under (re-PROG) / over (ERASE->reprog) with verify inject.
//
// host_data is held for HOST_BUS_HOLD_CYCLES while busy so cmd/data/address stay visible
// (then cleared before return to idle to avoid accidental re-latch).
//
// Waveforms (ModelSim GUI):
//   python scripts/run_sim.py sim -m Controller -tb controller_program_state_waves_tb --do-file verif/Controller/do/controller_program_state_waves.do
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_program_state_waves_tb;

    localparam int CLK_PERIOD = 5;  // ns per full period @ timescale 1ns -> 200 MHz
    localparam int HOST_BUS_HOLD_CYCLES = 6;  // extra cycles with host_data held after busy (waves); keep small to avoid side effects
    localparam int IDLE_GAP_CYCLES = 35;

    // Multi-program sweep (different addresses / weights -> changing PI exports)
    localparam logic [15:0] ADDR_M0 = 16'h0100;
    localparam logic [15:0] ADDR_M1 = 16'h0144;
    localparam logic [15:0] ADDR_M2 = 16'h0290;
    localparam logic [3:0]  W_M0 = 4'd3;
    localparam logic [3:0]  W_M1 = 4'd10;
    localparam logic [3:0]  W_M2 = 4'd12;

    // Standalone READ / ERASE use this cell after programming
    localparam logic [15:0] ADDR_IO = 16'h0188;
    localparam logic [3:0]  W_IO = 4'd9;

    // ERASE target (program then direct CMD_ERASE)
    localparam logic [15:0] ADDR_E = 16'h0240;
    localparam logic [3:0]  W_E = 4'd11;

    // Inject scenarios: use an ANN address known to map cleanly (matches original TB)
    // Buf slot must differ from ADDR_M0 (0x100 uses address_reg[5:0]==0 — shared with 0x0000)
    localparam logic [15:0] INJECT_ADDR = 16'h001F;
    localparam logic [3:0]  INJECT_W = 4'd7;

    localparam string REPORT_FILE = "target/Controller/program_state_flow_report.txt";
    localparam logic [2:0] DUT_ERASE_PULSE = 3'd3;

    typedef enum int {
        SCEN_NONE,
        SCEN_REGULAR,
        SCEN_UNDER,
        SCEN_OVER
    } scenario_e;

    logic clk, rst_n, reset;
    logic [31:0] host_data;
    logic [2:0]  host_cmd;
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
    logic [7:0] buf_data_out, buf_data;
    logic D0, D1, D2, D3, D4, D5, D6, D7;
    logic buf_ready;

    int unsigned tb_transaction_id;
    scenario_e tb_scenario;
    logic [3:0] inject_expected_weight;

    logic [3:0] ann_weight_matrix [0:NUM_BLOCKS-1][0:NUM_SUB_BLOCKS-1][0:SUB_BLOCK_ROWS-1][0:SUB_BLOCK_COLS-1];
    logic [3:0] weight_read_data_mock;
    logic [3:0] actual_from_ann;
    logic [1:0] dec_blk, dec_sb;
    logic [2:0] dec_row, dec_col;

    always_comb begin
        ann_core_word_decode(ann_core_word, dec_blk, dec_sb, dec_row, dec_col);
        actual_from_ann = ann_weight_matrix[dec_blk][dec_sb][dec_row][dec_col];
    end

    int verify_cycle_cnt;
    logic was_in_verify;
    logic in_verify_phase;
    logic arm_stats_pulse;

    assign in_verify_phase = busy && (pulses == PULSE_MODE_READ || pulses == PULSE_MODE_HIZ);

    always_ff @(posedge clk) begin
        was_in_verify <= (pulses == PULSE_MODE_READ) && busy;
        if (busy && (pulses == PULSE_MODE_READ) && !was_in_verify)
            verify_cycle_cnt <= verify_cycle_cnt + 1;
        else if (!busy)
            verify_cycle_cnt <= 0;
    end

    always_comb begin
        weight_read_data_mock = actual_from_ann;
        if (tb_scenario == SCEN_UNDER && inject_expected_weight > 0 && in_verify_phase && (verify_cycle_cnt <= 1))
            weight_read_data_mock = inject_expected_weight - 1;
        else if (tb_scenario == SCEN_OVER && inject_expected_weight < 15 && in_verify_phase && (verify_cycle_cnt <= 1))
            weight_read_data_mock = inject_expected_weight + 1;
    end

    parallel_interface u_pi (.clk(clk), .reset(reset), .host_data(host_data), .host_cmd(host_cmd),
        .valid(valid), .data(data), .address(address), .cmd(cmd));

    ann_controller dut (
        .clk(clk), .rst_n(rst_n), .valid(valid), .data(data), .address(address), .cmd(cmd),
        .ann_reset(ann_reset),
        .op_done(op_done), .ann_core_word(ann_core_word), .pulses(pulses),
        .weight_read_data(weight_read_data_mock),
        .buf_reg_add(buf_reg_add), .buf_reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write),
        .buf_bit_sel(buf_bit_sel),
        .buf_data_out(buf_data_out), .buf_ready(buf_ready), .buf_data(buf_data), .busy(busy));

    input_buffer u_buf (.clk(clk), .rst_n(rst_n), .data_in(buf_data_out), .ready(buf_ready),
        .reg_ctrl(buf_reg_ctrl), .buf_read_write(buf_read_write), .buf_reg_add(buf_reg_add),
        .bit_sel(buf_bit_sel), .buf_data(buf_data),
        .D0(D0), .D1(D1), .D2(D2), .D3(D3), .D4(D4), .D5(D5), .D6(D6), .D7(D7));

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

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

    //----------------------------------------------------------------------
    // Stats (inject scenarios, reset by arm_stats_pulse)
    //----------------------------------------------------------------------
    int scen_prog_bursts;
    int scen_erase_pulse_cycles;
    logic prev_prog_write;

    wire prog_in_write = (dut.state == S_PROGRAM) && (dut.prog_state == PROG_WRITE);
    wire prog_write_rise = prog_in_write && !prev_prog_write;

    int scen_s_read_entry;
    logic prev_dut_read;
    wire dut_in_read = (dut.state == S_READ);
    wire read_rise = dut_in_read && !prev_dut_read;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            prev_prog_write <= 0;
        else
            prev_prog_write <= prog_in_write;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            prev_dut_read <= 0;
        else
            prev_dut_read <= dut_in_read;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scen_prog_bursts <= 0;
            scen_erase_pulse_cycles <= 0;
            scen_s_read_entry <= 0;
        end else if (arm_stats_pulse) begin
            scen_prog_bursts <= 0;
            scen_erase_pulse_cycles <= 0;
            scen_s_read_entry <= 0;
        end else if (tb_scenario != SCEN_NONE && busy) begin
            if (prog_write_rise)
                scen_prog_bursts <= scen_prog_bursts + 1;
            if (dut.state == S_ERASE && dut.erase_state == DUT_ERASE_PULSE)
                scen_erase_pulse_cycles <= scen_erase_pulse_cycles + 1;
            if (read_rise)
                scen_s_read_entry <= scen_s_read_entry + 1;
        end else if (busy && tb_scenario == SCEN_NONE && read_rise)
            scen_s_read_entry <= scen_s_read_entry + 1;
        else if (busy && tb_scenario == SCEN_NONE && dut.state == S_ERASE && dut.erase_state == DUT_ERASE_PULSE)
            scen_erase_pulse_cycles <= scen_erase_pulse_cycles + 1;
    end

    function automatic logic [31:0] ann_payload_prog(logic [15:0] addr, logic [3:0] w);
        return build_host_ann_word({4'b0, w}, addr);
    endfunction

    function automatic logic [31:0] ann_payload_addr_only(logic [15:0] addr);
        return build_host_ann_word(8'h00, addr);
    endfunction

    // host_data = ann_core_word layout; host_cmd selects operation (parallel_interface)
    task automatic send_host_and_wait(logic [2:0] op, logic [31:0] payload);
        automatic int timeout;
        automatic int k;
        tb_transaction_id++;
        host_cmd = CMD_HIZ;
        host_data = 0;
        @(posedge clk);
        host_data = payload;
        host_cmd = op;
        @(posedge clk);
        timeout = 0;
        while (!busy && timeout < 5000) begin
            @(posedge clk);
            timeout++;
        end
        if (!busy)
            $fatal(1, "DUT did not assert busy after transaction %0d", tb_transaction_id);
        for (k = 0; k < HOST_BUS_HOLD_CYCLES; k++)
            @(posedge clk);
        host_cmd = CMD_HIZ;
        host_data = 0;
        @(posedge clk);
        timeout = 0;
        while (busy && timeout < 500_000) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= 500_000)
            $fatal(1, "Timeout !busy after transaction %0d", tb_transaction_id);
        repeat (3) @(posedge clk);
    endtask

    task automatic send_prog_wait(logic [15:0] addr, logic [3:0] w);
        send_host_and_wait(CMD_PROG, ann_payload_prog(addr, w));
    endtask

    task automatic send_read_wait(logic [15:0] addr);
        send_host_and_wait(CMD_READ, ann_payload_addr_only(addr));
    endtask

    task automatic send_erase_wait(logic [15:0] addr);
        send_host_and_wait(CMD_ERASE, ann_payload_addr_only(addr));
    endtask

    task automatic verify_ann_cell(logic [15:0] addr, logic [3:0] exp, string ctx);
        automatic logic [1:0] blk, sb;
        automatic logic [2:0] rid, cid;
        parse_ann_address(addr, blk, sb, rid, cid);
        if (ann_weight_matrix[blk][sb][rid][cid] !== exp)
            $fatal(1, "%s: ANN cell mismatch addr=0x%04h exp=%0d got=%0d", ctx, addr, exp,
                ann_weight_matrix[blk][sb][rid][cid]);
    endtask

    //----------------------------------------------------------------------
    // Report + main
    //----------------------------------------------------------------------
    int fd;

    initial begin
        rst_n = 0;
        reset = 1;
        host_cmd = CMD_HIZ;
        host_data = 0;
        tb_scenario = SCEN_NONE;
        inject_expected_weight = 4'h0;
        arm_stats_pulse = 0;
        tb_transaction_id = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        reset = 0;
        repeat (5) @(posedge clk);

        fd = $fopen(REPORT_FILE, "w");
        if (fd == 0)
            $fatal(1, "Cannot open report %s", REPORT_FILE);

        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "// Controller programming-state / READ / ERASE wave stimulus report");
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "TB CLK_PERIOD (ns): %0d  HOST_BUS_HOLD_CYCLES: %0d", CLK_PERIOD, HOST_BUS_HOLD_CYCLES);
        $fdisplay(fd, "");
        $fdisplay(fd, "controller_pkg timing (cycles): TREAD=%0d TPROG=%0d TERASE=%0d  MAX_PROG_RETRIES=%0d",
            TREAD, TPROG, TERASE, MAX_PROG_RETRIES);
        $fdisplay(fd, "  PULSE_TOTAL_READ=%0d PULSE_TOTAL_PROG=%0d PULSE_TOTAL_ERASE=%0d",
            PULSE_TOTAL_READ, PULSE_TOTAL_PROG, PULSE_TOTAL_ERASE);
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        $fdisplay(fd, "");

        //--- A: Multi-address PROG sweep (rich cmd/data/address on PI) ---
        send_prog_wait(ADDR_M0, W_M0);
        send_prog_wait(ADDR_M1, W_M1);
        send_prog_wait(ADDR_M2, W_M2);
        verify_ann_cell(ADDR_M0, W_M0, "Sweep M0");
        verify_ann_cell(ADDR_M1, W_M1, "Sweep M1");
        verify_ann_cell(ADDR_M2, W_M2, "Sweep M2");
        $fdisplay(fd, "A multi_prog_sweep: PASS (3 addresses)");

        repeat (IDLE_GAP_CYCLES) @(posedge clk);

        //--- B: Program cell then standalone READ (S_READ on DUT) ---
        send_prog_wait(ADDR_IO, W_IO);
        send_read_wait(ADDR_IO);
        if (scen_s_read_entry < 1)
            $fatal(1, "Expected S_READ activity for standalone READ");
        verify_ann_cell(ADDR_IO, W_IO, "After READ sequence");
        $fdisplay(fd, "B prog_then_host_read: PASS  s_read_edges=%0d", scen_s_read_entry);
        repeat (IDLE_GAP_CYCLES) @(posedge clk);

        //--- C: Program cell then standalone ERASE (direct CMD_ERASE, not via VERIFY fail) ---
        begin
            automatic int er_before_prog;
            automatic int er_after_prog;
            er_before_prog = scen_erase_pulse_cycles;
            send_prog_wait(ADDR_E, W_E);
            er_after_prog = scen_erase_pulse_cycles;
            if (er_after_prog != er_before_prog)
                $fatal(1, "C: unexpected ERASE during PROG+VERIFY");
            send_erase_wait(ADDR_E);
            if (scen_erase_pulse_cycles <= er_after_prog)
                $fatal(1, "Expected ERASE pulse cycles for direct CMD_ERASE");
            $fdisplay(fd, "C prog_then_host_erase: PASS  erase_pulse_cycles_total=%0d", scen_erase_pulse_cycles);
        end
        repeat (IDLE_GAP_CYCLES) @(posedge clk);

        //--- D: PROG+VERIFY regular ---
        arm_stats_pulse = 1;
        @(posedge clk);
        arm_stats_pulse = 0;
        tb_scenario = SCEN_REGULAR;
        inject_expected_weight = INJECT_W;
        @(posedge clk);
        send_prog_wait(INJECT_ADDR, INJECT_W);
        if (busy)
            $fatal(1, "D: busy stuck");
        if (scen_prog_bursts != 1)
            $fatal(1, "D: expected 1 PROG burst, got %0d", scen_prog_bursts);
        if (scen_erase_pulse_cycles != 0)
            $fatal(1, "D: unexpected ERASE");
        verify_ann_cell(INJECT_ADDR, INJECT_W, "D regular");
        $fdisplay(fd, "D inject_regular: PASS  prog_bursts=%0d", scen_prog_bursts);

        tb_scenario = SCEN_NONE;
        inject_expected_weight = 0;
        repeat (IDLE_GAP_CYCLES) @(posedge clk);

        //--- E: Under (re-PROG) ---
        arm_stats_pulse = 1;
        @(posedge clk);
        arm_stats_pulse = 0;
        tb_scenario = SCEN_UNDER;
        inject_expected_weight = INJECT_W;
        @(posedge clk);
        send_prog_wait(INJECT_ADDR, INJECT_W);
        if (busy)
            $fatal(1, "E: busy stuck");
        if (scen_prog_bursts != 2)
            $fatal(1, "E: expected 2 PROG bursts, got %0d", scen_prog_bursts);
        if (scen_erase_pulse_cycles != 0)
            $fatal(1, "E: unexpected ERASE");
        verify_ann_cell(INJECT_ADDR, INJECT_W, "E under");
        $fdisplay(fd, "E inject_under: PASS  prog_bursts=%0d", scen_prog_bursts);

        tb_scenario = SCEN_NONE;
        inject_expected_weight = 0;
        repeat (IDLE_GAP_CYCLES) @(posedge clk);

        //--- F: Over (ERASE + reprogram) ---
        arm_stats_pulse = 1;
        @(posedge clk);
        arm_stats_pulse = 0;
        tb_scenario = SCEN_OVER;
        inject_expected_weight = INJECT_W;
        @(posedge clk);
        send_prog_wait(INJECT_ADDR, INJECT_W);
        if (busy)
            $fatal(1, "F: busy stuck");
        if (scen_prog_bursts < 2)
            $fatal(1, "F: expected >=2 PROG bursts, got %0d", scen_prog_bursts);
        if (scen_erase_pulse_cycles < 1)
            $fatal(1, "F: expected ERASE pulses, got %0d", scen_erase_pulse_cycles);
        verify_ann_cell(INJECT_ADDR, INJECT_W, "F over");
        $fdisplay(fd, "F inject_over: PASS  prog_bursts=%0d erase_pulse_cycles=%0d",
            scen_prog_bursts, scen_erase_pulse_cycles);

        $fdisplay(fd, "");
        $fdisplay(fd, "Summary: all sections PASS  total_transactions=%0d", tb_transaction_id);
        $fdisplay(fd, "//------------------------------------------------------------------------------");
        begin automatic int fdx = fd; fd = 0; $fclose(fdx); end

        $display("[%0t] PASS - report: %s", $time, REPORT_FILE);
        repeat (10) @(posedge clk);
        $finish;
    end

    initial begin
        #(10_000_000 * CLK_PERIOD);
        $fatal(1, "Global timeout");
    end

endmodule
