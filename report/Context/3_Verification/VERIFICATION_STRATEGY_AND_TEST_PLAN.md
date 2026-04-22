# Verification Strategy and Test Plan

This chapter describes **only** what is implemented in this repository: directed SystemVerilog testbenches under `verif/`, simulation via ModelSim-style flows (including `scripts/run_sim.py`), and textual reports under `target/`. There is **no** UVM environment, constrained-random stimulus engine, or functional coverage model in the codebase.

---

## 1. Execution context

- **Language / style:** SystemVerilog modules, `import` of `controller_pkg`, `input_buffer_pkg`, and `parallel_interface_pkg`, plus `` `include "source/common/macros.svh" `` (paths vary slightly per TB).
- **DUT stacking:** Most controller benches instantiate `parallel_interface` → `ann_controller` → `input_buffer` in that order (integration order matches real connectivity).
- **Artifacts:** Benches open report paths with `$fopen` / `$fdisplay` / `$fwrite` and close them explicitly; summaries are intended for regression diffing in `target/`.

---

## 2. Mocking strategy for ANN / memristor behavior (controller program–verify benches)

Several controller testbenches **do not** instantiate a separate ANN or ADC model. Instead they maintain a **TB-local shadow array** and drive the DUT port `weight_read_data` from combinational logic that can be **perturbed** to force verify recovery.

### 2.1 Shadow storage: `ann_weight_matrix`

In `controller_prog_verify_lut_tb`, `controller_prog_verify_lut_10w_tb`, `controller_host_erase_tb`, and `controller_host_read_reorder_tb`, the TB declares:

```systemverilog
logic [3:0] ann_weight_matrix [0:NUM_BLOCKS-1][0:NUM_SUB_BLOCKS-1][0:SUB_BLOCK_ROWS-1][0:SUB_BLOCK_COLS-1];
```

Indices follow the same block / sub-block / row / col decomposition as the RTL address map (`NUM_BLOCKS`, `NUM_SUB_BLOCKS`, etc., from `controller_pkg`).

**Reset:** On `negedge rst_n`, nested `for` loops clear every element to `4'b0`.

**Update on program (mock “cell programmed”):** A shared pattern is:

- `assign in_prog_core_phase = (pulses == PULSE_MODE_PROG) && (buf_reg_ctrl == CTRL_WEIGHT_READ);`
- In an `always_ff @(posedge clk)`, when `in_prog_core_phase` is true, the TB decodes the current `ann_core_word` with `ann_core_word_decode(ann_core_word, lb, lsb, lr, lc)` and writes:

```systemverilog
ann_weight_matrix[lb][lsb][lr][lc] <= ann_core_word[27:24];
```

So the **nibble programmed onto the core bus** (`ann_core_word[27:24]`, i.e. the weight field in the packed word) is what the mock stores. That matches the RTL using the same word layout during program.

### 2.2 Baseline readback: `actual_from_ann` and `weight_read_data_mock`

The TB continuously decodes the **current** `ann_core_word` to select a cell:

```systemverilog
always_comb begin
    ann_core_word_decode(ann_core_word, dec_blk, dec_sb, dec_row, dec_col);
    actual_from_ann = ann_weight_matrix[dec_blk][dec_sb][dec_row][dec_col];
end
```

By default, `weight_read_data_mock` is tied to `actual_from_ann` (or assigned from it before optional overrides). The DUT input is wired as:

```systemverilog
.weight_read_data(weight_read_data_mock),
```

So during **verify**, when the RTL issues read timing on `pulses` and samples `weight_read_data`, it sees either the shadow cell contents or an **injected** value (see §4).

**Other tie-offs (not using the shadow matrix):**

- `controller_addr_pulse_tb` and `parallel_interface_controller_integration_tb` use `weight_read_data(buf_data[3:0])` so verify/read paths see the buffer nibble, not `ann_weight_matrix`.
- `controller_inf_buffer_flow_tb` ties `weight_read_data_mock` to `buf_data[3:0]` and holds `op_done` low; INF flow does not use the program–verify mock.

### 2.3 `op_done` behavioral mock (handshake for PROG / ERASE pulse phases)

The RTL waits on `op_done` in program and erase substates (`PROG_SELECT`, `PROG_WAIT_ACK`, `ERASE_SELECT`, `ERASE_WAIT_ACK`). The LUT program–verify TBs model this with an `always_ff` that:

