# Report Structure Suggestion
## RTL Design and Verification of a Controller for an ANN Accelerator with In-Memory Computing Peripherals

> **Technion VLSI Lab — Course Project**  
> Suggested structure for a LaTeX report (Overleaf-ready).  
> Review and approve this structure before drafting begins.

---

## My Reading and General Opinion

After reading all five context documents, all three RTL source modules and their packages, the full testbench catalog, and the simulation output reports, here is my honest assessment:

**This is a well-scoped, technically rich project.** The controller is not trivial: it has a hierarchical FSM (main state + three sub-FSMs), a data-driven LUT-based pulse shaper, two separate one-hot address encoding/decoding paths, and a closed-loop program→verify→erase recovery chain. The verification is serious: shadow-matrix mocking of memristor behavior, deliberate fault injection (28 specific weight indices forcing under/over-program paths), a 640-weight regression, and a complete integration bench. All of that gives you **real, cite-able evidence** for the verification section.

The right report for this project is one that:
1. **Motivates** the IMC/memristor context properly (why a controller like this is needed at all).
2. **Describes the architecture** at two levels — system level (the three modules, their roles, the dataflow) and block level (detailed FSM, address encoding, pulse math).
3. **Makes the verification methodology look intentional**, not just "we ran some testbenches." The fault injection strategy, the shadow matrix, and the scoreboard design are all publishable-quality ideas.
4. **Is honest about scope limits** — no gate-level, no physical model, no UVM — without underselling what was actually achieved.
5. **Pushes the heavier technical detail (full FSM tables, all port tables, waveform images, code listings) to an appendix** so the main body stays readable.

---

## Proposed Structure

---

### Title
**RTL Design and Functional Verification of a Memristor Weight-Programming Controller for an ANN In-Memory Computing Accelerator**

*(Or a shorter variant you prefer.)*

---

### Abstract *(~250 words)*

One dense paragraph covering: what the system is (ANN accelerator controller for an IMC chip), what was designed (three RTL modules: parallel interface, controller FSM, input buffer), what was verified (directed SV testbenches in ModelSim, 640-weight regression, fault-injected verify/erase recovery), and the key result (all 10 integration tests pass, zero errors in 640-weight program-verify sweep, both re-PROG and ERASE recovery paths exercised).

---

### 1. Introduction

| Sub-section | What to cover |
|---|---|
| 1.1 In-Memory Computing and ANN Acceleration | Why IMC is interesting: near-memory MAC, memristor crossbars, energy argument. Set the motivation without claiming your RTL implements any of this physically. |
| 1.2 Project Context and Goals | This is an RTL + functional verification project: implement a controller that sequences programming, reading, erasing, and inference operations toward an ANN core, and verify that sequencing through simulation. State scope explicitly (no netlist, no silicon). |
| 1.3 Contributions | Three RTL modules implemented, one hierarchical FSM with recovery, LUT-based pulse shaping, full simulation suite. |
| 1.4 Report Organization | One paragraph describing the rest of the report. |

---

### 2. Background

| Sub-section | What to cover |
|---|---|
| 2.1 Non-Volatile Resistive Memory and Memristors | Basic R/W physics at the right abstraction level: conductance states, program/erase operations, the read-verify need. Tie to the 4-bit weight model used in the project. |
| 2.2 The Write-Verify Problem | Why a simple "write once" doesn't work: process variation, drift. This is the engineering motivation for the whole PROG→VERIFY→ERASE→REPROG loop. |
| 2.3 Related Work | Briefly: existing ANN accelerator controllers, IMC peripheral designs in the literature. A few citations from the background papers. Keep short. |
| 2.4 Design Context: Where This Controller Sits | The controller is the digital glue between a host processor and the ANN analog core. Describe the role without over-claiming the analog side. |

---

### 3. System Architecture

| Sub-section | What to cover |
|---|---|
| 3.1 Top-Level Block Diagram | Host → Parallel Interface → ANN Controller → Input Buffer → ANN Core. Draw it. Label data widths and control signals. This should be Figure 1. |
| 3.2 Module Roles and Responsibilities | One paragraph each on PI (combinational decode), Controller (FSM sequencer), Input Buffer (pixel storage for inference). |
| 3.3 The 32-bit ANN Core Word | The `ann_core_word` field layout: `[31:24]` payload, `[23:20]` PE one-hot, `[19:16]` SA one-hot, `[15:8]` column one-hot, `[7:0]` row one-hot. This is the key integration contract. A small table/figure here is worth a lot. |
| 3.4 Command Set | `CMD_READ`, `CMD_PROG`, `CMD_ERASE`, `CMD_INF`, `CMD_HIZ`. A simple table with encodings. |
| 3.5 Repository File Organization | Brief: `source/`, `verif/`, `scripts/`, `target/`. Explain how they relate. |

