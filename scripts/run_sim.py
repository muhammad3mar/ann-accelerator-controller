#!/usr/bin/env python3
"""
ANN Accelerator Controller - Simulation Runner Script
======================================================
This script automates compilation, simulation, and analysis tasks.

Usage:
    python scripts/run_sim.py <command> [options]

Commands:
    compile    - Compile RTL or verification files
    sim        - Run simulation
    run_all    - Run all testbenches for module(s), save logs to target/
    clean      - Clean work directories and generated files
    list       - List available modules and testbenches
    wave       - Open waveform viewer (if GUI available)
    report     - Generate simulation reports

Examples:
    # Compile Controller RTL
    python scripts/run_sim.py compile -m Controller -t rtl

    # Run Controller testbench
    python scripts/run_sim.py sim -m Controller -tb controller_weight_program_tb

    # Clean all generated files
    python scripts/run_sim.py clean -a

    # List available modules
    python scripts/run_sim.py list
"""

import os
import sys
import subprocess
import argparse
import shutil
from pathlib import Path

# Project root directory
PROJECT_ROOT = Path(__file__).parent.parent
os.chdir(PROJECT_ROOT)

# Configuration
MODELSIM_PATH = "/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem"
VLOG_CMD = "vlog"
VSIM_CMD = "vsim"

# Module definitions
MODULES = {
    "Controller": {
        "rtl_list": "source/Controller/controller_rtl_list.f",
        "verif_list": "verif/Controller/file_list/controller_verif_list.f",
        "rtl_dir": "source/Controller",
        "verif_dir": "verif/Controller",
        "testbenches": ["controller_weight_program_tb", "controller_addr_pulse_tb", "controller_prog_verify_tb"]
    },
    "Input_Buffer": {
        "rtl_list": "source/Input_Buffer/input_buffer_rtl_list.f",
        "verif_list": "verif/Input_Buffer/file_list/input_buffer_verif_list.f",
        "rtl_dir": "source/Input_Buffer",
        "verif_dir": "verif/Input_Buffer",
        "testbenches": ["input_buffer_write_read_tb", "input_buffer_bit_serial_tb"]
    },
    "Parallel_Interface": {
        "rtl_list": "source/Parallel_Interface/parallel_interface_rtl_list.f",
        "verif_list": "verif/Parallel_Interface/file_list/parallel_interface_verif_list.f",
        "rtl_dir": "source/Parallel_Interface",
        "verif_dir": "verif/Parallel_Interface",
        "testbenches": ["parallel_interface_extract_tb", "parallel_interface_valid_tb", "parallel_interface_commands_tb"]
    }
}

# Work directory
WORK_DIR = PROJECT_ROOT / "work"
TARGET_DIR = PROJECT_ROOT / "target"


def check_modelsim():
    """Check if ModelSim is available in PATH"""
    try:
        result = subprocess.run([VLOG_CMD, "-version"], 
                              capture_output=True, 
                              timeout=5)
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def run_command(cmd, cwd=None, check=True):
    """Run a shell command and return result"""
    print(f"Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, cwd=cwd, check=check, 
                              capture_output=False, text=True)
        return result.returncode == 0
    except subprocess.CalledProcessError as e:
        print(f"Error: Command failed with return code {e.returncode}")
        return False
    except FileNotFoundError:
        print(f"Error: Command not found: {cmd[0]}")
        print(f"Please ensure {cmd[0]} is in your PATH")
        return False


def compile_rtl(module_name, file_list):
    """Compile RTL files for a module"""
    print(f"\n{'='*60}")
    print(f"Compiling RTL for {module_name}")
    print(f"{'='*60}")
    
    # Create work directory if it doesn't exist
    WORK_DIR.mkdir(exist_ok=True)
    
    # Change to module directory for relative paths
    module_dir = PROJECT_ROOT / MODULES[module_name]["rtl_dir"]
    
    cmd = [VLOG_CMD, "-sv", "-work", "work", "-f", file_list]
    success = run_command(cmd, cwd=PROJECT_ROOT)
    
    if success:
        print(f"\n[OK] Successfully compiled {module_name} RTL")
    else:
        print(f"\n[X] Failed to compile {module_name} RTL")
    
    return success


def compile_verif(module_name, file_list):
    """Compile verification files for a module"""
    print(f"\n{'='*60}")
    print(f"Compiling Verification for {module_name}")
    print(f"{'='*60}")
    
    # Create work directory if it doesn't exist
    WORK_DIR.mkdir(exist_ok=True)
    
    cmd = [VLOG_CMD, "-sv", "-work", "work", "-f", file_list]
    success = run_command(cmd, cwd=PROJECT_ROOT)
    
    if success:
        print(f"\n[OK] Successfully compiled {module_name} verification")
    else:
        print(f"\n[X] Failed to compile {module_name} verification")
    
    return success


