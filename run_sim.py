#!/usr/bin/env python3
"""
ANN Accelerator Controller - Simulation Runner Script
======================================================
This script automates compilation, simulation, and waveform viewing for the project.

Usage:
    python run_sim.py <module> <action> [options]

Examples:
    # Compile Controller RTL
    python run_sim.py controller compile

    # Run Controller testbench
    python run_sim.py controller sim

    # Run Controller testbench with GUI
    python run_sim.py controller sim --gui

    # View waveforms from previous run
    python run_sim.py controller wave

    # Clean work directory
    python run_sim.py all clean
"""

import os
import sys
import subprocess
import argparse
import shutil
from pathlib import Path

# Project root directory
PROJECT_ROOT = Path(__file__).parent.absolute()

# Module configurations
MODULES = {
    'controller': {
        'rtl_list': 'source/Controller/controller_rtl_list.f',
        'verif_list': 'verif/Controller/file_list/controller_verif_list.f',
        'tb_name': 'controller_weight_program_tb',
        'rtl_dir': 'source/Controller',
    },
    'input_buffer': {
        'rtl_list': 'source/Input_Buffer/input_buffer_rtl_list.f',
        'verif_list': 'verif/Input_Buffer/file_list/input_buffer_verif_list.f',
        'tb_name': None,  # No testbench yet
        'rtl_dir': 'source/Input_Buffer',
    },
    'parallel_interface': {
        'rtl_list': 'source/Parallel_Interface/parallel_interface_rtl_list.f',
        'verif_list': 'verif/Parallel_Interface/file_list/parallel_interface_verif_list.f',
        'tb_name': None,  # No testbench yet
        'rtl_dir': 'source/Parallel_Interface',
    },
}

# ModelSim commands
VSIM_CMD = 'vsim'
VLOG_CMD = 'vlog'
VLIB_CMD = 'vlib'


def run_command(cmd, cwd=None, check=True):
    """Run a shell command and return the result."""
    print(f"\n{'='*80}")
    print(f"Running: {' '.join(cmd)}")
    print(f"{'='*80}\n")
    
    result = subprocess.run(
        cmd,
        cwd=cwd or PROJECT_ROOT,
        capture_output=False,
        text=True
    )
    
    if check and result.returncode != 0:
        print(f"\n[ERROR] Command failed with exit code {result.returncode}")
        sys.exit(result.returncode)
    
    return result


