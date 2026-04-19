# Wave Testbench Runbook

This runbook lists wave-oriented testbenches (`*_waves_tb`), what they cover, and commands to compile and launch with ModelSim waveforms.

For **batch** (non-wave) top-level testbenches, see [Regular Testbench Runbook](../regular_testbench_runbook/REGULAR_TESTBENCH_RUNBOOK.md).

## Controller

### `controller_prog_verify_lut_tb_waves_tb`
- **Tests:** Program-verify control flow with retry/reprogram/erase branches (LUT-based PROG duration).
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb_waves_tb --do-file verif/Controller/do/waves/controller_prog_verify_lut_tb_waves.do`

### `parallel_interface_controller_integration_tb_waves_tb`
- **Tests:** Integration of PI + controller + input buffer paths.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb parallel_interface_controller_integration_tb_waves_tb --do-file verif/Controller/do/waves/parallel_interface_controller_integration_tb_waves.do`

### `controller_host_erase_tb_waves_tb`
- **Tests:** Host-directed erase on one memristor cell; `pulses` and erase sub-FSM vs mock weight matrix.
- **Compile:** `python scripts/run_sim.py compile -m Controller -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Controller -tb controller_host_erase_tb_waves_tb --do-file verif/Controller/do/waves/controller_host_erase_tb_waves.do`

## Input_Buffer

### `input_buffer_bit_serial_tb_waves_tb`
- **Tests:** Bit-serial `D0..D7` output behavior over selected address groups.
- **Waves:** TB `tb_captured_din_0..7` latch each `data_in` after each write; first load fills buffer `0..7`, second load overwrites the same eight traces with `8..15`. Also includes `tb_pi_load_trigger` (load enable) and `tb_load_pixel_count` (0..8). DUT waves: clock/reset and bit-serial (`bit_sel`, `D0..D7`) only.
- **Compile:** `python scripts/run_sim.py compile -m Input_Buffer -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_bit_serial_tb_waves_tb --do-file verif/Input_Buffer/do/waves/input_buffer_bit_serial_tb_waves.do`

### `input_buffer_reset_behavior_tb_waves_tb`
- **Tests:** Reset-focused behavior while loading data and while in bit-serial compute (`D0..D7`), including post-reset buffer-clear checks.
- **Waves:** DUT clock/reset, control/data path (`reg_ctrl`, `buf_read_write`, `buf_reg_add`, `bit_sel`, `data_in`, `buf_data`, `ready`), bit-serial outputs (`D0..D7`), plus TB helpers (`tb_pi_load_trigger`, `tb_load_pixel_count`).
- **Compile:** `python scripts/run_sim.py compile -m Input_Buffer -t verif`
- **Run (wave):** `python scripts/run_sim.py sim -m Input_Buffer -tb input_buffer_reset_behavior_tb_waves_tb --do-file verif/Input_Buffer/do/waves/input_buffer_reset_behavior_tb_waves.do`
