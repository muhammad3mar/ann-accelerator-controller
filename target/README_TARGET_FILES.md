# Target File Descriptions

This file gives a short description of each generated artifact under `target/`: what it validates and how the testbench produces the result.

**Batch sim logs:** `target/**/<testbench>_log.txt` files are ModelSim transcripts from `run_sim.py`. They are **not** meant to live in the repo (see root `.gitignore`); functional outputs below are the durable reports.

## `target/Controller`

- `tb_pi_controller_integration.txt`  
  Parallel-interface to controller integration report. It verifies host payload decode (`cmd/data/address`) and that downstream controller behavior matches decoded traffic.

- `programming_inputs/weight_matrix.txt`  
  Input stimulus matrix used by programming benches. Testbenches consume these quantized values and compare programmed ANN-cell contents against the expected matrix entries.

- `programming_inputs/weight_pulse_lut.mem`  
  LUT memory file mapping weight-related pulse behavior. LUT-enabled benches load this file to drive pulse-length selection in program/verify runs.

- `programming_inputs/weight_pulse_lut_table.txt`  
  Human-readable LUT table companion for `weight_pulse_lut.mem`. It documents expected pulse mapping entries used by LUT-based verification.

- `controller_addr_pulse_verify.txt`  
  Directed address/pulse verification report from `controller_addr_pulse_tb`. It checks packed `ann_address` fields and pulse mode selection for each command case (PROG/READ/ERASE/INF).

## `target/Controller/prog`

- `prog_verify_report.txt`  
  Main PROG->VERIFY behavior report from `controller_prog_verify_lut_tb`. PROG_WRITE length follows `programming_inputs/weight_pulse_lut.mem`. It exercises equal/under/over verify outcomes and logs retry/reprogram/erase progression with timestamps. A non-LUT (fixed `PULSE_TOTAL_PROG`) snapshot of the old flow lives under `backup/controller_prog_verify_fixed_pulse/`.

## `target/Controller/erase`

- `controller_host_erase_report.txt`  
  Host-directed erase report from `controller_host_erase_tb`. It proves single-cell erase behavior while preserving an untouched programmed cell, with cycle-by-cycle pulse/state traces.

## `target/Controller/read`

- `controller_host_read_reorder_report.txt`  
  From `controller_host_read_reorder_tb`: programmed weights and addresses, then out-of-order host `CMD_READ` transactions with expected packet, `ann_address` (binary field breakdown in the log), and mock memristor read data per step.

## `target/Controller/inf`

- `controller_inf_buffer_flow_tb_log.txt`  
  INF buffer-flow trace from `controller_inf_buffer_flow_tb`: host INF packet fields, collect-phase writes into the input buffer (row snapshots), and observed bit-serial `D0..D7` values once compute starts. Ends with a TB summary block.

## `target/input_buffer`

For Input_Buffer testbenches, `run_sim.py` writes one file per run: `<testbench>_log.txt`. It contains the full ModelSim transcript plus a `// TB REPORT` block (summary + RESULT). The script moves that block to the **very end** of the file so it appears after the ModelSim `$finish` trailer.

## `target/Parallel_Interface`

(Parallel_Interface batch tests write `parallel_interface_extract_tb_log.txt` when run; that transcript pattern is gitignored.)