- Asserts `op_done <= 1'b1` when `dut.state == S_PROGRAM` and `dut.prog_state` is `PROG_SELECT` or `PROG_WAIT_ACK`, or when `dut.state == S_ERASE` and `dut.erase_state` is `ERASE_SELECT` or `ERASE_WAIT_ACK`.
- For other busy intervals where `pulses` is `3'b001` (READ / verify train), `3'b011` (ERASE), or `3'b100` (INF in some benches), pulses a delayed `op_done` using `op_done_cnt` (assert after a few cycles) so the DUT does not hang in wait states.

This is **testbench-only timing**; it is not modeling a specific analog latency—only enough to let the FSM advance in simulation.

### 2.4 End-of-run scoreboard vs. `weight_matrix`

`controller_prog_verify_lut_tb` loads **expected** nibbles from `target/Controller/programming_inputs/weight_matrix.txt` into a flat array `weight_matrix[0:639]` and builds `weight_addresses[]` via `matrix_coords_to_address`. After all `CMD_PROG` transactions complete, it loops all rows/cols, uses `parse_ann_address` to index `ann_weight_matrix`, and increments `errs` on any `actual !== expected`. The report ends with `// Summary: %0d errors in 640 weights`.

---

## 3. Testbench architecture, tasks, and pass/fail accounting

There is no unified base class. Each TB is a single `module` with **local** counters and file handles.

### 3.1 Report files and handles

Representative patterns:

| Testbench | Primary counters / log | Report path (as in source) |
|-----------|------------------------|----------------------------|
| `controller_prog_verify_lut_tb` | `errs`, `erase_phase_count`, `reprog_retry_count`, cycle logger uses `fd` | `target/Controller/prog/prog_verify_report.txt` |
| `controller_prog_verify_lut_10w_tb` | `errs`, per-index PASS/ERROR lines | `target/Controller/prog/prog_verify_10w_report.txt` |
| `parallel_interface_controller_integration_tb` | `pass_c`, `fail_c` | `target/Controller/tb_pi_controller_integration.txt` |
| `controller_addr_pulse_tb` | PASS/ERROR lines per test; no numeric summary counter | `target/Controller/controller_addr_pulse_verify.txt` |
| `controller_inf_buffer_flow_tb` | `pass_count`, `fail_count` | `target/Controller/inf/controller_inf_buffer_flow_tb_log.txt` |
| `controller_host_read_reorder_tb` | PASS/FAIL per read + summary | `target/Controller/read/controller_host_read_reorder_report.txt` |

`controller_prog_verify_lut_tb` sets `fd = 0` before `$fclose` in one branch so an `always_ff` logger stops writing after the file is closed.

### 3.2 Tasks

- **`load_weights` / `load_weights_10`:** File I/O into `weight_matrix`; builds addresses.
- **`send_prog_and_wait`:** Waits until `!busy`, issues one-cycle `host_cmd = CMD_PROG` with `build_host_ann_word`, waits for `busy` to rise then fall (with timeout).
- **`run_cmd_test` (`controller_addr_pulse_tb`):** Drives a command, compares `ann_core_word` to `expected_ann_core_word` (READ scans until match; others sample after a few cycles).
- **`check_cmd` / `check_inf_row8` (`parallel_interface_controller_integration_tb`):** Encapsulate a full transaction check (see §5).
- **`send_inf_beat` / `dump_row0` (`controller_inf_buffer_flow_tb`):** Per-beat logging and buffer peek.

### 3.3 “Scoreboard” character

Checks are **directed**: compare RTL outputs and internal hierarchical peeks (`u_input_buffer.buffer_reg[...]`) to computed expectations. Failures increment integer counters and emit `FAIL` lines; some benches call `$fatal` or `$error` on timeout or nonzero failure count.

---

## 4. Verify / recovery injection in `controller_prog_verify_lut_tb` (detailed)

This bench is the primary regression for **asymmetric verify recovery**: under-programmed → re-PROG; over-programmed → ERASE then PROG again (per RTL). The TB **does not** call `force` on internal nets; it **only** manipulates `weight_read_data_mock`.

### 4.1 Injection gating: `current_weight_idx`, `in_verify_phase`, `verify_cycle_cnt`

