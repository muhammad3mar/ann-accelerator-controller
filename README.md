# ANN Accelerator Controller for a Y-Flash Memristor Array

A SystemVerilog hardware controller that programs, erases, verifies, reads, and
runs inference on an Analog Neural Network (ANN) implemented on a **Y-Flash
memristor crossbar**. The controller bridges a host (via a parallel interface)
to the analog ANN core and an on-chip input buffer, generating the precise
pulse trains required for in-memory computing.

> **Technion VLSI Laboratory Project**
> Team: **Mohammad Abu Ammar** & **Lana Bakrieh** · Supervisor: **Nir Ben-Haim**

---

## 1. Overview

The design implements a host-driven controller (`ann_controller`) that decodes
5 commands and drives a Y-Flash array through a 3-bit pulse-mode bus:

| Command | Code (`cmd[2:0]`) | Action |
|---------|-------------------|--------|
| `CMD_HIZ`   | `000` | Idle / high-Z, no pulses |
| `CMD_READ`  | `001` | Read a weight from the memristor |
| `CMD_PROG`  | `010` | Program a weight at an address (with LUT-based pulse count) |
| `CMD_ERASE` | `011` | Erase a weight at an address |
| `CMD_INF`   | `100` | Collect 8×8 input, run bit-serial inference |

Programming is **closed-loop**: after each `PROG`, the controller enters a
`VERIFY` read; if the cell is under-programmed it re-applies `PROG` pulses (up
to `MAX_PROG_RETRIES = 3`), and if over-programmed it falls back to `ERASE`
then re-programs (up to 3 erase retries).

## 2. Architecture

Three RTL blocks compose the system (see `tb/Controller/tb/parallel_interface_controller_integration_tb.sv`):

```
        host_data[31:0], host_cmd[2:0]
                  │
        ┌─────────▼──────────┐
        │ parallel_interface │  decodes one-hot host word → data/address/cmd/valid
        └─────────┬──────────┘
                  │ valid, data[7:0], address[15:0], cmd[2:0]
        ┌─────────▼──────────┐         pulses[2:0], ann_core_word[31:0]
        │   ann_controller   │ ───────────────────────────────────────►  ANN / Y-Flash core
        │  (main + sub-FSMs) │ ◄─── op_done, weight_read_data[3:0] ───────
        └─────────┬──────────┘
                  │ buf_reg_add/ctrl, buf_read_write, buf_bit_sel, buf_data_out
        ┌─────────▼──────────┐
        │   input_buffer     │  64×8 storage; bit-serial D0–D7 for inference
        └────────────────────┘
```

| Module | File | Role |
|--------|------|------|
| `ann_controller` | `rtl/Controller/controller.sv` | Top-level FSM (9 states + PROG/VERIFY/ERASE sub-FSMs), pulse generation |
| `parallel_interface` | `rtl/Parallel_Interface/parallel_interface.sv` | Host word decode, one-hot validation, `valid` generation |
| `input_buffer` | `rtl/Input_Buffer/input_buffer.sv` | 64×8-bit buffer; full-byte read for verify, bit-serial `D0–D7` for compute |
| `controller_pkg` | `rtl/Controller/controller_pkg.sv` | States, address map, pulse-train parameters & helpers |
| `parallel_interface_pkg` | `rtl/Parallel_Interface/parallel_interface_pkg.sv` | `cmd_t`, host-word pack/unpack |
| `input_buffer_pkg` | `rtl/Input_Buffer/input_buffer_pkg.sv` | Buffer sizes, `CTRL_*` encodings |

## 3. Repository Layout

```
rtl/           RTL: Controller/, Parallel_Interface/, Input_Buffer/, common/
tb/            Testbenches + file_list/ + do/waves/ per module
scripts/       run_sim.py (automation), extract_digits_to_csv.py (INF stimulus)
target/        Generated reports/logs + programming_inputs/ (LUT, weight matrix)
docs/          Block diagrams, user manual (LaTeX → PDF), verification catalog & runbooks
               (`docs/verification/`: TESTBENCH_CATALOG, REGULAR/WAVE runbooks)
report/        Final report and reference papers
```

## 4. Prerequisites

