# Simulation Runner Script Guide

## Quick Start

The `run_sim.py` script automates all simulation tasks for the ANN Accelerator Controller project.

## Basic Usage

```bash
python run_sim.py <module> <action> [options]
```

## Available Modules

- `controller` - Controller module (has testbench)
- `input_buffer` - Input Buffer module
- `parallel_interface` - Parallel Interface module
- `all` - All modules (for clean/list only)

## Available Actions

### 1. List Modules
```bash
python run_sim.py all list
```
Shows all available modules and their testbench status.

### 2. Compile RTL
```bash
# Compile Controller RTL only
python run_sim.py controller compile

# Compile Input Buffer RTL
python run_sim.py input_buffer compile

# Compile Parallel Interface RTL
python run_sim.py parallel_interface compile
```

### 3. Run Simulation
```bash
# Run Controller testbench (command-line mode)
python run_sim.py controller sim

# Run Controller testbench with GUI
python run_sim.py controller sim --gui

# Run simulation for specific duration
python run_sim.py controller sim --duration 1000ns
```

### 4. View Waveforms
```bash
# Open waveforms from previous simulation
python run_sim.py controller wave
```

### 5. Clean
```bash
# Clean work directory only
python run_sim.py controller clean

# Clean all generated files (work + dump files)
python run_sim.py all clean
```

## Examples

### Complete Workflow: Controller Testbench

```bash
# 1. List available modules
python run_sim.py all list

# 2. Clean previous runs (optional)
python run_sim.py all clean

# 3. Run simulation
python run_sim.py controller sim

# 4. View results
# Check target/Controller/ann_matrix_dump.txt
# Check target/Controller/input_buffer_dump.txt

# 5. View waveforms (if GUI was used)
python run_sim.py controller wave
```

### Quick Test Run

```bash
# Compile and run in one command
python run_sim.py controller sim
```

### GUI Mode for Debugging

```bash
# Run with GUI to see waveforms interactively
python run_sim.py controller sim --gui
```

## Output Files

After running simulations, check these files:

- **`target/Controller/ann_matrix_dump.txt`** - Step-by-step ANN weight matrix updates
- **`target/Controller/input_buffer_dump.txt`** - Input buffer state (64 rows x 8 bits)
- **`target/Controller/weight_matrix.txt`** - Input weight matrix (edit this to change weights)

## Troubleshooting

### ModelSim Not Found
```
[ERROR] ModelSim not found in PATH
```
**Solution**: Ensure ModelSim is installed and added to your PATH, or source the ModelSim setup script.

### Testbench Not Available
```
[WARN] No testbench available for module: input_buffer
```
**Solution**: Only `controller` module has a testbench currently. Other modules need testbenches to be created.

### Compilation Errors
Check the error messages. Common issues:
- Missing file dependencies
- Syntax errors in RTL files
- Incorrect file paths in `.f` files

## Advanced Usage

### Custom Simulation Duration
```bash
python run_sim.py controller sim --duration 5000ns
```

### Batch Operations
```bash
# Compile all modules
python run_sim.py controller compile
python run_sim.py input_buffer compile
python run_sim.py parallel_interface compile
```

## File Structure

The script uses these file lists:
- **RTL Lists**: `source/<module>/<module>_rtl_list.f`
- **Verification Lists**: `verif/<module>/file_list/<module>_verif_list.f`

All paths are relative to the project root.

