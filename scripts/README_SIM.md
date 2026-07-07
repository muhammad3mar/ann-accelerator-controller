# Simulation Runner Script

The `run_sim.py` script automates all simulation and verification tasks for the ANN Accelerator Controller project.

## Quick Start

```bash
# List available modules and testbenches
python scripts/run_sim.py list

# Compile Controller verification files
python scripts/run_sim.py compile -m Controller -t verif

# Run Controller testbench
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb

# Clean all generated files
python scripts/run_sim.py clean -a
```

## Commands

### 1. Compile (`compile`)

Compile RTL or verification files.

```bash
# Compile RTL only
python scripts/run_sim.py compile -m Controller -t rtl

# Compile verification (includes RTL dependencies)
python scripts/run_sim.py compile -m Controller -t verif
```

**Options:**
- `-m, --module`: Module name (Controller, Input_Buffer, Parallel_Interface)
- `-t, --type`: Compilation type (rtl or verif)

### 2. Simulate (`sim`)

Run a simulation/testbench.

```bash
# Run simulation in batch mode (no GUI)
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb

# Run simulation with GUI waveform viewer
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb -g

# Run simulation for specific duration
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb -d 1000ns
```

**Options:**
- `-m, --module`: Module name
- `-tb, --testbench`: Testbench name (e.g., controller_prog_verify_lut_tb)
- `-g, --gui`: Open GUI waveform viewer
- `-d, --duration`: Simulation duration (e.g., 1000ns)

**Note:** The script automatically compiles verification files before running simulation.

### 3. Clean (`clean`)

Clean generated files and work directories.

```bash
# Clean everything (work + target)
python scripts/run_sim.py clean -a

# Clean only work directory
python scripts/run_sim.py clean -w

# Clean only target directory
python scripts/run_sim.py clean -t

# Clean specific module target
python scripts/run_sim.py clean -t -m Controller
```

**Options:**
- `-a, --all`: Clean all (work + target)
- `-w, --work`: Clean work directory
- `-t, --target`: Clean target directory
- `-m, --module`: Clean specific module target

### 4. List (`list`)

List all available modules and testbenches.

```bash
python scripts/run_sim.py list
```

### 5. Report (`report`)

Generate simulation report.

```bash
python scripts/run_sim.py report -m Controller -tb controller_prog_verify_lut_tb
```

**Options:**
- `-m, --module`: Module name
- `-tb, --testbench`: Testbench name

## Examples

### Complete Workflow: Run Controller Testbench

```bash
# 1. Clean previous runs
python scripts/run_sim.py clean -a

# 2. Run simulation (automatically compiles first)
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb

# 3. Check results
ls target/Controller/
# Should see: programming_inputs/weight_matrix.txt, prog/prog_verify_report.txt (after successful run), etc.
```

### Compile Only (No Simulation)

```bash
# Compile Controller RTL
python scripts/run_sim.py compile -m Controller -t rtl

# Compile Controller verification
python scripts/run_sim.py compile -m Controller -t verif
```

### Run with GUI (Waveform Viewer)

```bash
# Open ModelSim GUI with waveform viewer
python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb_waves_tb --do-file tb/Controller/do/waves/controller_prog_verify_lut_tb_waves.do
```

## Output Files

After running simulations, check the `target/` directory:

- **`target/Controller/controller_addr_pulse_verify.txt`**: Address/`ann_address` checks from `controller_addr_pulse_tb`
- **`target/Controller/prog/prog_verify_report.txt`**: PROG→VERIFY sweep report from `controller_prog_verify_lut_tb`
- **`target/Controller/programming_inputs/weight_matrix.txt`**: Input weight matrix file (used by program/verify benches)

### `weight_pulse_lut.mem` (PROG repeat count)

Entries are **R** (hex, one line per weight 0..15): on first PROG, the controller plays the macro train `M = pulse_train_total(TPROG, PULSE_NUM_PROG, PULSE_GAP)` **R** times with **`PULSE_GAP` HIZ between copies** (`pulse_total = R*M + (R-1)*PULSE_GAP`). Values below 1 are treated as 1. Re-PROG after verify mismatch uses a 1-cycle train. See `target/Controller/programming_inputs/weight_pulse_lut_table.txt`.

## Troubleshooting

### ModelSim Not Found

If you get "ModelSim not found in PATH", ensure ModelSim is in your PATH:

```bash
# Check if ModelSim is available
which vlog
which vsim

# If not, add to PATH (adjust path as needed)
export PATH=$PATH:/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem
```

### Compilation Errors

If compilation fails:
1. Check that all `.f` file lists are correct
2. Verify file paths in the file lists
3. Ensure all source files exist

### Simulation Errors

If simulation fails:
1. Check that compilation succeeded
2. Verify testbench name is correct
3. Check that `programming_inputs/weight_matrix.txt` exists under `target/Controller/`

## File Structure

```
project/
├── data/
│   ├── extract_digits_to_csv.py
│   └── README.md
├── docs/
│   └── verification/          # Testbench runbooks and catalog
├── rtl/
│   ├── Controller/
│   │   ├── controller.sv
│   │   └── controller_rtl_list.f
│   ├── Input_Buffer/
│   │   ├── input_buffer.sv
│   │   └── input_buffer_rtl_list.f
│   └── Parallel_Interface/
│       ├── parallel_interface.sv
│       └── parallel_interface_rtl_list.f
├── scripts/
│   ├── run_sim.py               # Main simulation script
│   └── README_SIM.md            # This file
├── tb/
│   ├── Controller/
│   │   ├── do/waves/            # ModelSim wave .do files
│   │   ├── file_list/
│   │   │   ├── controller_list.f
│   │   │   └── controller_verif_list.f
│   │   └── tb/
│   │       ├── regular/         # Batch testbenches
│   │       └── waves/           # GUI wave wrapper testbenches
│   ├── Input_Buffer/
│   │   ├── do/waves/
│   │   ├── file_list/
│   │   └── tb/
│   └── Parallel_Interface/
│       ├── file_list/
│       └── tb/
└── target/
    ├── Controller/
    │   ├── prog/
    │   └── programming_inputs/
    │       └── weight_matrix.txt
    ├── input_buffer/            # Input_Buffer sim logs (*_log.txt)
    └── parallel_interface/      # Parallel_Interface sim logs
```