| Tool | Version used | Notes |
|------|--------------|-------|
| ModelSim / QuestaSim ASE | Intel FPGA 17.0 | `vlog` + `vsim` must be on `PATH`. Default path in `run_sim.py`: `/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem` |
| Python | 3.8+ | For `scripts/run_sim.py` and dataset extraction |
| Python packages | see `requirements.txt` | `numpy`, `scikit-learn` (only for `extract_digits_to_csv.py`) |

## 5. Clone & Setup

```bash
# 1. Clone
git clone <your-repo-url> ann-accelerator-controller
cd ann-accelerator-controller

# 2. (Optional) Python venv for the helper scripts
python -m venv .venv
source .venv/Scripts/activate      # Windows Git Bash
# source .venv/bin/activate        # Linux / macOS
pip install -r requirements.txt

# 3. Make ModelSim visible (Git Bash on Windows example)
export PATH="/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem:$PATH"
vlog -version    # sanity check
```

## 6. Step-by-Step Execution

All commands are run from the **project root** and use the automation script.

### 6.1 List everything available
```bash
python scripts/run_sim.py list
```

### 6.2 Compile (RTL or full verification set)
```bash
# RTL only
python scripts/run_sim.py compile -m Controller -t rtl

# Verification (RTL + testbenches)
python scripts/run_sim.py compile -m Controller -t verif
```

### 6.3 Run a single testbench (batch / console)
```bash
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb
```

### 6.4 Run with the ModelSim GUI + waveforms
A `--do-file` automatically opens the GUI and loads the wave layout. Use the
`*_waves_tb` wrapper TB together with its `.do` script:
```bash
python scripts/run_sim.py sim -m Controller \
  -tb controller_prog_verify_lut_tb_waves_tb \
  --do-file tb/Controller/do/waves/controller_prog_verify_lut_tb_waves.do
```

### 6.5 Run all testbenches for a module (logs to `target/`)
```bash
python scripts/run_sim.py run_all -m Controller
python scripts/run_sim.py run_all -m Input_Buffer -m Parallel_Interface
```

### 6.6 Clean generated artifacts
```bash
python scripts/run_sim.py clean -a          # work/ + target/ outputs
python scripts/run_sim.py clean -w          # work/ only
python scripts/run_sim.py clean -t -m Controller
```

### 6.7 (Optional) Generate inference stimulus
```bash
python scripts/extract_digits_to_csv.py     # writes digits_8x8_dataset.csv
```

## 7. Available Testbenches

Full descriptions, batch commands, and wave/GUI commands:
[`docs/verification/TESTBENCH_CATALOG.md`](docs/verification/TESTBENCH_CATALOG.md),
[`REGULAR_TESTBENCH_RUNBOOK.md`](docs/verification/REGULAR_TESTBENCH_RUNBOOK.md),
[`WAVE_TESTBENCH_RUNBOOK.md`](docs/verification/WAVE_TESTBENCH_RUNBOOK.md).

| Module | Testbenches |
|--------|-------------|
| **Controller** | `controller_addr_pulse_tb`, `controller_prog_verify_lut_tb`, `controller_prog_verify_lut_10w_tb`, `parallel_interface_controller_integration_tb`, `controller_host_erase_tb`, `controller_inf_buffer_flow_tb`, `controller_host_read_reorder_tb` |
| **Input_Buffer** | `input_buffer_bit_serial_tb`, `input_buffer_reset_behavior_tb`, `input_buffer_full_overwrite_tb` |
| **Parallel_Interface** | `parallel_interface_extract_tb` |

## 8. Key Parameters (defaults from `controller_pkg`)

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `ADDR_WIDTH` | 8 | Host address width default |
| `WEIGHT_WIDTH` | 16 | Weight data width default |
| `WEIGHT_ADDR_WIDTH` | 10 | `{block[2], sub_block[2], row[3], col[3]}` |
| `BUFFER_SIZE` | 64 | Input-buffer depth (8×8 image) |
| `TREAD/TPROG/TERASE` | 2 | Pulse width (cycles) per burst |
| `TINF` | 8 | Inference pulse width |
| `PULSE_GAP` | 1 | Idle cycles between bursts |
| `MAX_PROG_RETRIES` | 3 | Re-PROG attempts before ERASE fallback |
| `USE_WEIGHT_PULSE_LUT` | 1 | Enable LUT-driven PROG repeat count |

## 9. Authors & License

Developed by **Mohammad Abu Ammar** and **Lana Bakrieh** under the supervision of
**Nir Ben-Haim**, Technion VLSI Laboratory. See `LICENSE` for usage terms.