def check_modelsim():
    """Check if ModelSim is available."""
    try:
        result = subprocess.run(
            [VSIM_CMD, '-version'],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print(f"[OK] ModelSim found: {result.stdout.split()[0]}")
            return True
    except FileNotFoundError:
        print("[ERROR] ModelSim not found in PATH")
        print("   Please ensure ModelSim is installed and added to PATH")
        return False
    return False


def create_work_library():
    """Create ModelSim work library if it doesn't exist."""
    work_dir = PROJECT_ROOT / 'work'
    if not work_dir.exists():
        print("Creating ModelSim work library...")
        run_command([VLIB_CMD, 'work'])
    else:
        print("[OK] Work library already exists")


def compile_rtl(module):
    """Compile RTL files for a module."""
    if module not in MODULES:
        print(f"❌ Unknown module: {module}")
        return False
    
    config = MODULES[module]
    rtl_list = PROJECT_ROOT / config['rtl_list']
    
    if not rtl_list.exists():
        print(f"[ERROR] RTL file list not found: {rtl_list}")
        return False
    
    print(f"\n[COMPILE] Compiling RTL for module: {module}")
    create_work_library()
    
    cmd = [
        VLOG_CMD,
        '-sv',
        '-work', 'work',
        '-f', str(rtl_list.relative_to(PROJECT_ROOT))
    ]
    
    run_command(cmd)
    print(f"[OK] RTL compilation complete for {module}")
    return True


def compile_verif(module):
    """Compile verification files (RTL + testbench) for a module."""
    if module not in MODULES:
        print(f"[ERROR] Unknown module: {module}")
        return False
    
    config = MODULES[module]
    verif_list = PROJECT_ROOT / config['verif_list']
    
    if not verif_list.exists():
        print(f"[ERROR] Verification file list not found: {verif_list}")
        return False
    
    if config['tb_name'] is None:
        print(f"[WARN] No testbench available for module: {module}")
        return False
    
    print(f"\n[COMPILE] Compiling verification files for module: {module}")
    create_work_library()
    
    cmd = [
        VLOG_CMD,
        '-sv',
        '-work', 'work',
        '-f', str(verif_list.relative_to(PROJECT_ROOT))
    ]
    
    run_command(cmd)
    print(f"[OK] Verification compilation complete for {module}")
    return True


def run_simulation(module, gui=False, duration=None):
    """Run simulation for a module."""
    if module not in MODULES:
        print(f"[ERROR] Unknown module: {module}")
        return False
    
    config = MODULES[module]
    tb_name = config['tb_name']
    
    if tb_name is None:
        print(f"[ERROR] No testbench available for module: {module}")
        return False
    
    print(f"\n[SIM] Running simulation for module: {module}")
    print(f"   Testbench: {tb_name}")
    
    # Build vsim command
    cmd = [VSIM_CMD]
    
    if not gui:
        cmd.append('-c')  # Command-line mode
    
    cmd.extend(['-do'])
    
    # Build do file commands
    do_commands = []
    do_commands.append(f"run -all")
    
    if duration:
        do_commands.append(f"run {duration}")
    else:
        do_commands.append("run -all")
    
    if not gui:
        do_commands.append("quit")
    
    do_string = "; ".join(do_commands)
    cmd.extend([do_string, f"work.{tb_name}"])
    
    run_command(cmd)
    print(f"[OK] Simulation complete for {module}")
    return True


def view_waveforms(module):
    """Open waveforms from previous simulation."""
    if module not in MODULES:
        print(f"[ERROR] Unknown module: {module}")
        return False
    
    config = MODULES[module]
    tb_name = config['tb_name']
    
    if tb_name is None:
        print(f"[ERROR] No testbench available for module: {module}")
        return False
    
    print(f"\n[WAVE] Opening waveforms for module: {module}")
    
    cmd = [
        VSIM_CMD,
        '-view', f'work.{tb_name}.wlf',
        '-do', 'wave.do'
    ]
    
    # Check if waveform file exists
    wlf_file = PROJECT_ROOT / f'work/{tb_name}.wlf'
    if not wlf_file.exists():
        print(f"[WARN] Waveform file not found: {wlf_file}")
        print("   Run simulation first to generate waveforms")
        return False
    
    run_command(cmd, check=False)
    return True


def clean_work():
    """Clean ModelSim work directory."""
    work_dir = PROJECT_ROOT / 'work'
    if work_dir.exists():
        print(f"\n[CLEAN] Cleaning work directory...")
        shutil.rmtree(work_dir)
        print("[OK] Work directory cleaned")
    else:
        print("[OK] Work directory already clean")


def clean_all():
    """Clean all generated files."""
    print("\n[CLEAN] Cleaning all generated files...")
    
    # Clean work directory
    clean_work()
    
    # Clean target directories (keep structure, remove generated files)
    target_dirs = [
        'target/Controller',
        'target/Input_Buffer',
        'target/Parallel_Interface'
    ]
    
    for target_dir in target_dirs:
        target_path = PROJECT_ROOT / target_dir
        if target_path.exists():
            for file in target_path.glob('*.txt'):
                if file.name != 'weight_matrix.txt':  # Keep weight matrix
                    file.unlink()
                    print(f"   Removed: {file}")
    
    print("[OK] Clean complete")


def list_modules():
    """List all available modules."""
    print("\nAvailable modules:")
    for module, config in MODULES.items():
        tb_status = "[OK]" if config['tb_name'] else "[--]"
        print(f"   {module:20s}  Testbench: {tb_status} {config['tb_name'] or 'N/A'}")


def main():
    parser = argparse.ArgumentParser(
        description='ANN Accelerator Controller - Simulation Runner',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        'module',
        choices=['controller', 'input_buffer', 'parallel_interface', 'all'],
        help='Module to operate on'
    )
    
    parser.add_argument(
        'action',
        choices=['compile', 'sim', 'wave', 'clean', 'list'],
        help='Action to perform'
    )
    
    parser.add_argument(
        '--gui',
        action='store_true',
        help='Run simulation with GUI (for sim action)'
    )
    
    parser.add_argument(
        '--duration',
        type=str,
        help='Simulation duration (e.g., "1000ns" or "1000")'
    )
    
    args = parser.parse_args()
    
    # Check ModelSim availability
    if args.action != 'list' and args.action != 'clean':
        if not check_modelsim():
            sys.exit(1)
    
    # Handle special actions
    if args.action == 'list':
        list_modules()
        return
    
    if args.action == 'clean':
        if args.module == 'all':
            clean_all()
        else:
            clean_work()
        return
    
    # Handle module-specific actions
    if args.module == 'all':
        print("[WARN] 'all' module only supports 'clean' and 'list' actions")
        sys.exit(1)
    
    # Execute action
    success = False
    
    if args.action == 'compile':
        success = compile_rtl(args.module)
    
    elif args.action == 'sim':
        # Compile first, then simulate
        if compile_verif(args.module):
            success = run_simulation(args.module, gui=args.gui, duration=args.duration)
    
    elif args.action == 'wave':
        success = view_waveforms(args.module)
    
    if success:
        print(f"\n[OK] Operation '{args.action}' completed successfully for '{args.module}'")
    else:
        print(f"\n[ERROR] Operation '{args.action}' failed for '{args.module}'")
        sys.exit(1)


if __name__ == '__main__':
    main()

