# ANN controller — user guide (host / integrator)

This guide describes how to **drive** the design from the host side and how to **re-run verification**. RTL details live in [`source/Controller/controller.sv`](../../source/Controller/controller.sv) and [`source/Parallel_Interface/parallel_interface.sv`](../../source/Parallel_Interface/parallel_interface.sv).

## Interface signals

**Clock and reset:** The controller uses `clk` and active-low `rst_n`. The parallel interface uses active-high `reset`; integration testbenches tie these appropriately.

**Host to parallel interface:**

- `host_data[31:0]` — same layout as `ann_core_word`: byte in `[31:24]`, one-hot `{PE, SA, col, row}` in `[23:0]`.
- `host_cmd[2:0]` — command; `CMD_HIZ` means “no transaction.”

**Controller inputs (from PI):**

- `valid` — high when `host_cmd != CMD_HIZ`.
- `data[7:0]` — `host_data[31:24]`.
- `address[15:0]` — decoded from `host_data[23:0]` (see `ann_tail_to_parallel_addr` in [`parallel_interface_pkg`](../../source/Parallel_Interface/parallel_interface_pkg.sv)).
- `cmd[2:0]` — copy of `host_cmd`.

**Status:**

- `busy` — high while the controller is in any active state (`S_PROGRAM`, `S_VERIFY`, `S_ERASE`, `S_READ`, `S_COLLECT_DATA`, `S_COMPUTE`, `S_RESULT`). Low in `S_IDLE`.

**ANN core:**

- `ann_core_word[31:0]` — packed data byte + physical address tail.
- `pulses[2:0]` — operation mode (read / program / erase / inference) per cycle; see [`controller_pkg::pulse_mode_t`](../../source/Controller/controller_pkg.sv).

**Input buffer:** The controller issues `buf_reg_ctrl`, `buf_reg_add`, `buf_read_write`, `buf_bit_sel`, and `buf_data_out`. The buffer raises `buf_ready` per its own protocol.

## Commands

| `host_cmd`   | Name   | Purpose |
|-------------|--------|---------|
| `3'b000`    | HIZ    | Idle; `valid` low. |
| `3'b001`    | READ   | Verification / debug read at `address`. |
| `3'b010`    | PROG   | Program weight; byte in `data`; location in `address`. Automatic verify follows. |
| `3'b011`    | ERASE  | Erase at `address` (also used from verify failure path). |
| `3'b100`    | INF    | Inference: load a row of pixels, then compute / result phases. |

Encoding is in [`parallel_interface_pkg`](../../source/Parallel_Interface/parallel_interface_pkg.sv).

## Address format

The 16-bit `address` field uses the lower bits as in [`parse_ann_address`](../../source/Controller/controller_pkg.sv):

- `[9:8]` — block (PE), `[7:6]` — sub-block (SA), `[5:3]` — column id, `[2:0]` — row id. Upper bits are reserved.

## Typical sequences

1. **Program weights:** For each cell, present `CMD_PROG` with weight in `data` and cell address. Wait until `busy` falls. Internal flow stores the weight in the buffer, programs, then verifies (with possible reprogram or erase).
2. **Debug read:** `CMD_READ` with same address layout; observe core read pulses and downstream quantizer if present.
3. **Erase:** `CMD_ERASE` when an explicit erase is required.
4. **Inference:** Issue `CMD_INF`, then supply pixel bytes with `valid` high while the controller is in data collection (see case study in [CONTROLLER_CASE_STUDIES.md](CONTROLLER_CASE_STUDIES.md)). After `busy` drops, the buffer/result path reflects the RTL’s `CTRL_RESULT_OUT` phase.

**Rule of thumb:** Do not start a new command until `busy` is low unless your system-level protocol explicitly overlaps transactions (the current RTL assumes idle completion per command).

## Timing and pulses

Nominal timing is in `controller_pkg`: per-mode `T*` (high cycles per burst), `PULSE_NUM_*` (burst count), and `PULSE_GAP` (HIZ cycles between bursts). `PULSE_TOTAL_*` is the full train length `N*T + max(0,N-1)*PULSE_GAP` (INF total is at least 8). The `pulses` bus follows that train (active mode vs `000`). With `USE_WEIGHT_PULSE_LUT`, first PROG repeats that macro train `R` times per weight (`R` from `weight_pulse_lut.mem`), inserting `PULSE_GAP` idle cycles between copies so each repeat is visible on `pulses` (re-PROG uses a minimal 1-cycle train).

## Regenerating verification outputs

From the repository root:

```bash
python scripts/run_sim.py compile -m Controller -t verif
python scripts/run_sim.py sim -m Controller -tb controller_addr_pulse_tb
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb
python scripts/run_sim.py sim -m Controller -tb parallel_interface_controller_integration_tb
```

Logs and dumps are written under [`target/Controller/`](../../target/Controller/). More testbenches and wave runs are listed in [`docs/TESTBENCH_CATALOG.md`](../TESTBENCH_CATALOG.md) and the [wave testbench runbook](../wave_testbench_runbook/WAVE_TESTBENCH_RUNBOOK.md).

## Further reading

- Step-by-step scenarios: [CONTROLLER_CASE_STUDIES.md](CONTROLLER_CASE_STUDIES.md)
- State diagrams: [CONTROLLER_OPERATIONS_DIAGRAM.md](CONTROLLER_OPERATIONS_DIAGRAM.md)
- Simulation driver: [`scripts/README_SIM.md`](../../scripts/README_SIM.md)
