# Analysis, Limitations, Future Work, and Terminology

## Purpose of this chapter

This final chapter closes the project book by tying together what the RTL and directed testbenches *actually* establish about the `ann_controller` and its surrounding blocks, what remains unproven, and what a follow-on hardware or verification team would reasonably do next. Every technical claim below is traceable to the SystemVerilog sources and the testbench or log files under this repository; no fabrication of silicon metrics, power, or unimplemented features is used as evidence.

---

## 1. Design choices and architectural rationale

### 1.1 Module parameters versus package-level structure

`ann_controller` exposes `ADDR_WIDTH` and `WEIGHT_WIDTH` as instance parameters, defaulting to `controller_pkg::DEFAULT_ADDR_WIDTH` (8) and `DEFAULT_WEIGHT_WIDTH` (16) (`source/Controller/controller.sv`). In the current `controller.sv` body, those two parameters are **not** referenced in combinational or sequential logic; the live datapath instead relies on **package** definitions such as `WEIGHT_ADDR_WIDTH` (10 bits for a packed ANN location), the 16-bit `address` field from the parallel interface, 4-bit verification data on `weight_read_data`, and buffer addressing via `BUF_ADDR_WIDTH` and `input_buffer_pkg::BUFFER_ADDR_WIDTH`. Practically, this means: scalability and mapping logic are **centralized in `controller_pkg`** and in shared helpers, while the two module parameters function as a **compatibility hook** for a future top-level that might unify width conventions—until they are wired into expressions, they do not, by themselves, change generated logic.

The **practical** modularity for different weight-matrix footprints is therefore implemented in `controller_pkg`: constants such as `MAX_MATRIX_ROWS`, `MAX_MATRIX_COLS`, `DEFAULT_MATRIX_ROWS` / `DEFAULT_MATRIX_COLS`, and `TOTAL_WEIGHT_LOCATIONS` (1024) bound the *intended* addressable space, while `buffer_idx_to_matrix_coords`, `matrix_coords_to_ann_addr`, and `buffer_idx_to_ann_addr` implement **deterministic** mapping from a linear index to `{block, sub_block, row, col}` for programming-related flows. The code paths include optimized branches for `matrix_cols` of 64, 32, 16, and 8 (`buffer_idx_to_matrix_coords`), and comments note that the 10×64 (640-weight) use case is the one exercised by current testbench data. A later team that changes matrix geometry would adjust these helpers and the **source** of `weight_count_reg` / `matrix_rows` / `matrix_cols` (today defaulted in reset and partially updated only on paths involving `S_RESET` / legacy sequencing) rather than only overriding `WEIGHT_WIDTH` on the module line.

**Why this matters for robustness:** a single `controller_pkg` gives one place to keep **pulse timing math**, **address packing**, and **matrix-to-core mapping** aligned with the parallel interface’s `parse_ann_address` / `ann_tail_to_parallel_addr` conventions. That reduces the risk of the controller emitting an `ann_core_word` that the PI cannot round-trip, or that decodes to a different cell than the buffer address used for verify.

### 1.2 Helper functions, pulse trains, and the LUT path

`controller_pkg` implements reusable **cycle-accurate** building blocks: `pulse_train_total` and `pulse_train_active` expand a burst model (T cycles per burst, N bursts, G idle cycles) into the `pulse_cnt` / `pulse_done` discipline used in `ann_controller`. For `USE_WEIGHT_PULSE_LUT`, two additional helpers—`pulse_lut_macro_repeat_total` and `pulse_lut_macro_repeat_active`—repeat a **macro** train (one PROG burst pattern of length `pulse_train_total(TPROG, PULSE_NUM_PROG, PULSE_GAP)`) a variable number of times, `Rlut`, with `PULSE_GAP` high-Z between copies (`source/Controller/controller.sv` PROG_WRITE branch).

**Engineering rationale for the LUT (as evidenced by the RTL, not by external device data):**

