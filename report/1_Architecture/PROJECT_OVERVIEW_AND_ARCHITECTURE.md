# Project Overview and Architecture

This chapter describes the **internal RTL implementation** of the three top-level synthesizable blocks (`parallel_interface`, `ann_controller`, and `input_buffer`) and their packages. All behavioral detail below is taken directly from the corresponding SystemVerilog sources under `source/`.

---

## 1) Project Purpose and Scope

The repository implements a **controller-centric** RTL stack for an ANN accelerator interface: host traffic is decoded, sequenced into program/read/erase/inference operations, and driven to an ANN core via a packed 32-bit word plus a 3-bit pulse mode bus. The controllable command tokens defined in `parallel_interface_pkg` are:

- `CMD_READ`, `CMD_PROG`, `CMD_ERASE`, `CMD_INF`, and `CMD_HIZ` (idle / no transaction on the command port)

The scope present in this codebase is **RTL and functional simulation** (testbenches, scripts). No netlist, timing closure, or power/area analysis artifacts are part of the RTL paths documented here.

---

## 2) Top-Level Partitioning and Dataflow

The host presents a **32-bit payload** in the same layout as the controller’s `ann_core_word`, plus a **separate 3-bit command** (`host_cmd`). The `parallel_interface` module is **purely combinational** (no `always` blocks): it slices `host_data`, decodes the 24-bit tail into a 16-bit packed index field, passes `host_cmd` through, and computes a **qualifier** `valid`. The `ann_controller` module is **registered FSM logic** with multiple `always_ff` blocks for state, counters, and captured address/data; it drives ANN outputs, buffer control, and busy status. The `input_buffer` module holds **64 bytes** in a synchronous register array with combinational read and write-enable decode.

---

## 3) Deep Dive: `parallel_interface` (`parallel_interface.sv`, `parallel_interface_pkg.sv`)

### 3.1 RTL structure

The module body contains only **continuous assignments**:

- `data`    \(\leftarrow\) `host_data[31:24]`
- `address` \(\leftarrow\) `ann_tail_to_parallel_addr(host_data[23:0])`
- `cmd`     \(\leftarrow\) `host_cmd`
- `valid`   \(\leftarrow\) Boolean AND of (a) non-idle command and (b) tail structural validity

There is **no sequential logic** in this module: `clk` and `reset` are declared as ports but are **not referenced** in the module body. Any synchronization or reset behavior for host-side logic must exist outside this block (not described here unless present in higher-level wrappers).

### 3.2 How `valid` is formed: one-hot tail checks

`valid` is assigned as:

```text
valid = (host_cmd != CMD_HIZ) && ann_tail_is_valid_onehot(host_data[23:0])
```

Therefore **two independent conditions** must hold:

1. **Command activity:** `host_cmd` must not equal `CMD_HIZ` (`3'b000`). If the host holds the idle command, `valid` is forced low regardless of `host_data`.

2. **Tail legality:** `ann_tail_is_valid_onehot(tail)` must be true. That function is defined as the **logical AND** of four structural one-hot tests:

| Tail slice | Width | Predicate function | Meaning |
|------------|------:|--------------------|--------|
| `tail[23:20]` | 4 | `pi_is_onehot4` | Exactly one of four PE-select bits set |
| `tail[19:16]` | 4 | `pi_is_onehot4` | Exactly one of four SA-select bits set |
| `tail[15:8]`  | 8 | `pi_is_onehot8` | Exactly one of eight column bits set |
| `tail[7:0]`   | 8 | `pi_is_onehot8` | Exactly one of eight row bits set |

**`pi_is_onehot4(oh)`** returns 1 only for these four patterns: `4'b0001`, `4'b0010`, `4'b0100`, `4'b1000`. Any other 4-bit pattern (including all zeros and multi-hot) returns 0.

**`pi_is_onehot8(oh)`** returns 1 only for the eight patterns with a single 1 in positions 0..7 (e.g. `8'b00000001`, `8'b00000010`, …, `8'b10000000`). All other patterns return 0.

**Consequence:** If the host asserts a non-`HIZ` command but the tail is not strictly one-hot in **all four** fields, `valid` stays 0. The data and address outputs are still driven combinationally from `host_data` (including invalid tails), but downstream logic that gates on `valid` (the controller in `S_IDLE`) will **not** accept the transaction. This matches directed tests where all-ones `host_data` keeps `valid` deasserted despite a non-`HIZ` `host_cmd`.

### 3.3 `ann_tail_to_parallel_addr`: bit mapping from one-hot tail to 16-bit address