def run_simulation(module_name, testbench_name, gui=False, duration=None, log_file=None):
    """Run a simulation. If log_file is set, capture output to that path."""
    print(f"\n{'='*60}")
    print(f"Running Simulation: {testbench_name}")
    if log_file:
        print(f"Output -> {log_file}")
    print(f"{'='*60}")
    
    work_name = f"work.{testbench_name}"
    
    # Build vsim command
    if gui:
        cmd = [VSIM_CMD, work_name]
    else:
        # Batch mode
        do_script = "run -all; quit"
        if duration:
            do_script = f"run {duration}; quit"
        cmd = [VSIM_CMD, "-c", "-do", do_script, work_name]
    
    if log_file:
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, 'w', encoding='utf-8') as f:
            try:
                result = subprocess.run(cmd, cwd=PROJECT_ROOT, check=True,
                                       stdout=f, stderr=subprocess.STDOUT)
                success = result.returncode == 0
            except subprocess.CalledProcessError as e:
                f.write(f"Command failed with return code {e.returncode}\n")
                success = False
            except FileNotFoundError:
                f.write(f"Error: {VSIM_CMD} not found in PATH\n")
                success = False
    else:
        success = run_command(cmd, cwd=PROJECT_ROOT)
    
    if success:
        print(f"\n[OK] Simulation completed: {testbench_name}")
    else:
        print(f"\n[X] Simulation failed: {testbench_name}")
    
    return success


def clean_work():
    """Clean work directory"""
    print(f"\n{'='*60}")
    print("Cleaning work directory")
    print(f"{'='*60}")
    
    if WORK_DIR.exists():
        try:
            shutil.rmtree(WORK_DIR)
            print("[OK] Removed work/ directory")
        except Exception as e:
            print(f"[X] Error removing work/: {e}")
            return False
    
    # Recreate empty work directory
    WORK_DIR.mkdir(exist_ok=True)
    return True


def clean_target(module_name=None):
    """Clean target directory (simulation outputs)"""
    print(f"\n{'='*60}")
    print("Cleaning target directory")
    print(f"{'='*60}")
    
    if module_name:
        target_module_dir = TARGET_DIR / module_name
        if target_module_dir.exists():
            try:
                shutil.rmtree(target_module_dir)
                print(f"[OK] Removed target/{module_name}/")
            except Exception as e:
                print(f"[X] Error removing target/{module_name}/: {e}")
                return False
    else:
        # Clean all target files except weight_matrix.txt
        for item in TARGET_DIR.iterdir():
            if item.is_dir():
                for subitem in item.iterdir():
                    if subitem.name != "weight_matrix.txt":
                        try:
                            if subitem.is_file():
                                subitem.unlink()
                                print(f"[OK] Removed {subitem}")
                        except Exception as e:
                            print(f"[X] Error removing {subitem}: {e}")
    
    return True


def list_modules():
    """List available modules and testbenches"""
    print(f"\n{'='*60}")
    print("Available Modules and Testbenches")
    print(f"{'='*60}\n")
    
    for module_name, config in MODULES.items():
        print(f"Module: {module_name}")
        print(f"  RTL List:     {config['rtl_list']}")
        print(f"  Verif List:   {config['verif_list']}")
        print(f"  Testbenches:  {', '.join(config['testbenches']) if config['testbenches'] else 'None'}")
        print()