- **Per-weight shaping without editing RTL constants:** the first programming attempt for a given expected weight uses `weight_pulse_cycles_lut[expected_weight]` (loaded from `WEIGHT_PULSE_LUT_FILE` via `$readmemh`) as the repeat count `Rlut` for that macro train. Re-synthesizing or recompiling the controller is *not* required to change how aggressively a 4-bit code is programmed; only the **memory image** (e.g. `target/Controller/programming_inputs/weight_pulse_lut.mem`) need change. That is a standard way to hand off **calibration** or **recipe** data from characterization flows to digital control.
- **Contrast with the non-LUT path:** when `USE_WEIGHT_PULSE_LUT` is 0, `pulse_total` and `pulses` in PROG_WRITE follow fixed `TPROG` / `PULSE_NUM_PROG` / `PULSE_GAP` from the package. Every weight would see the same electrical programming footprint on the first attempt.
- **Retry path is intentionally “short”:** for `prog_retry_cnt > 0`, the same combinational block forces `Tp = 1`, `Np = 1`—a single-cycle active slice of the train—so later attempts do not blindly repeat the full LUT-scaled first pulse. The RTL is thereby structured for **staged** programming: a strong first shot from the table, then **incremental** pulses if verify still fails.

The LUT file in the repository is a **hex list** of 16 lines (one row per `expected_weight` index in the 4-bit range used by the mock flows). The document does not interpret resistance or analog yield; it only states what the code does: **the repeat count** for the first PROG is **data-driven** from a file.

### 1.3 `ann_core_word` and the parallel interface

The 32-bit `ann_core_word` is consistently described as: high byte = payload (`[31:24]`, including quantized weight in `[27:24]` for programming), low 24 bits = one-hot **PE**, **SA**, column, and row fields (`source/Controller/controller.sv` comments; `parallel_interface_pkg` host data layout). Functions `pack_ann_core_word`, `host_addr_to_ann_addr_out`, `ann_core_word_decode`, and `parse_ann_address` keep the same bit-field contract across the controller, parallel interface, and testbenches. The PI additionally defines `ann_tail_is_valid_onehot` so that only strictly one-hot tails produce `valid=1` at the controller—invalid combinations are **suppressed** at the interface, not “fixed” inside the FSM. That is an architectural **guardrail** with a clear verification target: FSMs can assume one-hot decodability when `valid` is high.

### 1.4 Sub-FSMs and recovery (PROG, VERIFY, ERASE)

Programming uses `prog_sequence_state_t` (HIZ → SELECT → WRITE → WAIT_ACK → COMPLETE). Verify uses `verify_state_t`; erase uses `erase_state_t` (`controller_pkg`). Recovery policy is explicit in the RTL: `weight_read_data < expected_weight` with `prog_retry_cnt < MAX_PROG_RETRIES` leads to re-PROG; `weight_read_data > expected_weight` or too many re-PROG attempts leads toward erase; `erase_from_host` distinguishes host-issued `CMD_ERASE` from verify-driven erase. This structure is what the 640-weight and 10-weight program/verify benches exercise with **injected** readback errors (see Section 3).

---

## 2. What the verification results actually prove

The repository records directed-test outcomes under `target/`. The following interprets *what is demonstrated*, not just that logs exist.

### 2.1 Address and pulse contract (`controller_addr_pulse_verify.txt`)

`controller_addr_pulse_tb` (`verif/Controller/tb/regular/prog/controller_addr_pulse_tb.sv`) checks packing of `ann_core_word` and the mapping from `pulses[2:0]` to `PULSE_MODE_*` for the commands exercised. The generated report documents **30** distinct directed cases (Test 1–30), each `PASS` for the expected `ann_core_word` format and encoded pulse mode.

**Implication:** the controller’s **static** I/O contract—how host address bits become one-hot **PE/SA/col/row**, and how each command class requests READ/PROG/ERASE/INF on the 3-bit pulse bus—is consistent with `controller_pkg` parameters (`TREAD`, `TPROG`, etc., as listed in the report header). This mitigates integration risk with the **parallel interface and ANN core pin semantics** as modeled in SV.

### 2.2 Host read reorder (`controller_host_read_reorder_report.txt` / `controller_host_read_reorder_tb.sv`)