- `current_weight_idx` is set at the start of `send_prog_and_wait` so the combinational override knows **which** weight in the sweep is active.
- `in_verify_phase = busy && (pulses == 3'b001 || pulses == 3'b000)` — i.e. busy during verify read train (`PULSE_MODE_READ`) or the subsequent low phase before/around `VERIFY_CHECK` (where `pulses` is `PULSE_MODE_HIZ` / `3'b000` in the RTL comb driving `pulses`).
- `verify_cycle_cnt` is a small FSM helper: it increments once when entering the verify read phase (`busy && pulses == 3'b001 && !was_in_verify`) and clears when `!busy`.

**Override condition (640-weight TB):**

```systemverilog
if (current_weight_idx >= 0 && in_verify_phase && (verify_cycle_cnt <= 1)) begin
```

Combined with the counter behavior, this keeps injection active through the early verify cycles (READ/WAIT/CHECK) for the current command.

### 4.2 Under-programmed (`read < expected`) → re-PROG path

**Index set:** `is_inject_read_lt(idx)` is true for:

`5, 15, 25, 50, 100, 200, 385, 420, 455, 490, 535, 580, 605, 625`.

**Injected value:**

```systemverilog
weight_read_data_mock = weight_matrix[current_weight_idx] - 1;  // requires weight_matrix[...] > 0
```

So the DUT’s `weight_read_data` is **one LSB step below** the expected nibble loaded from the file for that index.

**RTL response (for comparison):** In `S_VERIFY`, substate `VERIFY_CHECK`, if `weight_read_data < expected_weight` and `prog_retry_cnt < MAX_PROG_RETRIES` (`MAX_PROG_RETRIES = 3` in `controller_pkg`), `next_state = S_PROGRAM` and verify restarts from `VERIFY_IDLE` after another PROG cycle. If retries are exhausted, the RTL sets the erase path (`next_state = S_ERASE`).

### 4.3 Over-programmed (`read > expected`) → ERASE → PROG path

**Index set:** `is_inject_read_gt(idx)` is true for:

`10, 30, 70, 150, 250, 350, 395, 440, 475, 510, 555, 600, 615, 635`.

**Injected value:**

```systemverilog
weight_read_data_mock = weight_matrix[current_weight_idx] + 1;  // requires weight_matrix[...] < 15
```

So the mock ADC/readback is **one step above** the programmed target (guarded so 4-bit wrap is avoided in the test).

**RTL response:** In `VERIFY_CHECK`, if `weight_read_data > expected_weight`, the RTL asserts the verify-failure erase branch (`verify_failure_starts_erase` in the package) and `next_state = S_ERASE`. After `ERASE_COMPLETE` on the **non-host** path, if `retry_cnt < 3`, `next_state = S_PROGRAM` again to re-attempt programming.

### 4.4 Cycle-by-cycle expectation (conceptual, tied to RTL)

The RTL exposes verify as a **sub-FSM** (`VERIFY_IDLE` → `VERIFY_WAIT` (if `PULSE_TOTAL_READ > 1`) → `VERIFY_CHECK` → `VERIFY_DONE` or loop / branch). On `pulses`, during `S_VERIFY` with `verify_state == VERIFY_IDLE` or `VERIFY_WAIT`, the DUT drives `pulses = PULSE_MODE_READ` (`3'b001`) during active read-burst phases (see `controller.sv` comb on `pulses`). When the burst completes, `VERIFY_CHECK` compares `weight_read_data` to `expected_weight` (the expected nibble comes from buffer/read path in the RTL).

**Without injection:** comparison passes → `VERIFY_DONE` → return to `S_IDLE`.

**With under-program injection:** on the `VERIFY_CHECK` evaluation where `weight_read_data` is the injected `expected - 1`, comparison fails low → transition to `S_PROGRAM` (re-PROG) if retry budget allows; `pulses` then shows `PULSE_MODE_PROG` (`3'b010`) during `PROG_WRITE` with LUT-based timing. The TB’s phase logger labels a subsequent `PROG` after verify as `REPROG` and increments `reprog_retry_count` when phase transitions indicate a retry.

