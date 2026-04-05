# Testbench Catalog

This file lists the testbenches currently present in the project and what each one checks.

## Controller testbenches

- `controller_weight_program_tb`
  - Loads quantized weights from `target/Controller/weight_matrix.txt`.
  - Sends PROG transactions through PI and checks ANN matrix programming/address mapping.

- `controller_addr_pulse_tb`
  - Verifies `ann_core_word` packing from address/data.
  - Verifies pulse mode behavior for READ/PROG/ERASE/INF.

- `controller_prog_verify_tb`
  - Verifies full PROG->VERIFY loop with asymmetric retry behavior.
  - Checks branches: read==expected, read<expected (re-PROG), read>expected (ERASE->PROG).

- `controller_program_state_waves_tb`
  - Wave-focused scenario TB with dense state transitions.
  - Exercises multi-address PROG plus standalone READ/ERASE and injected verify paths.

- `ann_controller_unit_tb`
  - Unit-level `ann_controller` validation using behavioral buffer/op_done modeling.
  - Checks command handling and generated `ann_core_word`/pulse behavior.

- `parallel_interface_controller_integration_tb`
  - Integration of `parallel_interface` + `ann_controller` + `input_buffer`.
  - Checks command path, pulse response, and busy/idle behavior.

- `controller_buffer_integration_tb`
  - Integration of `ann_controller` + `input_buffer` without PI.
  - Checks direct command stimulus and expected pulse/word behavior.

- `controller_integration_smoke_tb`
  - Smoke integration test for PI + controller + buffer + ANN mock.
  - Sanity-checks PROG/READ/ERASE/INF sequences and return to idle.

## Input_Buffer testbenches

- `input_buffer_write_read_tb`
  - Verifies write path (`CTRL_DATA_LOAD`) and full-byte read path (`buf_data`).
  - Verifies ready behavior for both write and read operations.

- `input_buffer_bit_serial_tb`
  - Verifies bit-serial output on `D0..D7`, LSB-first by `bit_sel`.
  - Checks first group (addr 0..7) and second group (addr 8..15).

## Parallel_Interface testbenches

- `parallel_interface_extract_tb`
  - Verifies extraction/decoding of `data`, `address`, and `cmd` from host-side inputs.

- `parallel_interface_valid_tb`
  - Verifies `valid` generation rule: active when command lane is non-idle (`host_cmd != CMD_HIZ`).

- `parallel_interface_commands_tb`
  - Verifies command coverage and boundary behavior (address/data extremes).

## Wave wrapper testbenches (`*_waves_tb`)

These wrapper benches instantiate existing benches for wave viewing and do not introduce new functional checks.

### Controller wrappers
- `controller_weight_program_tb_waves_tb` -> wraps `controller_weight_program_tb`
- `controller_addr_pulse_tb_waves_tb` -> wraps `controller_addr_pulse_tb`
- `controller_prog_verify_tb_waves_tb` -> wraps `controller_prog_verify_tb`
- `controller_program_state_waves_tb_waves_tb` -> wraps `controller_program_state_waves_tb`
- `ann_controller_unit_tb_waves_tb` -> wraps `ann_controller_unit_tb`
- `parallel_interface_controller_integration_tb_waves_tb` -> wraps `parallel_interface_controller_integration_tb`
- `controller_buffer_integration_tb_waves_tb` -> wraps `controller_buffer_integration_tb`
- `controller_integration_smoke_tb_waves_tb` -> wraps `controller_integration_smoke_tb`

### Input_Buffer wrappers
- `input_buffer_write_read_tb_waves_tb` -> wraps `input_buffer_write_read_tb`
- `input_buffer_bit_serial_tb_waves_tb` -> wraps `input_buffer_bit_serial_tb`

### Parallel_Interface wrappers
- `parallel_interface_extract_tb_waves_tb` -> wraps `parallel_interface_extract_tb`
- `parallel_interface_valid_tb_waves_tb` -> wraps `parallel_interface_valid_tb`
- `parallel_interface_commands_tb_waves_tb` -> wraps `parallel_interface_commands_tb`
