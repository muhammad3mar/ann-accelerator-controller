# Wave Testbench Runbook

This runbook lists wave-oriented testbenches (`*_waves_tb`), what they cover, and commands to compile and launch with ModelSim waveforms.

## Controller

### `controller_weight_program_tb_waves_tb`
- **Tests:** End-to-end weight programming flow and ANN matrix programming behavior.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb_waves_tb --do-file verif/Controller/do/waves/controller_weight_program_tb_waves.do`

### `controller_addr_pulse_tb_waves_tb`
- **Tests:** Address decode and pulse mode generation for READ/PROG/ERASE/INF commands.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_addr_pulse_tb_waves_tb --do-file verif/Controller/do/waves/controller_addr_pulse_tb_waves.do`

### `controller_prog_verify_tb_waves_tb`
- **Tests:** Program-verify control flow with retry/reprogram/erase branches.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_tb_waves_tb --do-file verif/Controller/do/waves/controller_prog_verify_tb_waves.do`

### `controller_program_state_waves_tb_waves_tb`
- **Tests:** Dense waveform scenario sweep across controller states and transitions.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_program_state_waves_tb_waves_tb --do-file verif/Controller/do/waves/controller_program_state_waves_tb_waves.do`

### `ann_controller_unit_tb_waves_tb`
- **Tests:** Unit-level `ann_controller` behavior with direct stimulus and BFM-style support logic.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb ann_controller_unit_tb_waves_tb --do-file verif/Controller/do/waves/ann_controller_unit_tb_waves.do`

### `parallel_interface_controller_integration_tb_waves_tb`
- **Tests:** Integration of PI + controller + input buffer paths.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb parallel_interface_controller_integration_tb_waves_tb --do-file verif/Controller/do/waves/parallel_interface_controller_integration_tb_waves.do`

### `controller_buffer_integration_tb_waves_tb`
- **Tests:** Integration between controller and input buffer without PI wrapper.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_buffer_integration_tb_waves_tb --do-file verif/Controller/do/waves/controller_buffer_integration_tb_waves.do`

### `controller_integration_smoke_tb_waves_tb`
- **Tests:** Smoke-level integration sanity over PI/controller/buffer with basic transaction flow.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_integration_smoke_tb_waves_tb --do-file verif/Controller/do/waves/controller_integration_smoke_tb_waves.do`

## Input_Buffer

### `input_buffer_write_read_tb_waves_tb`
- **Tests:** Buffer write path, full-byte read path, and `ready` behavior.
- **Compile:** `python scripts/run_sim.py compile -m Input_Buffer -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_write_read_tb_waves_tb --do-file verif/Input_Buffer/do/waves/input_buffer_write_read_tb_waves.do`

### `input_buffer_bit_serial_tb_waves_tb`
- **Tests:** Bit-serial `D0..D7` output behavior over selected address groups.
- **Compile:** `python scripts/run_sim.py compile -m Input_Buffer -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_bit_serial_tb_waves_tb --do-file verif/Input_Buffer/do/waves/input_buffer_bit_serial_tb_waves.do`

## Parallel_Interface

### `parallel_interface_extract_tb_waves_tb`
- **Tests:** Extraction of data/address/cmd from ann-format host interface.
- **Compile:** `python scripts/run_sim.py compile -m Parallel_Interface -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Parallel_Interface -tb parallel_interface_extract_tb_waves_tb --do-file verif/Parallel_Interface/do/waves/parallel_interface_extract_tb_waves.do`

### `parallel_interface_valid_tb_waves_tb`
- **Tests:** `valid` behavior relative to command lane (`host_cmd != CMD_HIZ`).
- **Compile:** `python scripts/run_sim.py compile -m Parallel_Interface -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Parallel_Interface -tb parallel_interface_valid_tb_waves_tb --do-file verif/Parallel_Interface/do/waves/parallel_interface_valid_tb_waves.do`

### `parallel_interface_commands_tb_waves_tb`
- **Tests:** Command coverage and boundary payload/address handling.
- **Compile:** `python scripts/run_sim.py compile -m Parallel_Interface -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Parallel_Interface -tb parallel_interface_commands_tb_waves_tb --do-file verif/Parallel_Interface/do/waves/parallel_interface_commands_tb_waves.do`