The bench programs eight weights at eight different decoded addresses, then issues `CMD_READ` in a **permuted** order (program indices `4 0 7 2 1 6 3 5`). The mock ADC returns the memristor model value indexed by `ann_core_word_decode(ann_core_word)`. The report summary: **`PASS=8 FAIL=0`**.

**Implication:** correctness does not depend on reading cells in the same order they were programmed. The chain **address → `ann_core_word` on READ → cell selection in the mock → 4-bit data path** is stable under reordering. Architectural risk mitigated: **stale address registers**, **wrong one-hot field**, or **read pulse discipline** that accidentally depended on program sequence would likely fail this test.

### 2.3 Program/verify with LUT and injected failures (`prog_verify_report.txt` / `controller_prog_verify_lut_tb.sv`)

The large regression loads 640 weights, drives `CMD_PROG` with LUT-based first PROG, and the testbench **injects** `read < expected` and `read > expected` on specific indices to force re-PROG and ERASE branches (see the `is_inject_read_lt` / `is_inject_read_gt` functions in the bench). The report records many tagged `re-PROG` and `ERASE` sequences; the file footer states **640** weights programmed and **“0 errors in 640 weights”** (`target/Controller/prog/prog_verify_report.txt`).

**Implication:** the **closed loop** of program → verify → compare → optional re-PROG or erase and reprogram is exercised **end-to-end in simulation** for a full sweep, including **stressed** indices early and late in the run. The risk of subtle counter or state stuck conditions only appearing after many weights is **partially** reduced (not eliminated for all possible `op_done` or analog behaviors).

The compact 10-weight bench (`controller_prog_verify_lut_10w_tb.sv`, `prog_verify_10w_report.txt`) exists for **faster** waveform debug; it reports **10/10 PASS** cases and a **0 errors** summary, with scenarios for match, under-read, over-read, and max re-PROG leading to ERASE (as described in the bench header). The 10w file also documents a **limitation of what that bench can show** about `retry_cnt` in direct-address mode (see Section 4).

### 2.4 Host erase and non-target retention (`controller_host_erase_tb.sv`)

The erase test targets controlled addresses on the mock matrix and checks **clearing** of a selected cell while another cell **retains** its programmed value (see the TB structure: two addresses, matrix decode, before/after style checks in the log). **Implication:** the erase sub-FSM and pulse mapping do not indiscriminately clear unrelated decoded indices in the **testbench’s behavioral model**—a proxy for *spatial* selectivity of the command as wired through `ann_core_word`.

### 2.5 Parallel interface + controller + input buffer (`tb_pi_controller_integration.txt`)

`parallel_interface_controller_integration_tb.sv` logs mixed `CMD_READ`, `CMD_PROG`, `CMD_ERASE`, and `CMD_INF` in sequence. The log ends with **`PASS=10 FAIL=0`**. **Implication:** the handshakes and command multiplexing at the PI boundary interoperate with the controller and `input_buffer` in a **repeated** pattern without the dedicated per-feature benches’ assumptions breaking.

### 2.6 Input buffer and parallel interface logs (sampled)

Separate benches under `verif/Input_Buffer` and `verif/Parallel_Interface` produce `target/Input_Buffer/*.txt` and `target/Parallel_Interface/parallel_interface_extract_tb_log.txt` with pass-oriented summaries in the checked-in artifacts. They support the claim that **peripheral** concerns (buffer control, PI extraction) were simulated successfully in those runs, but they do not replace a full-chip analog or system-level sign-off.

### 2.7 INF path and `op_done`

In the current `controller.sv`, `op_done` is only referenced inside the program and erase sub-FSMs (`PROG_SELECT` / `PROG_WAIT_ACK`, `ERASE_SELECT` / `ERASE_WAIT_ACK`); the collect/compute/result path does not sample it. The INF-focused bench `controller_inf_buffer_flow_tb.sv` nevertheless **ties** `op_done` low in a clocked block, with a comment that it is **not used** by the RTL path under test. So INF behavior in simulation is not exercising `op_done` timing (and, given the RTL, a change that added `op_done` to INF would not be covered by the existing `op_done` generators in other benches).

