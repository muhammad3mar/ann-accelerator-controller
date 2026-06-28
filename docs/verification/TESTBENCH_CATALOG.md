# Testbench Catalog

This file lists the testbenches currently present in the project and what each one checks.

**Batch compile/run commands** for each regular top-level testbench: [Regular Testbench Runbook](REGULAR_TESTBENCH_RUNBOOK.md).

**GUI + waveform runs** (`*_waves_tb` + `--do-file`): [Wave Testbench Runbook](WAVE_TESTBENCH_RUNBOOK.md).

## Controller testbenches

- `controller_addr_pulse_tb`
  - Verifies `ann_core_word` packing from address/data.
  - Verifies pulse mode behavior for READ/PROG/ERASE/INF.

- `controller_prog_verify_lut_tb`
  - Loads weights from `target/Controller/programming_inputs/weight_matrix.txt`; drives PROG through PI for the full 640-weight sweep.
  - Full PROG→VERIFY flow with asymmetric retry (re-PROG / ERASE→PROG).
  - PROG_WRITE length follows `programming_inputs/weight_pulse_lut.mem` (matches default `ann_controller` `USE_WEIGHT_PULSE_LUT`).
  - Non-LUT (fixed `PULSE_TOTAL_PROG`) variant archived under `backup/controller_prog_verify_fixed_pulse/`.

- `parallel_interface_controller_integration_tb`
  - Integration of `parallel_interface` + `ann_controller` + `input_buffer`.
  - Checks command path, pulse response, and busy/idle behavior.

- `controller_host_erase_tb`
  - Host `CMD_ERASE` on one programmed cell; second cell stays programmed.
  - Logs `busy` / `pulses` / `ann_core_word` / FSM during erase; mock matrix before/after in `target/Controller/erase/controller_host_erase_report.txt`.

- `controller_inf_buffer_flow_tb`
  - INF-focused integration trace: host `CMD_INF` packet stream, collect-phase writes into input buffer, and bit-serial `D0..D7` behavior when compute starts.
  - Report under `target/Controller/inf/controller_inf_buffer_flow_tb_log.txt`.

- `controller_host_read_reorder_tb`
  - Programs eight 4-bit weights at eight distinct ANN addresses through the PI, then issues `CMD_READ` for those cells in a non-sequential order.
  - Report under `target/Controller/read/controller_host_read_reorder_report.txt`: programmed map, each host READ command (packet hex), and DUT `S_READ` samples (`pulses`, `ann_core_word`, mock `weight_read_data`).

## Input_Buffer testbenches

- `input_buffer_bit_serial_tb`
  - Verifies bit-serial output on `D0..D7`, LSB-first by `bit_sel`.
  - Checks first group (addr 0..7) and second group (addr 8..15).

- `input_buffer_reset_behavior_tb`
  - Verifies reset during data load and during bit-serial output, including post-reset buffer state.

## Parallel_Interface testbenches

- `parallel_interface_extract_tb`
  - Verifies extraction/decoding of `data` (MSB byte), `address` (from ann tail), and `cmd` (`host_cmd`) for representative host patterns.

## Wave wrapper testbenches (`*_waves_tb`)

These wrapper benches instantiate existing benches for wave viewing and do not introduce new functional checks.

### Controller wrappers
- `controller_prog_verify_lut_tb_waves_tb` -> wraps `controller_prog_verify_lut_tb`
- `parallel_interface_controller_integration_tb_waves_tb` -> wraps `parallel_interface_controller_integration_tb`
- `controller_host_erase_tb_waves_tb` -> wraps `controller_host_erase_tb`

### Input_Buffer wrappers
- `input_buffer_bit_serial_tb_waves_tb` -> wraps `input_buffer_bit_serial_tb`
- `input_buffer_reset_behavior_tb_waves_tb` -> wraps `input_buffer_reset_behavior_tb`