The conversion is a **decode-then-concatenate** path implemented entirely in a package function:

1. **Index extraction** via case-style decode functions (not priority encoders for unknown patterns—default maps to index 0):
   - `blk = pi_onehot4_to_idx(tail[23:20])` → 2-bit index in \([0,3]\)
   - `sb  = pi_onehot4_to_idx(tail[19:16])` → 2-bit index
   - `cid = pi_onehot8_to_idx(tail[15:8])` → 3-bit index in \([0,7]\)
   - `rid = pi_onehot8_to_idx(tail[7:0])`  → 3-bit index in \([0,7]\)

2. **Packed output:**  
   `return {6'b0, blk, sb, cid, rid};`

This yields a 16-bit value with:

- `[15:10] = 6'b000000` (always zero in this function)
- `[9:8]   = blk`
- `[7:6]   = sb`
- `[5:3]   = cid`
- `[2:0]   = rid`

This 16-bit layout is the same field layout the controller later parses with `parse_ann_address` (see §4.2). The **inverse** transformation (packed indices → one-hot tail) is implemented in `build_host_ann_word`: indices are turned back into one-hot vectors using `4'(1 << blk)`, `8'(1 << cid)`, etc., which is the structural dual of the decode path above.

### 3.4 Relation to the controller

The controller does **not** re-validate one-hot; it consumes `address` as a parallel field slice. **Semantic consistency** (host tail one-hot \(\leftrightarrow\) legal `address`) is enforced at the PI boundary when `valid` is high.

---

## 4) Deep Dive: `ann_controller` (`controller.sv`, `controller_pkg.sv`)

The module is declared as `ann_controller` and parameterized by `ADDR_WIDTH`, `WEIGHT_WIDTH`, `USE_WEIGHT_PULSE_LUT`, and `WEIGHT_PULSE_LUT_FILE`. The following subsections follow the **actual signal flow** in the RTL: registered captures → combinational parse/pack → pulse arithmetic → output multiplexing.

### 4.1 Register-level capture of host `address` and `data`

In `always_ff @(posedge clk or negedge rst_n)`:

- When `valid && (state == S_IDLE)`, the controller latches:
  - `address_reg <= address`
  - `data_reg <= data`

Thus for accepted commands, **subsequent states** (PROG, VERIFY, READ, ERASE, etc.) use the **registered** `address_reg`/`data_reg`, not the live PI outputs, except where the combinational FSM explicitly uses `data` for streaming (inference collection).

### 4.2 From 16-bit `address_reg` to index fields: `parse_ann_address`

A combinational macro block calls:

```text
parse_ann_address(address_reg, block_id, sub_block_id, row_id, col_id);
weight_addr_reg = {block_id, sub_block_id, row_id, col_id};
```

The package defines `parse_ann_address` as **direct bit slicing** of `address[15:0]`, ignoring `[15:10]` for field extraction:

- `block_id     = address[9:8]`
- `sub_block_id = address[7:6]`
- `col_id       = address[5:3]`
- `row_id       = address[2:0]`

So the physical RTL path is: **10-bit packed logical address** reconstructed as `{block_id, sub_block_id, row_id, col_id}` into `weight_addr_reg` (10 bits). Reserved bits `[15:10]` are not used inside `parse_ann_address`.

### 4.3 Packing `ann_core_word`: from indices to one-hot tail

When `state != S_IDLE`, the controller drives:

```text
ann_core_word = pack_ann_core_word(data_byte_for_ann, block_id, sub_block_id, row_id, col_id)
```

`pack_ann_core_word` implements:

1. `tail = host_addr_to_ann_addr_out(block_id, sub_block_id, row_id, col_id)`  
2. `return { data_byte, tail[23:0] }`

**`host_addr_to_ann_addr_out`** constructs each one-hot field by **left shift of 1** using the index widths:

- `pe_onehot  = (1 << block_id);`     // 4-bit, positions used as PE[23:20]
- `sa_onehot  = (1 << sub_block_id);` // 4-bit, SA[19:16]
- `col_onehot = (1 << col_id);`       // 8-bit, column field [15:8]
- `row_onehot = (1 << row_id);`       // 8-bit, row field [7:0]

The function returns `{pe_onehot, sa_onehot, col_onehot, row_onehot}` as a 24-bit tail (concatenation order matches comments in the package: PE, SA, col, row).

**Physical interpretation:** The combinational path from `address_reg` to `ann_core_word` is: **slice fields → barrel-shifter style one-hot masks** → concat with `data_byte_for_ann`. There is **no** stored “ANN tail register”; the word is recomputed every cycle from current `address_reg` parse and the selected data byte.