---

## 3. Limitations, blind spots, and technical debt (code-backed)

### 3.1 No independent ANN behavioral or numerical model in RTL

Testbenches implement a **sparse 4D array** `ann_weight_matrix[...]` updated when programming is detected, and return `weight_read_data` as a function of `ann_core_word` decode. That is a **register-transfer mock**, not a memristor or MAC array model. **Untested** by that abstraction:

- Real **timing** of `op_done` relative to array settling (TBs use deterministic counters or immediate assertions for many paths).
- **End-to-end numerical accuracy** of an inference (no reference MAC against golden vectors in RTL).
- **Cross-talk**, **IR drop**, and **variability** beyond the **discrete 4-bit** readback injection patterns.

The project is honest about *what* is validated: **control sequencing** and **digital packet semantics** to a first-order memristor **abstraction**, not full accelerator accuracy.

### 3.2 `op_done` is a testbench-controlled artifact in most benches

In `controller_host_read_reorder_tb.sv` and the program/verify TBs, `op_done` is generated with cycle-count heuristics when certain `pulses` and DUT states are active. The **risk**: if a silicon `op_done` is late, early, or pulsed differently, PROG/ERASE sub-FSM timing in **hardware** may diverge from what the SV mock proved. The repository does not include min/max delay characterization—only the **FSM’s dependency** on `op_done` in RTL is real.

### 3.3 `S_RESET` is unreachable from `S_IDLE` in the current FSM

`S_IDLE` decodes `CMD_*` to `S_PROGRAM`, `S_ERASE`, `S_READ`, or `S_COLLECT_DATA` (`controller.sv`); it never sets `next_state = S_RESET`. State `S_RESET` still exists, drives `ann_reset` for a cycle, and forces `S_PROGRAM` on exit. Sequential logic still **initializes programming-related counters** when `state == S_IDLE && next_state == S_RESET` (e.g. `weight_count_reg`, `matrix_rows`/`matrix_cols`, `buffer_idx_reg`), but because no path sets that transition, this is **legacy or forward-looking** code. **Debt:** either remove dead transitions after audit, or add a host-visible reset command that **does** enter `S_RESET` if product needs global buffer/core reset from idle.

### 3.4 `weight_read_en` is assigned but not an output

A local `weight_read_en` is toggled in `S_VERIFY` (`verify_state == VERIFY_IDLE`) but the signal is not connected to a port and does not feed other logic in the excerpted design. The actual verify path **samples** `weight_read_data` in `VERIFY_CHECK`. **Debt:** delete the dead signal or connect it to a future `weight_read` qualifier if the core needs an explicit enable.

### 3.5 Module parameters `ADDR_WIDTH` / `WEIGHT_WIDTH` not driving logic

As noted, these parameters are not used in the `ann_controller` body. **Debt:** connect them to port widths, or remove from the public API to avoid misleading integrators who assume a width change re-parameterizes the core.

### 3.6 Direct-address flow versus legacy buffer-index flow

The RTL and comments show **two** conceptual programming histories: a **direct-address** path using `address_reg[5:0]` for buffer read/write in PROG/VERIFY, and **legacy** `buffer_idx_reg` / `weight_count_reg` support “kept for ERASE/VERIFY compatibility” (`controller.sv`). `weight_prog_done` is asserted in **both** the legacy “advance buffer on verify re-entry to program” path and the direct `PROG_COMPLETE` path. **Debt:** a maintenance pass could unify or formally deprecate the unused path to reduce double semantics.

### 3.7 Compact TB note on `retry_cnt` in direct-address mode

`controller_prog_verify_lut_10w_tb.sv` documents (header comment) that the **ERASE max-retry give-up** path (`erase_max_retries_exhausted` / `retry_cnt` accumulation) is **not reachable** in the direct-address flow as wired, because `PROG_COMPLETE` clears `retry_cnt` when `buffer_idx_reg < weight_count_reg-1` with the default 640 count—so **erase retry does not accumulate across** PROG cycles in that configuration. The limitation is **specific** to the interaction of reset conditions and the default `weight_count_reg`; it is not a claim about all possible parameterizations. A future test should either shrink `weight_count_reg` in a contrived scenario or drive the legacy buffer sweep to **hit** `erase_max_retries_exhausted`.