---

### 4. RTL Module Design

This is the technical heart of the report. Split into three subsections, one per module.

#### 4.1 Parallel Interface (`parallel_interface`)

| Sub-section | What to cover |
|---|---|
| 4.1.1 Module Overview | Pure combinational; no sequential logic despite having `clk`/`reset` ports. |
| 4.1.2 One-Hot Tail Validity | `ann_tail_is_valid_onehot`: four independent predicates (PE 4-bit, SA 4-bit, col 8-bit, row 8-bit). The `valid` signal formation: command != HIZ AND all four one-hot checks pass. Consequence: invalid tails are silently suppressed before the FSM. |
| 4.1.3 Tail-to-Address Mapping | `ann_tail_to_parallel_addr`: case-decode to index, then pack into 16-bit address `{6'b0, blk[1:0], sb[1:0], cid[2:0], rid[2:0]}`. Explain the bit layout. |
| 4.1.4 I/O Summary | Port table (abbreviated here, full table in Appendix B). |

#### 4.2 ANN Controller (`ann_controller`)

| Sub-section | What to cover |
|---|---|
| 4.2.1 Module Overview | Parameterized (`ADDR_WIDTH`, `WEIGHT_WIDTH`, `USE_WEIGHT_PULSE_LUT`, `WEIGHT_PULSE_LUT_FILE`). Implementation structure: one large combinational block + two `always_ff` blocks. |
| 4.2.2 Register Capture | On `valid && state==S_IDLE`: latch `address_reg` and `data_reg`. Why this matters: subsequent states use registered values, not live PI outputs. |
| 4.2.3 Main FSM | 9 states: `S_IDLE`, `S_RESET`, `S_PROGRAM`, `S_VERIFY`, `S_ERASE`, `S_READ`, `S_COLLECT_DATA`, `S_COMPUTE`, `S_RESULT`. State transition diagram as a figure (simplified version — full diagram in Appendix A). Describe each state's role in 1–2 sentences. |
| 4.2.4 Program Sub-FSM | `PROG_HIZ → PROG_SELECT → PROG_WRITE → PROG_WAIT_ACK → PROG_COMPLETE`. Role of `op_done` (Mealy-style level-sensitive condition). Role of `pulse_done`. Buffer access during each sub-state. |
| 4.2.5 Verify Sub-FSM | `VERIFY_IDLE → VERIFY_WAIT → VERIFY_CHECK → VERIFY_DONE`. The three outcomes of VERIFY_CHECK: match (→DONE), under-programmed with retries (→re-PROG), over-programmed or retries exhausted (→ERASE). |
| 4.2.6 Erase Sub-FSM | `ERASE_HIZ → ERASE_SELECT → ERASE_PULSE → ERASE_WAIT_ACK → ERASE_COMPLETE`. The `erase_from_host` flag: distinguishes host-issued CMD_ERASE from verify-driven erase. ERASE_COMPLETE branching logic. |
| 4.2.7 Pulse Generation and LUT-Based Programming | `pulse_total`, `pulse_done`, `pulse_cnt` discipline. Fixed vs. LUT path (`USE_WEIGHT_PULSE_LUT`). LUT path: `Rlut` from `weight_pulse_cycles_lut[expected_weight]`, macro-repeat structure. Retry path: short single-cycle pulse for `prog_retry_cnt > 0`. Engineering rationale: data-driven calibration without RTL re-synthesis. |
| 4.2.8 Inference Path | `S_COLLECT_DATA` (8 pixels from host, row-major write to buffer) → `S_COMPUTE` (bit-serial output via `bit_count`) → `S_RESULT` (unconditional return to idle). |
| 4.2.9 Address Packing Path | `parse_ann_address` (16-bit field slice) → index fields → `pack_ann_core_word` (left-shift one-hot reconstruction). Full round-trip contract: host tail → PI → `address_reg` → `ann_core_word`. |

#### 4.3 Input Buffer (`input_buffer`)