### 4.5 Multiplexing `data_byte_for_ann`

`data_byte_for_ann` is selected in an `always_comb` with a `unique case (state)`:

- For `S_PROGRAM`, `S_VERIFY`, `S_READ`, `S_ERASE`: use **`data_reg`** (captured in `S_IDLE`).
- For `S_COLLECT_DATA`: use **`data`** (current PI data, for streaming inference pixel input).
- Default: `8'b0`.

`ann_core_word` itself is forced to **all zeros** when `state == S_IDLE`; otherwise it uses `pack_ann_core_word` as above.

### 4.6 Pulse length computation: `pulse_total`, `pulse_done`, and the `pulse_cnt` counter

**`pulse_total`** is computed in a combinational `` `comb`` block as an 8-bit unsigned clip of integer helper results:

- **`S_READ`:** `PULSE_TOTAL_READ` (from `pulse_train_total(TREAD, PULSE_NUM_READ, PULSE_GAP)`).
- **`S_PROGRAM` and `prog_state == PROG_WRITE`:** three branches:
  - If `USE_WEIGHT_PULSE_LUT` is 0: standard `pulse_train_total(TPROG, PULSE_NUM_PROG, PULSE_GAP)`.
  - If LUT enabled **and** `prog_retry_cnt > 0`: shortened train with `Tp=1`, `Np=1`.
  - If LUT enabled and first attempt: `Mmacro = pulse_train_total(TPROG, PULSE_NUM_PROG, PULSE_GAP)` and `Rlut` from `weight_pulse_cycles_lut[expected_weight]` (with minimum 1); total length from `pulse_lut_macro_repeat_total(Rlut, Mmacro, PULSE_GAP)`.
- **`S_ERASE` and `erase_state == ERASE_PULSE`:** `PULSE_TOTAL_ERASE`.
- **`S_COMPUTE`:** `PULSE_TOTAL_INF` (which is `max(8, TINF*N + gaps)` per package).

**`pulse_done`** is combinational: `(pulse_total > 0) && (pulse_cnt >= pulse_total - 1)`.

**`pulse_cnt`** is a registered 8-bit counter in `always_ff`:

- Cleared to 0 on transitions into `S_READ`, into `PROG_WRITE`, into `ERASE_PULSE`, or into `S_COMPUTE` (from the conditions encoded in the main state register block).
- Incremented on cycles where the FSM remains in the same pulse-active phase and `!pulse_done`.

So the **pulse duration** is implemented as **load/increment-until-match** against `pulse_total`, not as a separate one-shot generator block.

### 4.7 Pulse mode on `pulses[2:0]`: burst trains and HIZ gaps

A second combinational block drives `pulses`. Default is `PULSE_MODE_HIZ` (`3'b000`). For each active mode, the RTL sets a Boolean “*_on” using:

- **`pulse_train_active(cycle_idx, T, N, G)`** for simple burst+gap patterns, or  
- **`pulse_lut_macro_repeat_active(...)`** for LUT-based PROG first-attempt shaping.

When the corresponding `*_on` is true, `pulses` takes `PULSE_MODE_READ` / `PROG` / `ERASE` / `INF`; otherwise `PULSE_MODE_HIZ`. Thus the **physical waveform** on `pulses` is a **time-multiplexed burst train**: active mode for T cycles within each burst, `HIZ` during `PULSE_GAP`, and (for INF) at least enough cycles so `PULSE_TOTAL_INF` meets the minimum of 8 for bit-serial use.

**VERIFY read pulses:** When `state == S_VERIFY` and `verify_state` is `VERIFY_IDLE` or `VERIFY_WAIT`, the train index passed to `pulse_train_active` is 0 in `VERIFY_IDLE` and `verify_pulse_idx` in `VERIFY_WAIT`, coordinating with a separate registered `verify_pulse_idx` sequence.

### 4.8 `weight_read_data` path: combinatorial compare and registered retry counts

The port `weight_read_data[3:0]` is **not latched inside the controller into a dedicated pipeline register**. Its uses are:

1. **Combinational next-state / verify FSM** (`VERIFY_CHECK`): compares `weight_read_data` to `expected_weight` (which is combinationally assigned from `weight_from_buffer`) to decide `verify_next` and whether to jump to `S_PROGRAM` or `S_ERASE`.

2. **Registered side effects in `always_ff`** when `verify_state == VERIFY_CHECK`:
   - `prog_retry_cnt` increments if `weight_read_data < expected_weight` and below max retries.
   - `prog_retry_cnt` clears on over-programmed / max-reprog branch conditions.
   - `program_stronger` may set when `weight_read_data != expected_weight` and `expected_weight > weight_read_data`.