### 3.8 Repository scope

There is **no** UVM testbench, **no** checked-in formal property set, and **no** gate- or post-layout netlist in the explored tree. Those absences are **out of scope** of what this repository demonstrates, not proofs of impossibility.

---

## 4. Future work: a concrete engineering roadmap (RTL-scoped)

The items below are actionable **for teams continuing in SystemVerilog** on this codebase, without presupposing tools beyond what is implied by the files.

### 4.1 SystemVerilog Assertions (where and what)

Assertions should **bind to `ann_controller` instances** in testbenches (or a wrapper module) so RTL files stay lint-clean, or use `bind` if the flow supports it. Concrete **interfaces** to watch: `valid`, `cmd`, `busy`, `pulses`, `op_done`, `state`, `prog_state`, `verify_state`, `erase_state` (DUT is referenced hierarchically in TBs, e.g. `dut.state`).

| Concern | Suggested check (illustrative, to be encoded as SVA) | Grounding |
|--------|------------------------------------------------------|-----------|
| **Handshake** | If `valid` rises while `state==S_IDLE` and a legal `cmd` is sampled, `busy` (or a transition out of idle) should follow within bounded cycles, unless `rst_n` drops | Idle decode in `S_IDLE` |
| **`op_done` usage** | In `PROG_SELECT` / `PROG_WAIT_ACK` / `ERASE_SELECT` / `ERASE_WAIT_ACK`, if the RTL samples `op_done` as the advance condition, do not allow `X` on `op_done` during those sub-states in simulation (sim-only), or add toggle/stability properties if the analog team supplies bounds | `next_prog_state` / `erase_next` in `controller.sv` |
| **Pulse / mode consistency** | When `pulses` is a non-HIZ read mode, `pulse_cnt` should stay within `0..pulse_total-1` until `pulse_done` (repeat per command state) | `pulse_done` and `pulse_cnt` update block |
| **Invalid tail** | If using PI in loopback, `ann_tail_is_valid_onehot(host_data[23:0])` is a pre-condition for `valid` in PI—mirror as assume/cover in TB | `parallel_interface_pkg` |
| **INF** | If INF is extended to use `op_done`, add cases where `op_done` is *not* tied low, unlike `controller_inf_buffer_flow_tb` | Section 2.7 |

**Where to integrate:** the parallel interface integration and program/verify testbenches are the natural first targets: they already instantiate the DUT and reference internal state for `op_done` generation.

### 4.2 Toward constrained-random and coverage-driven stimulus

**Reuse existing infrastructure:** `build_host_ann_word` / `ann_tail_to_parallel_addr` and the `ann_tail_is_valid_onehot` predicate give a **legal host packet** generator. A next step is:

1. **Randomize** `host_data[31:0]` and `host_cmd` subject to one-hot tail validity and legal `cmd` values (`cmd_t` in `parallel_interface_pkg`).
2. **Constrain** sequences to the controller FSM: e.g. do not send a new `valid` when `busy` is high unless the protocol is defined to allow pipelining (the current FSM does not; **idle-wait** is the safe constraint).
3. **Coverage:** define covergroups on `state`, `prog_state`, `verify_state`, `erase_state`, and on branches taken in `VERIFY_CHECK` (match, under, over), plus **crosses** with `cmd` at idle.

**Self-checking:** re-use the mock matrix pattern from `controller_prog_verify_lut_tb.sv` to compare `ann_core_word` decode to expected storage, and keep **directed** regressions as a **shrinking** baseline when random finds failures.

### 4.3 Recovery and corner-case test expansion

- **Intentional** `read < expected` / `read > expected` injection should be **parameterized** (indices, counts) to hit `prog_retry_cnt` **equals** `MAX_PROG_RETRIES` and multiple **ERASE** rounds without relying on 640-weight runtime every time.
- **Host erase vs verify-erase:** cover both with `erase_from_host` true and false, observing `S_ERASE` entry sources (decode `erase_from_host` in waves already).

