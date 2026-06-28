# Regular Testbench Runbook

This runbook lists **batch** testbenches (top-level `*_tb` modules that are **not** `*_waves_tb` wrappers). Each entry gives the **compile** command and **run** command using [`scripts/run_sim.py`](../../scripts/run_sim.py).

**Notes**

- `sim` **recompiles verification** for the module before launching ModelSim in **batch** mode (`vsim -c`) unless you pass GUI options.
- For **GUI + waveforms**, use the [Wave Testbench Runbook](WAVE_TESTBENCH_RUNBOOK.md) (`*_waves_tb` + `--do-file`).
- **Run every regular test** for a module:  
  `python scripts/run_sim.py run_all -m <Module>`  
  Logs: `target/<Module>/<testbench>_log.txt`

**Compile (per module, verification includes RTL dependencies)**

```bash
python scripts/run_sim.py compile -m Controller -t verif
python scripts/run_sim.py compile -m Input_Buffer -t verif
python scripts/run_sim.py compile -m Parallel_Interface -t verif
```

---

## Controller

**Compile:** `python scripts/run_sim.py compile -m Controller -t verif`

**Run all regular Controller tests:** `python scripts/run_sim.py run_all -m Controller`

### `controller_addr_pulse_tb`

- **Tests:** `ann_core_word` packing and pulse modes for READ/PROG/ERASE/INF.
- **Run:** `python scripts/run_sim.py sim -m Controller -tb controller_addr_pulse_tb`

### `controller_prog_verify_lut_tb`

- **Tests:** Full PROG→VERIFY flow with re-PROG / ERASE branches (640-weight sweep); PROG pulse length from `programming_inputs/weight_pulse_lut.mem` (RTL default).
- **Run:** `python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb`

### `parallel_interface_controller_integration_tb`

- **Tests:** PI + `ann_controller` + input buffer integration.
- **Run:** `python scripts/run_sim.py sim -m Controller -tb parallel_interface_controller_integration_tb`

### `controller_host_erase_tb`

- **Tests:** Host `CMD_ERASE` on one cell; pulse/trace report under `target/Controller/erase/`.
- **Run:** `python scripts/run_sim.py sim -m Controller -tb controller_host_erase_tb`

### `controller_inf_buffer_flow_tb`

- **Tests:** INF host-packet flow into `input_buffer`: shows data-load writes during collect phase, row0 content evolution, and bit-serial `D0..D7` output once compute starts.
- **Output:** `target/Controller/inf/controller_inf_buffer_flow_tb_log.txt` (single merged log + TB report).
- **Run:** `python scripts/run_sim.py sim -m Controller -tb controller_inf_buffer_flow_tb`

### `controller_host_read_reorder_tb`

- **Tests:** Program 8 weights at 8 addresses via PI, then host `CMD_READ` in permuted order; mock memristor matrix + `ann_core_word` / `weight_read_data` checks.
- **Report:** `target/Controller/read/controller_host_read_reorder_report.txt`
- **Run:** `python scripts/run_sim.py sim -m Controller -tb controller_host_read_reorder_tb`

---

## Input_Buffer

**Compile:** `python scripts/run_sim.py compile -m Input_Buffer -t verif`

**Run all regular Input_Buffer tests:** `python scripts/run_sim.py run_all -m Input_Buffer`

**Outputs:** `target/input_buffer/<testbench>_log.txt` — one file: ModelSim transcript, then `// TB REPORT` moved to the **last** lines by `run_sim.py`.

### `input_buffer_bit_serial_tb`

- **Tests:** Bit-serial `D0..D7` / `bit_sel` behavior.
- **Run:** `python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_bit_serial_tb`
- **Output:** `target/input_buffer/input_buffer_bit_serial_tb_log.txt` (merged log + TB report)

### `input_buffer_reset_behavior_tb`

- **Tests:** Reset behavior during load and bit-serial phases.
- **Run:** `python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_reset_behavior_tb`
- **Output:** `target/input_buffer/input_buffer_reset_behavior_tb_log.txt` (merged log + TB report)

### `input_buffer_full_overwrite_tb`

- **Tests:** Fill all 64 buffer entries, dump rows, then overwrite 10 new pixels (addr `0..9`) and dump rows after each write to visualize replacement behavior.
- **Run:** `python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_full_overwrite_tb`
- **Output:** `target/input_buffer/input_buffer_full_overwrite_tb_log.txt` (merged log + TB report)

---

## Parallel_Interface

**Compile:** `python scripts/run_sim.py compile -m Parallel_Interface -t verif`

**Run all regular Parallel_Interface tests:** `python scripts/run_sim.py run_all -m Parallel_Interface`

### `parallel_interface_extract_tb`

- **Tests:** Decode of `host_data` → `data` / `address` / `cmd` for representative patterns.
- **Run:** `python scripts/run_sim.py sim -m Parallel_Interface -tb parallel_interface_extract_tb`

---

## Discover testbench names

```bash
python scripts/run_sim.py list
```