def generate_report(module_name, testbench_name):
    """Generate simulation report"""
    print(f"\n{'='*60}")
    print(f"Generating Report for {testbench_name}")
    print(f"{'='*60}")
    
    report_file = TARGET_DIR / module_name / f"{testbench_name}_report.txt"
    report_file.parent.mkdir(parents=True, exist_ok=True)
    
    # Collect output files
    dump_files = []
    target_module_dir = TARGET_DIR / module_name
    if target_module_dir.exists():
        for file in target_module_dir.glob("*_dump.txt"):
            dump_files.append(file)
    
    with open(report_file, 'w') as f:
        f.write(f"Simulation Report: {testbench_name}\n")
        f.write("=" * 60 + "\n\n")
        f.write(f"Module: {module_name}\n")
        f.write(f"Testbench: {testbench_name}\n")
        f.write(f"Generated Files:\n")
        for dump_file in dump_files:
            f.write(f"  - {dump_file.name}\n")
    
    print(f"[OK] Report generated: {report_file}")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="ANN Accelerator Controller - Simulation Runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Compile command
    compile_parser = subparsers.add_parser('compile', help='Compile RTL or verification files')
    compile_parser.add_argument('-m', '--module', 
                               choices=list(MODULES.keys()),
                               required=True,
                               help='Module name')
    compile_parser.add_argument('-t', '--type',
                               choices=['rtl', 'verif'],
                               default='verif',
                               help='Compilation type (default: verif)')
    
    # Simulate command
    sim_parser = subparsers.add_parser('sim', help='Run simulation')
    sim_parser.add_argument('-m', '--module',
                           choices=list(MODULES.keys()),
                           required=True,
                           help='Module name')
    sim_parser.add_argument('-tb', '--testbench',
                           required=True,
                           help='Testbench name (e.g., controller_weight_program_tb)')
    sim_parser.add_argument('-g', '--gui',
                           action='store_true',
                           help='Open GUI waveform viewer')
    sim_parser.add_argument('-d', '--duration',
                           help='Simulation duration (e.g., 1000ns)')
    
    # Clean command
    clean_parser = subparsers.add_parser('clean', help='Clean generated files')
    clean_parser.add_argument('-a', '--all',
                            action='store_true',
                            help='Clean all (work + target)')
    clean_parser.add_argument('-w', '--work',
                            action='store_true',
                            help='Clean work directory')
    clean_parser.add_argument('-t', '--target',
                            action='store_true',
                            help='Clean target directory')
    clean_parser.add_argument('-m', '--module',
                            choices=list(MODULES.keys()),
                            help='Clean specific module target')
    
    # List command
    list_parser = subparsers.add_parser('list', help='List available modules and testbenches')
    
    # Run-all command (all testbenches for module, output to target/)
    run_all_parser = subparsers.add_parser('run_all', help='Run all testbenches, save logs to target/')
    run_all_parser.add_argument('-m', '--module',
                               choices=list(MODULES.keys()),
                               action='append',
                               help='Module(s) to run (repeat for multiple)')
    
    # Report command
    report_parser = subparsers.add_parser('report', help='Generate simulation report')
    report_parser.add_argument('-m', '--module',
                              choices=list(MODULES.keys()),
                              required=True,
                              help='Module name')
    report_parser.add_argument('-tb', '--testbench',
                              required=True,
                              help='Testbench name')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    # Check ModelSim availability
    if args.command in ['compile', 'sim']:
        if not check_modelsim():
            print("Warning: ModelSim not found in PATH")
            print("Make sure ModelSim is installed and in your PATH")
            print(f"Expected path: {MODELSIM_PATH}")
    
    # Execute commands
    if args.command == 'compile':
        module_config = MODULES[args.module]
        if args.type == 'rtl':
            file_list = module_config['rtl_list']
            success = compile_rtl(args.module, file_list)
        else:
            file_list = module_config['verif_list']
            success = compile_verif(args.module, file_list)
        return 0 if success else 1
    
    elif args.command == 'sim':
        # First compile if needed
        module_config = MODULES[args.module]
        print("Compiling verification files first...")
        compile_verif(args.module, module_config['verif_list'])
        
        # Then run simulation
        success = run_simulation(args.module, args.testbench, 
                               gui=args.gui, duration=args.duration)
        return 0 if success else 1
    
    elif args.command == 'run_all':
        modules = args.module if args.module else ['Input_Buffer', 'Parallel_Interface']
        all_success = True
        for module_name in modules:
            if module_name not in MODULES:
                print(f"Unknown module: {module_name}")
                continue
            cfg = MODULES[module_name]
            print(f"\n>>> Compiling {module_name} verification...")
            compile_verif(module_name, cfg['verif_list'])
            for tb in cfg['testbenches']:
                log_path = TARGET_DIR / module_name / f"{tb}_log.txt"
                ok = run_simulation(module_name, tb, log_file=str(log_path))
                all_success = all_success and ok
        print(f"\n{'='*60}")
        print(f"Logs saved under target/<module>/<testbench>_log.txt")
        print(f"{'='*60}")
        return 0 if all_success else 1
    
    elif args.command == 'clean':
        success = True
        if args.all:
            success &= clean_work()
            success &= clean_target()
        else:
            if args.work:
                success &= clean_work()
            if args.target:
                success &= clean_target(args.module if args.module else None)
        return 0 if success else 1
    
    elif args.command == 'list':
        list_modules()
        return 0
    
    elif args.command == 'report':
        success = generate_report(args.module, args.testbench)
        return 0 if success else 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