| Sub-section | What to cover |
|---|---|
| 4.3.1 Storage Array | 64×8-bit synchronous register array. Write path: `buf_read_write && CTRL_DATA_LOAD`, synchronous single-port. Async reset to zero. |
| 4.3.2 Combinational Read | `buf_data`: mux-selected byte by `buf_reg_add` during `CTRL_COMPUTE`, `CTRL_RESULT_OUT`, `CTRL_WEIGHT_READ`. |
| 4.3.3 Bit-Serial Outputs D0–D7 | Eight parallel lanes: lane `k` = `buffer_reg[addr+k][bit_sel]`. `bit_sel` steps 0→7 to implement LSB-first serial readout. Explain the 8-pixel group concept. |
| 4.3.4 Ready Signal | Mode/address-qualified: only high during explicit write-load or read modes with valid address. Not asserted in CTRL_IDLE. |

---

### 5. Verification Methodology

| Sub-section | What to cover |
|---|---|
| 5.1 Strategy Overview | Directed functional simulation only. No UVM, no SVA, no gate-level. State this upfront. Tools: ModelSim, Python `run_sim.py` driver. |
| 5.2 Testbench Infrastructure | DUT stacking (PI → Controller → Buffer). Report files (`$fopen`/`$fdisplay`). `run_sim.py` compile/sim/run_all commands. |
| 5.3 Memristor Behavioral Mock | The `ann_weight_matrix[blocks][sub_blocks][rows][cols]` shadow array. Update on `in_prog_core_phase`. `weight_read_data` driven from shadow array or injected value. `op_done` behavioral model. Why this is the right abstraction level for a control-layer verification. |
| 5.4 Testbench Catalog | Table of all testbenches (see table below). |
| 5.5 Fault Injection for Recovery Coverage | The key insight: a well-behaved mock converges in one verify, never exercising re-PROG or ERASE paths. Injection strategy: force `weight_read_data` to `expected - 1` (under) or `expected + 1` (over) during VERIFY_CHECK window via `in_verify_phase` / `verify_cycle_cnt` gating. 28 specific injection indices in the 640-weight run. |
| 5.6 Pass/Fail Accounting | Per-test counters, PASS/FAIL lines, summary format. `$fatal` on nonzero failure count. |

**Testbench Catalog Table** (to appear in this section):

| Testbench | DUT | Key Scenario | Outcome |
|---|---|---|---|
| `controller_addr_pulse_tb` | Controller | 30 directed address/pulse packing cases | 30/30 PASS |
| `parallel_interface_controller_integration_tb` | PI+Controller+Buffer | 10 mixed READ/PROG/ERASE/INF transactions | PASS=10 FAIL=0 |
| `controller_prog_verify_lut_tb` | Controller | 640-weight PROG+VERIFY with re-PROG/ERASE injection | 0 errors, recovery paths exercised |
| `controller_prog_verify_lut_10w_tb` | Controller | 10-weight compact with under/over/max-retry scenarios | 10/10 PASS |
| `controller_host_erase_tb` | Controller | Host CMD_ERASE, non-target retention check | PASS |
| `controller_host_read_reorder_tb` | Controller | 8 weights, permuted read order | PASS=8 FAIL=0 |
| `controller_inf_buffer_flow_tb` | Controller | 8-pixel INF collect → compute → bit-serial check | Pass |
| `input_buffer_bit_serial_tb` | Input Buffer | Bit-serial lane output correctness | PASS |
| `input_buffer_reset_behavior_tb` | Input Buffer | Reset initialization | PASS |
| `input_buffer_full_overwrite_tb` | Input Buffer | Full 64-byte overwrite | PASS |
| `parallel_interface_extract_tb` | PI | Valid/invalid tail decode, address extraction | 6/6 PASS |

---

### 6. Simulation Results

| Sub-section | What to cover |
|---|---|
| 6.1 Address and Pulse Contract | Cite the 30-case `controller_addr_pulse_verify.txt` report. What it proves: static I/O contract for all command types. |
| 6.2 Integration Test | Cite `tb_pi_controller_integration.txt` (PASS=10 FAIL=0). Walk through 2–3 interesting cases (e.g., 02_PROG showing buffer write, 04_INF showing 8-pixel collect, 09_PROG showing max-address case). |
| 6.3 Program-Verify-Erase Regression (640 weights) | Cite `prog_verify_report.txt`. Highlight: zero errors, multiple re-PROG and ERASE sequences observed in the phase log, both injected failure modes exercised. Include a short excerpt of the phase log as a figure/listing. |
| 6.4 Compact 10-Weight Run | Cite `prog_verify_10w_report.txt`. Show the under-read → re-PROG path and over-read → ERASE path explicitly. |
| 6.5 Host Erase and Read Reorder | Brief: erase selectivity, permuted read stability. Cite respective report files. |
| 6.6 Input Buffer and Parallel Interface | Brief: unit-level evidence for peripheral blocks. |

