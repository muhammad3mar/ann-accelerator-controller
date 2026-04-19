# Controller case studies (host command scenarios)

Each scenario follows the same structure: **stimulus**, **controller path**, **outputs**, **evidence** (testbench + log under `target/Controller/` where applicable).

Host-side packing is documented in [`source/Parallel_Interface/parallel_interface.sv`](../../source/Parallel_Interface/parallel_interface.sv): `host_data[31:24]` is the data byte, `host_data[23:0]` is the one-hot `{PE, SA, col, row}` tail decoded to `address[15:0]`; `host_cmd` is forwarded as `cmd`. `valid` is high when `host_cmd != CMD_HIZ`.

---

## 1. Idle / no transaction (`CMD_HIZ`)

**Stimulus:** `host_cmd = CMD_HIZ` (3'b000). Parallel interface keeps `valid` low.

**Controller path:** Stay in `S_IDLE`. No address/data capture on the idle-to-active path until a non-HIZ command is seen with `valid`.

**Outputs:** `busy = 0`, `ann_core_word = 0`, `pulses = 000` (HIZ). Buffer control remains idle.

**Evidence:** All testbenches implicitly cover idle between transactions; no dedicated log (absence of activity).

---

## 2. Program one weight (`CMD_PROG`)

**Stimulus:** Assert `valid` with `cmd = CMD_PROG`, `data[7:0]` carrying the quantized weight (nibble used from buffer path), and `address[15:0]` encoding the memristor location per [`controller_pkg::parse_ann_address`](../../source/Controller/controller_pkg.sv): bits `[9:8]` block, `[7:6]` sub-block, `[5:3]` column id, `[2:0]` row id (upper bits reserved).

**Controller path:** `S_IDLE` → `S_PROGRAM` (program sub-FSM: `PROG_HIZ` → `PROG_SELECT` → `PROG_ENABLE` → `PROG_WRITE` holds until pulse counter done → `PROG_DISABLE` → `PROG_COMPLETE`) → `S_VERIFY`.

In `S_PROGRAM`, the controller writes the captured weight into the input buffer at `address_reg[5:0]`, then reads it back for the program phase so the same location supplies **expected_weight** during verify.

**Outputs:**

- `ann_core_word = { data_byte, one_hot(PE,SA,col,row) }` with the data byte from `data_reg` in program/verify (see RTL comment in [`ann_controller`](../../source/Controller/controller.sv)).
- `pulses = 010` during `PROG_ENABLE` and `PROG_WRITE`.
- During verify substates `VERIFY_READ` / `VERIFY_WAIT`, `pulses = 001` (read).

**Evidence:**

- [`verif/Controller/tb/regular/prog/controller_prog_verify_lut_tb.sv`](../../verif/Controller/tb/regular/prog/controller_prog_verify_lut_tb.sv) — full PROG→VERIFY loop and retry branches (LUT PROG pulses; non-LUT snapshot in `backup/controller_prog_verify_fixed_pulse/`).
- [`target/Controller/prog/prog_verify_report.txt`](../../target/Controller/prog/prog_verify_report.txt) — timestamped `Phase: PROG` / `Phase: VERIFY` lines with `ann_core_word` and `programmed_weight`.

---

## 3. Verify outcomes and retries (part of `CMD_PROG` flow)

After programming, the controller enters `S_VERIFY` with sub-FSM: `VERIFY_READ` → `VERIFY_WAIT` (countdown) → `VERIFY_CHECK` → `VERIFY_DONE` or loop.

**Match (`weight_read_data == expected_weight`):** `VERIFY_DONE` → return to `S_IDLE` (direct-address single-weight flow).

**Under-programmed (`read < expected`):** If `prog_retry_cnt < MAX_PROG_RETRIES` (3), go back to `S_PROGRAM` / `PROG_HIZ` and repeat program pulses. Otherwise set error indication and go to `S_ERASE`.

**Over-programmed (`read > expected`):** Go to `S_ERASE`; after erase sub-FSM completes, typically back to `S_PROGRAM` if `retry_cnt < 3`, else abort to `S_IDLE` with error.

**Outputs:** Same `ann_core_word` packing; read pulses in verify; erase pulses `011` in erase active substates.

**Evidence:** `prog_verify_report.txt` sections marked `re-PROG sequence` and `ERASE sequence`; wave TB `controller_prog_verify_lut_tb_waves_tb` ([runbook](../wave_testbench_runbook/WAVE_TESTBENCH_RUNBOOK.md)).

---

## 4. Direct read (`CMD_READ`)

**Stimulus:** `valid` with `cmd = CMD_READ` and target `address`.

**Controller path:** `S_IDLE` → `S_READ` until `pulse_done` (duration `TREAD * PULSE_NUM_READ` from package) → `S_IDLE`.

**Outputs:** `pulses = 001` for the read window. `ann_core_word` uses `data_reg` in the data byte field (host-supplied byte on the initiating beat).

**Evidence:** [`verif/Controller/tb/regular/prog/controller_addr_pulse_tb.sv`](../../verif/Controller/tb/regular/prog/controller_addr_pulse_tb.sv); [`target/Controller/controller_addr_pulse_verify.txt`](../../target/Controller/controller_addr_pulse_verify.txt) (per-test PASS and expected `ann_core_word`).

---

## 5. Erase (`CMD_ERASE`)

**Stimulus:** `valid` with `cmd = CMD_ERASE` and target `address`.

**Controller path:** `S_IDLE` → `S_ERASE` with sub-FSM `ERASE_HIZ` → `ERASE_SELECT` → `ERASE_ENABLE` → `ERASE_PULSE` (hold until `pulse_done`) → `ERASE_DISABLE` → `ERASE_COMPLETE`. From `ERASE_COMPLETE`, either `S_PROGRAM` (retry) or `S_IDLE` if erase retries exhausted.

**Outputs:** `pulses = 011` while erase mux states are active (`ERASE_ENABLE`, `ERASE_PULSE`, `ERASE_DISABLE`).

**Evidence:** `controller_prog_verify_lut_tb` (erase after failed verify); [`target/Controller/prog/prog_verify_report.txt`](../../target/Controller/prog/prog_verify_report.txt); `controller_host_erase_tb` / [`target/Controller/erase/controller_host_erase_report.txt`](../../target/Controller/erase/controller_host_erase_report.txt).

---

## 6. Inference (`CMD_INF`)

**Stimulus:** `valid` with `cmd = CMD_INF`. Pixel bytes arrive on `data` while the FSM is in `S_COLLECT_DATA` (controller uses **current** `data` from the parallel interface for buffer writes, not only the registered idle capture).

**Controller path:**

- `S_IDLE` → `S_COLLECT_DATA`: on each `valid` beat, write to buffer at `buf_write_addr`; after eight accepted pixels for the current row (`data_count` 0..7), next valid completion goes to `S_COMPUTE`.
- `S_COMPUTE`: `CTRL_COMPUTE`, buffer read, `buf_bit_sel` steps 0..7 LSB-first each cycle; `pulses = 100` (INF) until `pulse_done` (`PULSE_TOTAL_INF`, at least 8 cycles per package).
- `S_RESULT`: `CTRL_RESULT_OUT`, then `S_IDLE`.

**Outputs:** INF pulse mode on `pulses`; bit-serial path uses `buf_bit_sel` / `D0..D7` at the buffer boundary in integration.

**Evidence:** `controller_addr_pulse_tb` (INF pulse/word checks); [`verif/Controller/tb/parallel_interface_controller_integration_tb.sv`](../../verif/Controller/tb/parallel_interface_controller_integration_tb.sv); `parallel_interface_controller_integration_tb_waves_tb` in [runbook](../wave_testbench_runbook/WAVE_TESTBENCH_RUNBOOK.md).

---

## 7. Legacy reset state (`S_RESET`)

The enum includes `S_RESET` (asserts `ann_reset`, then would enter program). **Current** `S_IDLE` command decode does not branch to `S_RESET` for any host `cmd`; it remains in the RTL for compatibility with older stimulus paths. Mention only if asked about unused states.

---

## Quick reference: pulse encoding

Aligned with [`controller_pkg::pulse_mode_t`](../../source/Controller/controller_pkg.sv) and [`controller_addr_pulse_verify.txt`](../../target/Controller/controller_addr_pulse_verify.txt) header:

| Mode  | `pulses` (3-bit) |
|-------|--------------------|
| HIZ   | 000                |
| READ  | 001                |
| PROG  | 010                |
| ERASE | 011                |
| INF   | 100                |
