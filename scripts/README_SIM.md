# Simulation Runner Script

The `run_sim.py` script automates all simulation and verification tasks for the ANN Accelerator Controller project.

## Quick Start

```bash
# List available modules and testbenches
python scripts/run_sim.py list

# Compile Controller verification files
python scripts/run_sim.py compile -m Controller -t verif

# Run Controller testbench
python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb

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
python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb

# Run simulation with GUI waveform viewer
python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb -g

# Run simulation for specific duration
python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb -d 1000ns
```

**Options:**
- `-m, --module`: Module name
- `-tb, --testbench`: Testbench name (e.g., controller_weight_program_tb)
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
python scripts/run_sim.py report -m Controller -tb controller_weight_program_tb
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
python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb

# 3. Check results
ls target/Controller/
# Should see: ann_matrix_dump.txt, input_buffer_dump.txt
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
python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb -g
```

## Output Files

After running simulations, check the `target/` directory:

- **`target/Controller/ann_matrix_dump.txt`**: Step-by-step ANN weight matrix updates
- **`target/Controller/input_buffer_dump.txt`**: Input buffer state after weight loading
- **`target/Controller/weight_matrix.txt`**: Input weight matrix file

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
3. Check that weight_matrix.txt exists in target/Controller/

## File Structure

```
project/
├── scripts/
│   ├── run_sim.py          # Main simulation script
│   └── README_SIM.md       # This file
├── source/
│   ├── Controller/
│   │   └── controller_rtl_list.f
│   ├── Input_Buffer/
│   │   └── input_buffer_rtl_list.f
│   └── Parallel_Interface/
│       └── parallel_interface_rtl_list.f
├── verif/
│   ├── Controller/
│   │   ├── file_list/
│   │   │   ├── controller_list.f
│   │   │   └── controller_verif_list.f
│   │   └── tb/
│   │       └── controller_weight_program_tb.sv
│   └── ...
└── target/
    └── Controller/
        ├── ann_matrix_dump.txt
        ├── input_buffer_dump.txt
        └── weight_matrix.txt
```

