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
    python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb

    # ModelSim GUI + waves (--do-file implies GUI; path is relative to project root)
    python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb_waves_tb --do-file verif/Controller/do/waves/controller_prog_verify_lut_tb_waves.do

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
        "testbenches": ["controller_addr_pulse_tb", "controller_prog_verify_lut_tb", "controller_prog_verify_lut_10w_tb", "parallel_interface_controller_integration_tb", "controller_host_erase_tb", "controller_inf_buffer_flow_tb", "controller_host_read_reorder_tb"]
    },
    "Input_Buffer": {
        "rtl_list": "source/Input_Buffer/input_buffer_rtl_list.f",
        "verif_list": "verif/Input_Buffer/file_list/input_buffer_verif_list.f",
        "rtl_dir": "source/Input_Buffer",
        "verif_dir": "verif/Input_Buffer",
        "testbenches": ["input_buffer_bit_serial_tb", "input_buffer_reset_behavior_tb", "input_buffer_full_overwrite_tb"]
    },
    "Parallel_Interface": {
        "rtl_list": "source/Parallel_Interface/parallel_interface_rtl_list.f",
        "verif_list": "verif/Parallel_Interface/file_list/parallel_interface_verif_list.f",
        "rtl_dir": "source/Parallel_Interface",
        "verif_dir": "verif/Parallel_Interface",
        "testbenches": ["parallel_interface_extract_tb"]
    }
}

# Work directory
WORK_DIR = PROJECT_ROOT / "work"
TARGET_DIR = PROJECT_ROOT / "target"


def target_subdir_for_module(module_name: str) -> str:
    """Folder under target/ for logs and reports."""
    if module_name == "Input_Buffer":
        return "input_buffer"
    if module_name == "Parallel_Interface":
        return "parallel_interface"
    return module_name


def clean_sim_artifacts(verbose: bool = False) -> int:
    """Remove common ModelSim temporary artifacts from project root."""
    patterns = ["wlf*", "*.wlf", "transcript"]
    removed = 0
    for pat in patterns:
        for p in PROJECT_ROOT.glob(pat):
            if p.is_file():
                try:
                    p.unlink()
                    removed += 1
                    if verbose:
                        print(f"[OK] Removed artifact: {p.name}")
                except Exception as e:
                    if verbose:
                        print(f"[X] Could not remove artifact {p.name}: {e}")
    return removed


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


def normalize_testbench_name(name: str) -> str:
    """Strip whitespace and a trailing '~' (common typo when pasting names)."""
    n = name.strip()
    if n.endswith("~"):
        n = n[:-1].strip()
    return n


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


def relocate_input_buffer_tb_report_to_end(log_path: Path) -> None:
    """After ModelSim, move the // TB REPORT block to the physical end of the log (after vsim trailer)."""
    try:
        text = log_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    marker = "# //==============================================================================\n# // TB REPORT"
    if marker not in text:
        return
    i = text.index(marker)
    if i >= 4 and text[i - 4 : i] == "# \n\n":
        i -= 4
    finish = text.find("# ** Note: $finish", i)
    if finish < 0:
        return
    block = text[i:finish]
    rest = text[:i] + text[finish:]
    log_path.write_text(rest + block, encoding="utf-8")