**With over-program injection:** `VERIFY_CHECK` sees `weight_read_data > expected_weight` → `S_ERASE`; during `ERASE_PULSE`, `pulses = PULSE_MODE_ERASE` (`3'b011`). The logger increments `erase_phase_count` when the logged phase string becomes `ERASE`. After erase completion, RTL returns to `S_PROGRAM` for another program attempt; the mock array may be updated again on `in_prog_core_phase` when the cell is rewritten.

The TB **asserts** at the end that both counters are nonzero:

```systemverilog
if (erase_phase_count == 0) $error("Expected ERASE path ...");
if (reprog_retry_count == 0) $error("Expected re-PROG path ...");
```

### 4.5 Phase logging vs. FSM internals

The always block that writes `prog_verify_report.txt` maps `pulses` and `in_prog_core_phase` to strings `PROG`, `REPROG`, `VERIFY`, `ERASE`, `PROG_PREP`, `COMPUTE`, `CHECK_DONE`. It explicitly notes that substates like `PROG_PREP` and `COMPUTE` update `last_phase` but may not print every internal RTL state—logging is aligned to **pulse-mode observables** the TB uses for documentation.

### 4.6 Compact bench `controller_prog_verify_lut_10w_tb` (related behavior)

Same mock array and `in_prog_core_phase` update. Injection scenarios on the first row only:

- Index `1`: `weight_read_data_mock = weight_matrix[1] - 1` when `verify_cycle_cnt <= 1` (re-PROG stress).
- Index `2`: `+1` when `weight_matrix[2] < 15` (ERASE stress).
- Index `5`: persistent `actual_from_ann - 1` until `w5_release_under` sets after `dut.state == S_ERASE` with `prev_dut_state == S_VERIFY`, modeling repeated under-read until ERASE / release.

---

## 5. Integration TB: `parallel_interface_controller_integration_tb`

### 5.1 Connectivity

- `parallel_interface` converts `host_data` / `host_cmd` to `valid`, `pi_data`, `address`, `cmd`. RTL `assign valid = (host_cmd != CMD_HIZ) && ann_tail_is_valid_onehot(host_data[23:0]);`
- `ann_controller` uses `pi_data` as `data`.
- **Verify readback** is `weight_read_data(buf_data[3:0])` — integration checks do not use `ann_weight_matrix`.

### 5.2 `check_cmd` — single-beat host, completion via `busy`

1. **`wait_until_idle(maxcyc)`:** spins while `busy`, up to `maxcyc` cycles.
2. **Quiet bus:** `host_cmd = CMD_HIZ`, `host_data = 0`, a few clock edges.
3. **Issue stimulus:** One cycle with `host_data = build_host_ann_word(d, a)` and `host_cmd = c`, then **deassert** (`CMD_HIZ`, zero data) on the next cycle—comment documents that holding command high would re-arm INF incorrectly.
4. **`wait(busy)`:** blocks until the controller accepts and raises `busy`.
5. **Monitor loop:** While `busy`, on each `posedge clk`:
   - Count `busy_cycles`.
   - `pulse_ok` if `pulses === exp_pulse` at least once.
   - Track `saw_pulse` (last nonzero `pulses`).
   - `word_ok` if `ann_core_word === exp` at least once, with `exp = exp_word(a,d)` (`pack_ann_core_word` of address/data).
6. **Pass criteria:** Both `pulse_ok` and `word_ok` must be true; then `pass_c++`. Else `fail_c++` and log `FAIL` with `saw_pulse` / `saw_word`.
7. **Stuck busy:** If still `busy` after the loop, `fail_c++` again.
8. **`dump_buffer_snapshot`:** reads `u_input_buffer.buffer_reg[0:63]` for post-transaction visibility.

**“Transaction complete”** for the next stimulus: the task ends with `busy` low (or fails), and the caller inserts `@(posedge clk)` between cases. The next `check_cmd` begins with `wait_until_idle`, so the sequence is explicitly **idle-gated**.

### 5.3 `check_inf_row8` — nine-cycle INF burst and parallel monitor

For INF, the TB must not miss COLLECT-phase activity:

- **`fork`:** One branch drives **nine** consecutive cycles of `CMD_INF` with the same packet, then deasserts.
- **Parallel branch:** `wait(busy)` then the same style of `while (busy)` monitoring as `check_cmd`, but expects `PULSE_MODE_INF` on `pulses` at least once and the same `ann_core_word` match behavior (comment notes the word may change between COLLECT and COMPUTE).