---

### 7. Analysis and Discussion

| Sub-section | What to cover |
|---|---|
| 7.1 Design Choices | Package-centralized parameters vs. module parameters (why `ADDR_WIDTH`/`WEIGHT_WIDTH` don't drive logic yet). Why this architecture — address packing as a shared function, one-hot validity as a guardrail at the PI boundary. |
| 7.2 LUT-Based Pulse Programming | Engineering rationale: separating calibration data from control logic. Staged programming: strong first shot (LUT), incremental retries. How this maps to real memristor programming practice. |
| 7.3 The Recovery FSM as a Key Design Element | Why PROG→VERIFY→ERASE is the right structure for resistive memory. The `erase_from_host` vs verify-driven erase distinction. The `prog_retry_cnt` and `retry_cnt` counters and their reset conditions. |
| 7.4 What the Verification Results Actually Prove | Be precise: control sequencing is correct under behavioral mock assumptions. The scope of claims: digital packet semantics, FSM coverage of recovery branches, address round-trip correctness. What it doesn't prove: analog accuracy, physical timing, gate-level behavior. |

---

### 8. Limitations and Future Work

| Sub-section | What to cover |
|---|---|
| 8.1 Behavioral Mock vs. Physical Memristor | The `ann_weight_matrix` is a 4-bit register, not a conductance model. `op_done` timing is idealized. No cross-talk or variability. |
| 8.2 Known RTL Issues | `S_RESET` unreachable from `S_IDLE`. `weight_read_en` driven but not consumed. `ADDR_WIDTH`/`WEIGHT_WIDTH` parameters unused in logic. Dual `weight_prog_done` semantics. |
| 8.3 SVA and Formal Verification | Concrete proposals: handshake assertions on `valid`→`busy`, `op_done` stability in sub-states, pulse counter bounds, one-hot preconditions. Where to bind them. |
| 8.4 Constrained-Random + Coverage | Using `build_host_ann_word` and `ann_tail_is_valid_onehot` as a legal packet generator. Covergroups: FSM state crosses, VERIFY_CHECK branch coverage. |
| 8.5 Gate-Level and Physical Design | What the next steps would be: synthesis, STA, power analysis — outside this project's scope but a natural continuation. |

---

### 9. Conclusion

~300 words. Summarize: what was built, what was verified, what the key results show, and where the work sits in a broader VLSI design flow. End with a forward-looking sentence on how this controller fits into a real IMC chip.

---

### References

~8–15 references. Expected categories:
- 2–3 IMC/memristor background papers (from your `report/Background_Papers/` folder)
- 1–2 ANN accelerator architecture papers
- 1–2 SystemVerilog/verification methodology references
- Textbook reference (e.g., Weste & Harris for VLSI)
- ModelSim/QuestaSim tool reference if needed

---

## Appendices (Technical Details and Images)

---

### Appendix A: FSM State Diagrams (Figures)

**A.1** — Main FSM (all 9 states, all transitions with labeled conditions)  
**A.2** — Program Sub-FSM (`PROG_HIZ` → ... → `PROG_COMPLETE`)  
**A.3** — Verify Sub-FSM (`VERIFY_IDLE` → ... → `VERIFY_DONE` with all VERIFY_CHECK branches)  
**A.4** — Erase Sub-FSM (`ERASE_HIZ` → ... → `ERASE_COMPLETE` with `erase_from_host` branching)

*These are directly derived from the Mermaid diagrams in `CONTROLLER_FSM_AND_CONTROL_LOGIC.md`.  
They will be rendered as TikZ or pgf state machine diagrams in LaTeX.*

---

### Appendix B: Module Port Tables

**B.1** — `parallel_interface`: full port table (direction, width, description, implementing logic)  
**B.2** — `ann_controller`: full port table (all 20+ ports)  
**B.3** — `input_buffer`: full port table

---

### Appendix C: Addressing and Packing Conventions

**C.1** — 16-bit parallel field bit layout (`[15:10]` reserved, `[9:8]` block, `[7:6]` sub-block, `[5:3]` col, `[2:0]` row)  
**C.2** — 32-bit `ann_core_word` field layout (figure: byte-oriented breakdown)  
**C.3** — One-hot tail encoding: `pi_is_onehot4`, `pi_is_onehot8` truth summary  
**C.4** — Address round-trip: host tail → PI decode → `address_reg` → `parse_ann_address` → `pack_ann_core_word` → `ann_core_word` (as a flow diagram)

---

### Appendix D: Pulse Timing Details

**D.1** — Pulse train model: definition of `pulse_train_total(T, N, G)` and `pulse_train_active(cycle_idx, T, N, G)`  
**D.2** — `pulse_total` per state/sub-state table  
**D.3** — LUT-based macro-repeat: `pulse_lut_macro_repeat_total` and `pulse_lut_macro_repeat_active`  
**D.4** — Weight Pulse LUT table (from `weight_pulse_lut_table.txt`): 16 entries, index = expected weight nibble, value = `Rlut` repeat count  
**D.5** — Timing diagram: one PROG cycle with LUT repeat (conceptual waveform: `pulses`, `pulse_cnt`, `pulse_done`, `prog_state`)

---

### Appendix E: Testbench Technical Details

**E.1** — Fault injection index sets: `is_inject_read_lt` indices (14 weights: 5, 15, 25, ...) and `is_inject_read_gt` indices (14 weights: 10, 30, 70, ...) from `controller_prog_verify_lut_tb.sv`  
**E.2** — `op_done` mock logic description (the `always_ff` in TBs that drives `op_done` based on DUT state)  
**E.3** — `send_prog_and_wait` task flow  
**E.4** — `check_cmd` / `check_inf_row8` task flow (integration TB)  
**E.5** — Phase string mapping: `PROG`, `REPROG`, `VERIFY`, `ERASE`, `PROG_PREP`, `COMPUTE`, `CHECK_DONE`

---

### Appendix F: Simulation Waveforms (Images)

**F.1** — Program→Verify (successful, no injection): pulses, ann_core_word, FSM state  
**F.2** — Under-program injection: PROG → VERIFY (fail) → re-PROG → VERIFY (pass)  
**F.3** — Over-program injection: PROG → VERIFY (fail) → ERASE → PROG → VERIFY (pass)  
**F.4** — INF path: S_COLLECT_DATA pixel writes → S_COMPUTE bit-serial output on D0–D7  
**F.5** — Integration test excerpt: two consecutive transactions showing idle-gating

*Waveforms to be captured from ModelSim GUI runs using the wave `.do` files already in `verif/Controller/do/waves/` and `verif/Input_Buffer/do/waves/`.*

---

### Appendix G: Selected RTL Source Listings

**G.1** — `parallel_interface_pkg.sv`: `ann_tail_is_valid_onehot`, `ann_tail_to_parallel_addr` function bodies  
**G.2** — `controller_pkg.sv`: `pulse_train_total`, `pulse_train_active`, `pulse_lut_macro_repeat_total`, `pulse_lut_macro_repeat_active` (the pulse math library)  
**G.3** — `controller.sv` excerpt: VERIFY_CHECK case body (the compare + retry + erase branching logic)  
**G.4** — `input_buffer.sv`: bit-serial D0–D7 output combinational block  
**G.5** — `scripts/run_sim.py`: key snippet showing the compile/sim flow

---

## Page Estimate

| Section | Estimated Pages |
|---|---|
| Abstract | 0.5 |
| Sections 1–2 (Intro + Background) | 3–4 |
| Section 3 (Architecture) | 2–3 |
| Section 4 (Module Design) | 6–8 |
| Section 5 (Verification Methodology) | 3–4 |
| Section 6 (Simulation Results) | 3–4 |
| Section 7 (Analysis) | 2–3 |
| Section 8 (Limitations + Future Work) | 2 |
| Section 9 (Conclusion) | 0.5 |
| References | 1 |
| **Main body total** | **~23–30 pages** |
| Appendix A (FSM diagrams) | 2–3 |
| Appendix B–C (port tables, addressing) | 2 |
| Appendix D (pulse timing) | 2 |
| Appendix E (testbench details) | 2 |
| Appendix F (waveforms) | 2–3 |
| Appendix G (code listings) | 3–4 |
| **Appendix total** | **~13–16 pages** |
| **Grand total** | **~36–46 pages** |

This can be trimmed or expanded depending on the course's page guidelines. The appendix structure is designed so entire sections can be dropped without breaking the main narrative.

---

## Questions Before Writing

1. **Page / word limit**: Does the course specify a maximum length? I can trim accordingly.
2. **Background depth**: How much do you want on IMC/memristor physics? A sentence-level mention or a full half-page background?
3. **Waveform images**: Do you have screenshots from ModelSim ready, or should the waveform appendix be a placeholder for now?
4. **Author / institutional details**: Name(s), course name, semester, supervisor — needed for the title page.
5. **LaTeX template**: Plain `article`, IEEE `IEEEtran`, or Technion-specific template?