### 4.4 Optional consolidation of programming modes

If product direction is a **single** programming interface (buffer sweep only or direct only), the dead `S_RESET` path, unused parameters, and dual `weight_prog_done` semantics can be refactored with a spec-backed decision—reducing the **fan-out** of future SVA and CR environments.

### 4.5 Documentation alignment

The repository `README.md` uses the phrase **in-memory computing (IMC)** at project level; RTL comments refer to the **parallel interface** and **ANN core**. The glossary below relates those terms without attributing IMC behavior to a specific SystemVerilog module name.

---

## 5. Verification challenges: recovery FSMs and “natural” convergence

The re-PROG and ERASE sub-FSMs exist precisely because a **naive** program-once flow would leave weights wrong; in simulation, a **well-behaved** mock that updates the matrix on PROG and returns accurate reads **converges** in one verify. That **hides** the FSM’s recovery branches.

**What the project did:** `controller_prog_verify_lut_tb.sv` (and the 10w variant) **overrides** `weight_read_data` during a narrow **verify window** to simulate **under**- and **over**-read conditions relative to the buffer’s expected nibble, forcing `VERIFY_CHECK` to take the re-PROG and ERASE paths. Without that injection, the **same RTL** would “pass” a 640-weight run while almost never visiting those states.

**Engineering cost:** the TB author must **align** phase detectors (`pulses`, `in_verify_phase`, `verify_cycle_cnt`, etc.) with the sample point in `VERIFY_CHECK` so injections are not mis-timed. The long report exists because **observability** of multi-hop state across main FSM and sub-FSM is hard to see without waveforms—hence the separate **wave** testbench variants and `.do` files under `verif/Controller/do/waves/`.

A related issue is **controllability of `op_done`:** because many TBs model `op_done` as a function of **pulse** counts, changing pulse trains (e.g. LUT `Rlut` large) **stretches** simulated time. The compact 10w bench is the documented mitigation for **iteration speed**, not a substitute for the full 640-weight regression.

---

## 6. Terminology (project and codebase)

Definitions are aligned with `controller_pkg`, `parallel_interface_pkg`, and `input_buffer_pkg` unless noted.

- **`ann_core_word` (ANN core word)**  
  32-bit controller/PI payload: `[31:24]` = data byte; `[23:0]` = `{PE[3:0], SA[3:0], col one-hot[7:0], row one-hot[7:0]}` in the encoding produced by `host_addr_to_ann_addr_out` / `pack_ann_core_word`. The MSB nibble of the data byte carries the quantized **weight** in programming-related contexts per RTL comments.

- **PE (Processing Element)**  
  4-bit **one-hot** field in `ann_core_word[23:20]` selecting which of the four top-level **blocks** (see `block_id` in `parse_ann_address` / matrix mapping) is addressed. In `host_addr_to_ann_addr_out`, `pe_onehot = (1 << block_id)`.

- **SA (Sub-Array)**  
  4-bit **one-hot** in `ann_core_word[19:16]` for the sub-block within a block (`sub_block_id`).

- **Row / column (ANN)**  
  8-bit one-hot fields `[15:8]` (column) and `[7:0]` (row) within the sub-block, decoded to 3-bit `row_id` / `col_id` for internal addressing.

- **PI (parallel interface)**  
  The `parallel_interface` module and its package types: translates `host_data` + `host_cmd` into `valid`, `data[7:0]`, `address[15:0]`, and `cmd[2:0]` for `ann_controller`. The host **32-bit** word matches `ann_core_word` layout; the command is **separate** on `host_cmd[2:0]`.

- **`valid` (command valid)**  
  When asserted with a legal tail (see `ann_tail_is_valid_onehot` in `parallel_interface_pkg` / PI logic), a new host transaction is accepted. Illegal tails block `valid` to the controller.

- **`cmd_t` / `CMD_*`**  
  `CMD_READ`, `CMD_PROG`, `CMD_ERASE`, `CMD_INF` (and `CMD_HIZ` in encoding space): operation requested at the controller boundary after PI decode.

