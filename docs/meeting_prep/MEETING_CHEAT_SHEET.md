# Meeting cheat sheet — ANN controller

One-page style reference for a walkthrough with your supervisor. Deep dives: [CONTROLLER_CASE_STUDIES.md](CONTROLLER_CASE_STUDIES.md), [CONTROLLER_OPERATIONS_DIAGRAM.md](CONTROLLER_OPERATIONS_DIAGRAM.md), [CONTROLLER_USER_GUIDE.md](CONTROLLER_USER_GUIDE.md).

## Main FSM states (`controller_pkg::controller_state_t`)

| State | Value | Role |
|-------|-------|------|
| `S_IDLE` | 0 | Wait for `valid` + command |
| `S_RESET` | 1 | Legacy reset (not dispatched from current idle decode) |
| `S_PROGRAM` | 2 | Program + buffer/program sub-FSM |
| `S_VERIFY` | 3 | Read-back vs buffer |
| `S_ERASE` | 4 | Erase sub-FSM |
| `S_READ` | 5 | Host read |
| `S_COLLECT_DATA` | 6 | INF: stream pixels into buffer |
| `S_COMPUTE` | 7 | INF: bit-serial compute window |
| `S_RESULT` | 8 | INF: result phase → idle |

## Host commands (`parallel_interface_pkg`)

| `host_cmd` | Name |
|------------|------|
| `3'b000` | `CMD_HIZ` — idle, `valid=0` |
| `3'b001` | `CMD_READ` |
| `3'b010` | `CMD_PROG` |
| `3'b011` | `CMD_ERASE` |
| `3'b100` | `CMD_INF` |

**Host bus:** `host_data` = `ann_core_word` layout; PI exposes `data`, decoded `address`, `cmd`, and `valid`.

## Pulse modes (3-bit `pulses`)

| Mode | Bits |
|------|------|
| HIZ | `000` |
| READ | `001` |
| PROG | `010` |
| ERASE | `011` |
| INF | `100` |

## Wave-oriented testbenches (Controller)

From [WAVE_TESTBENCH_RUNBOOK.md](../wave_testbench_runbook/WAVE_TESTBENCH_RUNBOOK.md):

- `controller_prog_verify_lut_tb_waves_tb` — verify / retry / erase (LUT PROG length)
- `controller_host_erase_tb_waves_tb` — host `CMD_ERASE` + erase sub-FSM
- `parallel_interface_controller_integration_tb_waves_tb` — PI + controller + buffer

Example:  
`python scripts/run_sim.py sim -m Controller -tb controller_prog_verify_lut_tb_waves_tb --do-file verif/Controller/do/waves/controller_prog_verify_lut_tb_waves.do`

## Desired output excerpts (after latest sims)

### A. Address + pulse check (end of run summary)

From [`target/Controller/controller_addr_pulse_verify.txt`](../../target/Controller/controller_addr_pulse_verify.txt):

```text
=== Test 30: ERASE  (PE=0,SA=3,col=7,row=7) at addr 0x00ff ===
  PASS: ann_core_word 0x00188080 (0b00000000-0001-1000-10000000-10000000)

=== Verification Complete (30 tests) ===
```

### B. Program–verify–rePROG–ERASE narrative

From [`target/Controller/prog/prog_verify_report.txt`](../../target/Controller/prog/prog_verify_report.txt):

```text
[318000] Phase: PROG  ann_core_word=0x0a110801  programmed_weight=10
[350000] Phase: VERIFY  ann_core_word=0x0a110801  expected_weight=10  read_weight=10
[478000] Phase: PROG  ann_core_word=0x0a112001  programmed_weight=10
[510000] Phase: VERIFY  ann_core_word=0x0a112001  expected_weight=10  read_weight=9
//------------------------------------------------------------------------------
// re-PROG sequence START [526000]  (after phase: CHECK_DONE)
//------------------------------------------------------------------------------
[526000] Phase: REPROG  ann_core_word=0x0a112001  programmed_weight=10
[554000] Phase: VERIFY  ann_core_word=0x0a112001  expected_weight=10  read_weight=10
//------------------------------------------------------------------------------
// re-PROG sequence END [562000]  (DUT idle)
//------------------------------------------------------------------------------
...
//------------------------------------------------------------------------------
// ERASE sequence START [986000]
//------------------------------------------------------------------------------
[986000] Phase: ERASE  ann_core_word=0x05120401  programmed_weight=5
```

### C. PI + controller + buffer integration

From [`target/Controller/tb_pi_controller_integration.txt`](../../target/Controller/tb_pi_controller_integration.txt):

```text
PASS 01_READ pulses=001 word=00281080
PASS 02_PROG pulses=001 word=0c110101
...
// Summary: PASS=10 FAIL=0
```

### D. Host-directed erase report

From [`target/Controller/erase/controller_host_erase_report.txt`](../../target/Controller/erase/controller_host_erase_report.txt) (`controller_host_erase_tb`):

```text
//------------------------------------------------------------------------------
// controller_host_erase_tb — host CMD_ERASE on cell A, cell B untouched
// Phase 3 is CMD_ERASE only (RTL erase_from_host): expect state=4 (ERASE) only,
//       then idle — no PROG/VERIFY after host erase.
```

## Batch checks to quote

| Testbench | What it proves |
|-----------|----------------|
| `controller_addr_pulse_tb` | `ann_core_word` + pulse mode per command |
| `parallel_interface_controller_integration_tb` | PI decode + controller + buffer; `tb_pi_controller_integration.txt` |
| `controller_prog_verify_lut_tb` | 640-weight flow, 0 errors, `prog_verify_report.txt` (LUT PROG) |
| `controller_host_erase_tb` | Host `CMD_ERASE` on one cell; neighbor unchanged → `controller_host_erase_report.txt` |