**Completion:** `join` waits for both drive and monitor; then buffer dump, pass/fail accounting, and idle check.

### 5.4 Summary line

The `initial` block runs ten scenarios (`01_READ` … `10_ERASE`) and prints:

```systemverilog
$fdisplay(fd, "// Summary: PASS=%0d FAIL=%0d", pass_c, fail_c);
```

Nonzero `fail_c` triggers `$fatal`.

---

## 6. Other controller testbenches (code-grounded summary)

### 6.1 `controller_addr_pulse_tb`

Thirty directed `run_cmd_test` calls covering `CMD_PROG`, `CMD_READ`, `CMD_ERASE`. Checks `ann_core_word` packing against `expected_ann_core_word`. Uses the same `op_done` mock pattern as other benches. **No** `ann_weight_matrix`.

### 6.2 `controller_host_erase_tb`

Programs two cells (`ADDR_A` / `ADDR_B` with weights), issues `CMD_ERASE` on one, uses `ann_weight_matrix` updated on `in_prog_core_phase`, `weight_read_data_mock = actual_from_ann`. Report asserts cell A cleared and cell B preserved. `op_done` timing follows `PULSE_TOTAL_READ` / `PULSE_TOTAL_ERASE` for read/erase pulses.

### 6.3 `controller_host_read_reorder_tb`

Programs eight addresses, then issues `CMD_READ` in permuted order `read_perm[]`. Compares `ann_core_word` during `S_READ` and mock readback. Pass/fail tracked per read in the report.

### 6.4 `controller_inf_buffer_flow_tb`

While `writes_seen < 8`, calls `send_inf_beat` and increments `writes_seen` when `buf_reg_ctrl == CTRL_DATA_LOAD && buf_read_write`. Fails if compute (`CTRL_COMPUTE` or `pulses == PULSE_MODE_INF`) starts early. After eight writes, optionally one more INF beat to enter COMPUTE, then samples `D0..D7` against expected column bits from a row snapshot; increments `pass_count` / `fail_count` per bit lane check.

---

## 7. Waveform wrapper modules (`*_waves_tb`)

Wrappers (e.g. `controller_prog_verify_lut_tb_waves_tb`) **only** instantiate the corresponding regular TB module. They add **no** new checks. Companion `.do` scripts under `verif/Controller/do/waves/` preload signal groups for debug (FSM states, pulse counters, LUT fields, `D0..D7`, etc.).

---

## 8. Input_Buffer and Parallel_Interface benches (brief)

- **`input_buffer_bit_serial_tb`, `input_buffer_reset_behavior_tb`, `input_buffer_full_overwrite_tb`:** Directed writes and compares against `buffer_reg`; summaries like `SUMMARY: N passed, M failed` in logs under `target/Input_Buffer/`.
- **`parallel_interface_extract_tb`:** Exercises decode assumptions with `build_host_ann_word` and related patterns; six checks, summary in `target/Parallel_Interface/parallel_interface_extract_tb_log.txt`.

---

## 9. Verification gaps (still accurate)

The following are **not** present in the repository as of this documentation pass:

- UVM agents/scoreboards, coverage collection, or constrained-random generation.
- SVA formal verification or property proofs.
- Gate-level or timing-accurate signoff flows.

---

## 10. File reference index (primary TB sources)

| Area | Path |
|------|------|
| Program–verify LUT (640) | `verif/Controller/tb/regular/prog/controller_prog_verify_lut_tb.sv` |
| Program–verify LUT (10) | `verif/Controller/tb/regular/prog/controller_prog_verify_lut_10w_tb.sv` |
| PI + controller + buffer | `verif/Controller/tb/parallel_interface_controller_integration_tb.sv` |
| Address / pulse pack | `verif/Controller/tb/regular/prog/controller_addr_pulse_tb.sv` |
| Host erase | `verif/Controller/tb/regular/erase/controller_host_erase_tb.sv` |
| Read reorder | `verif/Controller/tb/regular/read/controller_host_read_reorder_tb.sv` |
| INF flow | `verif/Controller/tb/regular/inf/controller_inf_buffer_flow_tb.sv` |
| Verify FSM reference | `source/Controller/controller.sv` (`S_VERIFY`, `VERIFY_CHECK`, `S_ERASE`) |

This completes the verification picture **as implemented** in the `.sv` sources above.