- **`pulses[2:0]` / `pulse_mode_t`**  
  Encoded line toward the **ANN core** for READ, PROG, ERASE, or INF burst patterns; built from `pulse_train_active` and related helpers, not arbitrary bit patterns.

- **`op_done`**  
  **Core handshake** used in programming and erase sub-FSMs: advances `PROG_SELECT→PROG_WRITE`, `PROG_WAIT_ACK→PROG_COMPLETE`, `ERASE_SELECT→ERASE_PULSE`, and `ERASE_WAIT_ACK→ERASE_COMPLETE` when asserted as required by the RTL. Testbenches model it; silicon timing is **not** in-repo.

- **PROG / VERIFY / ERASE (paths)**  
  `S_PROGRAM` with `prog_sequence_state_t` for **write**; `S_VERIFY` with read burst and `VERIFY_CHECK` compare; `S_ERASE` with `erase_state_t` for **pulse** and completion. “Path” in verification reports also refers to **injected** failure routes (re-PROG, ERASE).

- **Re-PROG**  
  Return from a failed verify (`read < expected`, retries available) to `S_PROGRAM` without a full host-initiated sequence—mapped in RTL via `S_VERIFY` → `S_PROGRAM` with `prog_retry_cnt` update.

- **`erase_from_host`**  
  Internal flag: **host-issued** `CMD_ERASE` from `S_IDLE` (set when `valid && cmd==CMD_ERASE` in idle) versus verify-driven erase (cleared when transitioning `S_VERIFY→S_ERASE` for mismatch).

- **Bit-serial outputs `D0`–`D7` / `buf_bit_sel`**  
  `input_buffer` presents one bit per output lane per cycle from the stored byte, selected by `bit_sel[2:0]`. The controller in `S_COMPUTE` **steps** `bit_count` 0..7 and drives `buf_bit_sel` to implement LSB-first **bit-serial** readout of collected data.

- **LUT pulse mode**  
  `USE_WEIGHT_PULSE_LUT=1`: first PROG attempt uses `WEIGHT_PULSE_LUT_FILE` entry indexed by the **expected** (buffer) weight nibble to set **how many** macro pulse trains are concatenated. `USE_WEIGHT_PULSE_LUT=0`: fixed `TPROG`/`PULSE_NUM_PROG` train only (see `pulses`/`pulse_total` combinational block).

- **`ann_reset`**  
  Controller output used in `S_RESET` (currently not reached from `S_IDLE` in the shipped FSM graph).

- **IMC (in-memory computing)**  
  **Project** term in `README.md` for the overall accelerator context. Individual RTL files in this tree refer to the **parallel interface** and **ANN core**; there is no module literally named `imc` in the searched SystemVerilog.

- **MNIST (input buffer context)**  
  In `input_buffer_pkg`, `CTRL_DATA_LOAD` and row/column constants are labeled with MNIST-oriented naming; the buffer stores pixel-like streams for the INF path as modeled in TBs.

---

## 7. Closing statement

The controller and its verification **do** establish, under explicit modeling assumptions, a coherent **digital control** layer: command decoding, one-hot **addressing**, burst-shaped **pulses**, program/verify/erase **recovery** when readback is **forced** to misbehave, and **interoperability** with the **parallel interface** and **input buffer**. The same evidence shows **limits**: behavioral mocks stand in for physical arrays; **`op_done`** and **`weight_read_data`** are idealized; several **compatibility** hooks (**`S_RESET`**, **unused parameters**, **internal `weight_read_en`**) are **not** part of a minimal proven subset. A rigorous next phase is therefore not merely “more tests,” but **assertions** on the real protocols, **randomized** legal stimuli with **coverage** of FSM and recovery branches, and—where the program requires it—**models** that lift the abstraction from 4-bit tables to the actual non-idealities the silicon team must sign off on.

That progression stays faithful to the boundary of what this repository can claim today, while giving a VLSI follow-on team a **defensible** map from the present RTL to a production-grade sign-off process.