So the **sampling edge** for retry policy is the **clock edge** that updates those registers while in `VERIFY_CHECK`, using the **stable values of `weight_read_data` and `expected_weight`** assumed valid at that cycle per synchronous design assumptions.

**Note:** `weight_read_en` is assigned in the combinational FSM block as 1 only in `VERIFY_IDLE`, but **no other statement reads `weight_read_en`**. In the current RTL it is a **dead internal flag** (driven but unused).

### 4.9 `op_done` handshake path (PROG and ERASE sub-FSMs)

`op_done` is an **input** to the module and is read in **combinational next-state** for sub-FSMs:

- **Program:** `PROG_SELECT` waits until `op_done` to enter `PROG_WRITE`. `PROG_WAIT_ACK` waits until `op_done` to enter `PROG_COMPLETE`. There is **no** `always_ff` registering `op_done`; it gates combinational `next_prog_state`, and `prog_state` updates on the clock from that next value.

- **Erase:** `ERASE_SELECT` waits until `op_done` before `ERASE_PULSE`. `ERASE_WAIT_ACK` waits until `op_done` before `ERASE_COMPLETE`.

Physical interpretation: this is **Mealy-style dependency** on `op_done` for sub-state transitions; hold timing on `op_done` must be satisfied relative to `clk` for reliable synthesis behavior (standard static timing discipline; not analyzed in this RTL-only document).

---

## 5) Deep Dive: `input_buffer` (`input_buffer.sv`, `input_buffer_pkg.sv`)

### 5.1 Storage array

The module declares:

```systemverilog
logic [BUFFER_DATA_WIDTH-1:0] buffer_reg [0:BUFFER_SIZE-1];
```

With package constants `BUFFER_SIZE = 64`, `BUFFER_DATA_WIDTH = 8`. This is a **64-entry byte RAM** implemented explicitly as a vector of registers, indexed by a 6-bit `addr` wire tied directly to `buf_reg_add`.

### 5.2 Write path: synchronous register updates

`write_en` is:

```text
write_en = buf_read_write && (reg_ctrl == CTRL_DATA_LOAD)
```

On **posedge `clk`**, if `write_en && is_valid_addr(addr)`, then `buffer_reg[addr] <= data_in`. Asynchronous active-low reset initializes **every** entry to zero in one reset block (for loop). Thus writes are **single-port, synchronous**, gated by both mode decode and address range check.

### 5.3 `buf_data` read path: combinational byte mux

`read_en` is true when `~buf_read_write && (reg_ctrl` is one of `CTRL_COMPUTE`, `CTRL_RESULT_OUT`, or `CTRL_WEIGHT_READ`)`)`.

The combinational block drives `buf_data` to zero by default; if `read_en && is_valid_addr(addr)`, `buf_data = buffer_reg[addr]`. So **`buf_data` is a purely combinational read** of one RAM word, mux-selected by `addr`.

### 5.4 Bit-serial outputs `D0`–`D7`: lane offsets and `bit_sel`

Comment and RTL define:

- For lane `k` in `0..7`, when `read_en` is true and `(addr + k) < BUFFER_SIZE`,  
  **`Dk = buffer_reg[addr + k][bit_sel]`**  
  Otherwise that `Dk` stays 0 (initial default in the combinational block).

**Physical structure:**

- **`buf_reg_add`** is the **base row** address of an 8-pixel group in the 1D array (addresses `addr` through `addr+7` along the row-major mapping used by TB comments).
- **`bit_sel[2:0]`** picks **which bit position within each byte** is exposed on all eight lines in parallel. Advancing `bit_sel` 0→7 over cycles implements **LSB-first** bit-serial output across the eight parallel lanes.
- Each `Dk` is a **2:1 effective mux**: first, bounds check `addr+k`; second, index into `buffer_reg[...]`; third, select bit `bit_sel` from that 8-bit entry.

If `read_en` is false, all `D0`–`D7` are driven low in that combinational block.

### 5.5 `ready` output: exact conditions

`ready` is driven in a combinational block with default 0. It becomes `is_valid_addr(addr)` in exactly two mutually exclusive situations:

1. **`reg_ctrl == CTRL_DATA_LOAD && buf_read_write`**  
   “Ready for write operations during data load.”

2. **`(reg_ctrl == CTRL_COMPUTE || CTRL_RESULT_OUT || CTRL_WEIGHT_READ) && !buf_read_write`**  
   “Ready for read operations during compute/result/weight read phase.”

