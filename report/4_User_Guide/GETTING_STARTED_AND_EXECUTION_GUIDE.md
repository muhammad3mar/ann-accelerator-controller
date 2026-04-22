# Getting Started and Execution Guide

## 1) Prerequisites from Repository Scripts

The simulation flow is driven by `scripts/run_sim.py`, which invokes:

- `vlog` for compilation
- `vsim` for simulation

The script checks tool availability (`vlog -version`) and prints a warning if ModelSim is not in `PATH`.

Documented expected ModelSim location in the script:

- `/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem`

## 2) Quick Environment Check

From project root:

```bash
python scripts/run_sim.py list
```

This prints available modules, compile lists, and testbench names from the script’s `MODULES` map.

## 3) Compile Flow

## Compile verification bundle (recommended before running)

```bash
python scripts/run_sim.py compile -m Controller -t verif
python scripts/run_sim.py compile -m Input_Buffer -t verif
python scripts/run_sim.py compile -m Parallel_Interface -t verif
```

## Compile RTL only (optional)

```bash
python scripts/run_sim.py compile -m Controller -t rtl
python scripts/run_sim.py compile -m Input_Buffer -t rtl
python scripts/run_sim.py compile -m Parallel_Interface -t rtl
```

## 4) Run Single Tests (Batch / Log Mode)

## Controller examples

```bash
python scripts/run_sim.py sim -m Controller -tb controller_addr_pulse_tb
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb
python scripts/run_sim.py sim -m Controller -tb controller_host_erase_tb
python scripts/run_sim.py sim -m Controller -tb controller_inf_buffer_flow_tb
python scripts/run_sim.py sim -m Controller -tb controller_host_read_reorder_tb
python scripts/run_sim.py sim -m Controller -tb parallel_interface_controller_integration_tb
```

## Input_Buffer examples

```bash
python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_bit_serial_tb
python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_reset_behavior_tb
python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_full_overwrite_tb
```

## Parallel_Interface example

```bash
python scripts/run_sim.py sim -m Parallel_Interface -tb parallel_interface_extract_tb
```

## 5) Run All Tests for Module(s)

Implemented behavior in `run_all` command:

```bash
python scripts/run_sim.py run_all -m Controller
python scripts/run_sim.py run_all -m Input_Buffer
python scripts/run_sim.py run_all -m Parallel_Interface
```

Notes from script behavior:

- If no module is specified, `run_all` defaults to `Input_Buffer` and `Parallel_Interface`.
- Logs are emitted under `target/<module_dir>/`.

## 6) Waveform Runs (GUI + .do)

Wave runs are triggered by using wave wrapper TB names and `--do-file`. The script forces GUI mode when a do-file is provided.

## Controller wave runs

```bash
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb_waves_tb --do-file verif/Controller/do/waves/controller_prog_verify_lut_tb_waves.do
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_10w_tb_waves_tb --do-file verif/Controller/do/waves/controller_prog_verify_lut_10w_tb_waves.do
python scripts/run_sim.py sim -m Controller -tb parallel_interface_controller_integration_tb_waves_tb --do-file verif/Controller/do/waves/parallel_interface_controller_integration_tb_waves.do
python scripts/run_sim.py sim -m Controller -tb controller_host_erase_tb_waves_tb --do-file verif/Controller/do/waves/controller_host_erase_tb_waves.do
python scripts/run_sim.py sim -m Controller -tb controller_inf_buffer_flow_tb_waves_tb --do-file verif/Controller/do/waves/controller_inf_buffer_flow_tb_waves.do
```

## Input_Buffer wave runs

```bash
python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_bit_serial_tb_waves_tb --do-file verif/Input_Buffer/do/waves/input_buffer_bit_serial_tb_waves.do
python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_reset_behavior_tb_waves_tb --do-file verif/Input_Buffer/do/waves/input_buffer_reset_behavior_tb_waves.do
```

## 7) Clean Flow

```bash
python scripts/run_sim.py clean -a
python scripts/run_sim.py clean -w
python scripts/run_sim.py clean -t
python scripts/run_sim.py clean -t -m Controller
```

Implemented cleanup behavior:

- Removes/recreates `work/`.
- Removes module target files according to script logic.
- Removes temporary simulator artifacts such as `transcript` and `.wlf`.

## 8) Where Results Are Written

## Controller durable reports

- `target/Controller/controller_addr_pulse_verify.txt`
- `target/Controller/prog/prog_verify_report.txt`
- `target/Controller/prog/prog_verify_10w_report.txt`
- `target/Controller/erase/controller_host_erase_report.txt`
- `target/Controller/read/controller_host_read_reorder_report.txt`
- `target/Controller/tb_pi_controller_integration.txt`
- `target/Controller/inf/controller_inf_buffer_flow_tb_log.txt`

## Input_Buffer and Parallel_Interface logs

- `target/Input_Buffer/*_log.txt` (or module-mapped output directory used by the script run environment)
- `target/Parallel_Interface/parallel_interface_extract_tb_log.txt`

## Input stimuli / LUT artifacts

- `target/Controller/programming_inputs/weight_matrix.txt`
- `target/Controller/programming_inputs/weight_pulse_lut.mem`
- `target/Controller/programming_inputs/weight_pulse_lut_table.txt`

## 9) How to Read Outputs

## Report-style files

- Look for explicit PASS/FAIL lines and final summary sections.
- Controller program/verify reports include phase traces (`PROG`, `VERIFY`, `ERASE`, `REPROG`) and final mismatch summary.

## Log-style transcript files

- Include ModelSim run transcript and TB report blocks.
- In Input_Buffer flow, script post-processing relocates the TB report block to the physical end of the log.

## 10) Known Practical Notes from Existing Files

- `sim` command compiles verification before running.
- Wave wrapper TBs do not introduce extra functional checks; they reuse base testbench behavior.
- The 640-weight program/verify flow is significantly longer than compact tests by design.