def run_simulation(module_name, testbench_name, gui=False, duration=None, log_file=None, do_file=None):
    """Run a simulation. If log_file is set, capture output to that path.
    If do_file is set (path to a .tcl/.do script), vsim is launched with -do after resolving
    the path; use with gui=True so the Wave window opens (recommended)."""
    # Auto-clean transient simulator artifacts before each simulation run.
    clean_sim_artifacts(verbose=False)

    print(f"\n{'='*60}")
    print(f"Running Simulation: {testbench_name}")
    if log_file:
        print(f"Output -> {log_file}")
    if do_file:
        print(f"ModelSim -do: {do_file}")
    print(f"{'='*60}")
    
    work_name = f"work.{testbench_name}"
    
    # Build vsim command
    if gui:
        cmd = [VSIM_CMD]
        if do_file:
            do_norm = str(do_file).replace("\\", "/")
            cmd.extend(["-do", do_norm])
        cmd.append(work_name)
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
    
    if success and log_file:
        lp = Path(log_file)
        if "input_buffer" in str(lp).replace("\\", "/").lower():
            relocate_input_buffer_tb_report_to_end(lp)

    # Auto-clean transient simulator artifacts after run as well.
    clean_sim_artifacts(verbose=False)
    
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
        target_module_dir = TARGET_DIR / target_subdir_for_module(module_name)
        if target_module_dir.exists():
            try:
                shutil.rmtree(target_module_dir)
                print(f"[OK] Removed target/{module_name}/")
            except Exception as e:
                print(f"[X] Error removing target/{module_name}/: {e}")
                return False
    else:
        # Remove loose files under target/<module>/ (not recursive). Keeps subdirs
        # (e.g. programming_inputs/, prog/) intact; legacy top-level weight_matrix.txt skip retained.
        for item in TARGET_DIR.iterdir():
            if item.is_dir():
                for subitem in item.iterdir():
                    if not subitem.is_file():
                        continue
                    if subitem.name != "weight_matrix.txt":
                        try:
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
    
    report_file = TARGET_DIR / target_subdir_for_module(module_name) / f"{testbench_name}_report.txt"
    report_file.parent.mkdir(parents=True, exist_ok=True)
    
    # Collect output files
    dump_files = []
    target_module_dir = TARGET_DIR / target_subdir_for_module(module_name)
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
                           help='Testbench name (e.g., controller_prog_verify_lut_tb)')
    sim_parser.add_argument('-g', '--gui',
                           action='store_true',
                           help='Open ModelSim GUI (vsim without -c)')
    sim_parser.add_argument('--do-file',
                           default=None,
                           metavar='PATH',
                           help='Optional ModelSim DO/TCL script (e.g. verif/Controller/do/waves/controller_prog_verify_lut_tb_waves.do). '
                                'Implies GUI. Path is relative to project root.')
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
    
    # Keep root clean from simulator temp artifacts across all invocations.
    clean_sim_artifacts(verbose=False)

    # Execute commands
    if args.command == 'compile':
        module_config = MODULES[args.module]
        if args.type == 'rtl':
            file_list = module_config['rtl_list']
            success = compile_rtl(args.module, file_list)
        else:
            file_list = module_config['verif_list']
            success = compile_verif(args.module, file_list)
        clean_sim_artifacts(verbose=False)
        return 0 if success else 1
    
    elif args.command == 'sim':
        # First compile if needed
        module_config = MODULES[args.module]
        tb_name = normalize_testbench_name(args.testbench)
        if tb_name != args.testbench.strip():
            print(f"Note: normalized testbench name to '{tb_name}' (removed stray characters).\n")

        print("Compiling verification files first...")
        compile_verif(args.module, module_config['verif_list'])

        do_path = None
        if getattr(args, 'do_file', None):
            do_path = Path(args.do_file)
            if not do_path.is_absolute():
                do_path = PROJECT_ROOT / do_path
            if not do_path.is_file():
                print(f"Error: --do-file not found: {do_path}")
                return 1
            do_path = do_path.resolve()

        use_gui = args.gui or do_path is not None
        if do_path and not args.gui:
            print("Note: --do-file opens ModelSim GUI (wave window).")

        sim_log = None
        if args.module in ("Input_Buffer", "Parallel_Interface"):
            sim_log = str(
                TARGET_DIR / target_subdir_for_module(args.module) / f"{tb_name}_log.txt"
            )

        # Then run simulation
        success = run_simulation(
            args.module,
            tb_name,
            gui=use_gui,
            duration=args.duration,
            log_file=sim_log,
            do_file=str(do_path) if do_path else None,
        )
        clean_sim_artifacts(verbose=False)
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
                log_path = TARGET_DIR / target_subdir_for_module(module_name) / f"{tb}_log.txt"
                ok = run_simulation(module_name, tb, log_file=str(log_path))
                all_success = all_success and ok
        print(f"\n{'='*60}")
        print("Logs saved under target/<module_dir>/<testbench>_log.txt (Input_Buffer -> input_buffer/)")
        print(f"{'='*60}")
        clean_sim_artifacts(verbose=False)
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
        clean_sim_artifacts(verbose=False)
        return 0 if success else 1
    
    elif args.command == 'list':
        list_modules()
        return 0
    
    elif args.command == 'report':
        success = generate_report(args.module, normalize_testbench_name(args.testbench))
        clean_sim_artifacts(verbose=False)
        return 0 if success else 1
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