All other combinations drive `ready = 0` (including `CTRL_IDLE` and any unspecified decode). So **`ready` is not asserted during `CTRL_DATA_LOAD` reads** or during idle—only during explicit write-load or explicit read modes with valid address.

---

## 6) Module I/O Tables with Implementing Logic

The following tables match the ports in RTL; the **Implementing logic** column ties each port to `assign` / `always_ff` / `` `comb`` behavior described above.

### `parallel_interface`

| Port | Dir | Width | Description |
|---|---|---:|---|
| `clk` | in | 1 | Clock (unused in module body) |
| `reset` | in | 1 | Active-high reset (unused in module body) |
| `host_data` | in | 32 | `[31:24]` payload, `[23:0]` one-hot tail |
| `host_cmd` | in | 3 | Command |
| `valid` | out | 1 | Legal transaction qualifier |
| `data` | out | 8 | `host_data[31:24]` |
| `address` | out | 16 | `ann_tail_to_parallel_addr(host_data[23:0])` |
| `cmd` | out | 3 | `host_cmd` |

**Implementing logic:** All outputs are **continuous assignments**. `valid` uses **four one-hot predicates** ANDed together plus `host_cmd != CMD_HIZ`.

### `ann_controller`

| Port | Dir | Width | Description |
|---|---|---:|---|
| `clk`, `rst_n` | in | 1 | Clock / async low reset |
| `valid`, `data`, `address`, `cmd` | in | — | PI-side decoded bus |
| `ann_reset` | out | 1 | Asserted in `S_RESET` combinational default |
| `op_done` | in | 1 | Core handshake |
| `ann_core_word` | out | 32 | Packed output |
| `pulses` | out | 3 | Pulse mode |
| `weight_read_data` | in | 4 | Verify readback |
| `buf_*`, `buf_data_out`, `buf_ready`, `buf_data` | — | Buffer interface |
| `busy` | out | 1 | Busy |

**Implementing logic:**

- **Registered:** main `state`, `prog_state`, `address_reg`, `data_reg`, counters (`pulse_cnt`, `data_count`, `row_count`, `bit_count`, `verify_pulse_idx`, `retry_cnt`, `prog_retry_cnt`, …) in `always_ff`.
- **Combinational FSM:** large `` `comb`` block for `next_state`, buffer controls, `pulses`, `ann_core_word` packing path (via separate `always_comb` for `data_byte_for_ann`).
- **`weight_read_data`:** compared in VERIFY; updates retry registers at clock edge in VERIFY_CHECK conditions.

### `input_buffer`

| Port | Dir | Width | Description |
|---|---|---:|---|
| `clk`, `rst_n` | in | 1 | Clock / reset |
| `data_in` | in | 8 | Write data |
| `ready` | out | 1 | Mode/address-qualified ready |
| `reg_ctrl`, `buf_read_write`, `buf_reg_add`, `bit_sel` | in | — | Control |
| `buf_data` | out | 8 | Byte read |
| `D0..D7` | out | 1 | Bit-serial lanes |

**Implementing logic:** `write_en`/`read_en` from **assign**; `buffer_reg` in **always_ff**; `buf_data` and `D0..D7` and `ready` in **combinational** `` `comb`` blocks.

---

## 7) Addressing and Packing Conventions (Summary)

- **16-bit parallel field** (from PI or used inside controller after capture): `[15:10]` are not consumed by `parse_ann_address`; index fields are `address[9:8]` (block), `address[7:6]` (sub-block), `address[5:3]` (column id), `address[2:0]` (row id), per `controller_pkg`.
- **32-bit `ann_core_word`:** `[31:24]` payload byte from the multiplexed `data_byte_for_ann` path; `[23:0]` one-hot tail from those index fields via left-shift encoding in `host_addr_to_ann_addr_out`.

---

## 8) File Structure and File-Type Roles (Abbreviated)

- `source/*/*.sv` — RTL modules  
- `source/*/*_pkg.sv` — packages (functions, enums, parameters)  
- `source/common/macros.svh` — `comb` macro etc.  
- `verif/**/file_list/*.f` — compile ordering for `vlog -f`  
- `scripts/run_sim.py` — simulation automation  

---

## 9) Not Implemented / Not Evidenced in RTL Files Above

- No ANN computation core beyond what testbenches mock.  
- No physical metrics (area, power, timing closed loop).  
- **`weight_read_en` is driven but unused** in `controller.sv` as of the sources referenced.  
- **`parallel_interface` does not use `clk`/`reset` internally**; ports exist but have no behavior in-module.
