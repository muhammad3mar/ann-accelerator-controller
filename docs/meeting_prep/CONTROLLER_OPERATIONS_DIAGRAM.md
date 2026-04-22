# Controller operations diagram

This document matches the main FSM and sub-FSMs in [`source/Controller/controller.sv`](../../source/Controller/controller.sv) as of the current RTL.

**Memristor-focused block diagrams** (program / verify / erase / read): [`../block_diagram/MEMRISTOR_FSMS.md`](../block_diagram/MEMRISTOR_FSMS.md).

## Command dispatch (from `S_IDLE`)

When `valid` is high:

| `cmd`       | Next main state   |
|------------|-------------------|
| `CMD_PROG` | `S_PROGRAM`       |
| `CMD_READ` | `S_READ`          |
| `CMD_ERASE`| `S_ERASE`         |
| `CMD_INF`  | `S_COLLECT_DATA`  |
| other      | stay `S_IDLE`     |

`CMD_HIZ` yields `valid == 0` at the parallel interface, so the controller never leaves `S_IDLE` for that “command.”

## Main state flow (high level)

```mermaid
flowchart TD
  subgraph idle [Idle]
    S_IDLE[S_IDLE]
  end

  subgraph progFlow [Program_and_verify]
    S_PROGRAM[S_PROGRAM]
    S_VERIFY[S_VERIFY]
  end

  subgraph eraseFlow [Erase]
    S_ERASE[S_ERASE]
  end

  subgraph readFlow [Host_read]
    S_READ[S_READ]
  end

  subgraph infFlow [Inference]
    S_COLLECT[S_COLLECT_DATA]
    S_COMPUTE[S_COMPUTE]
    S_RESULT[S_RESULT]
  end

  S_IDLE -->|CMD_PROG| S_PROGRAM
  S_IDLE -->|CMD_READ| S_READ
  S_IDLE -->|CMD_ERASE| S_ERASE
  S_IDLE -->|CMD_INF| S_COLLECT

  S_PROGRAM -->|prog_complete| S_VERIFY

  S_VERIFY -->|VERIFY_DONE| S_IDLE
  S_VERIFY -->|reprogram or max reprog| S_PROGRAM
  S_VERIFY -->|over_prog or max reprog exhausted| S_ERASE

  S_ERASE -->|ERASE_COMPLETE retry_cnt less 3| S_PROGRAM
  S_ERASE -->|ERASE_COMPLETE retry_cnt equals 3| S_IDLE

  S_READ -->|pulse_done| S_IDLE

  S_COLLECT -->|8 pixels accepted valid| S_COMPUTE
  S_COLLECT -->|wait valid| S_COLLECT

  S_COMPUTE -->|pulse_done| S_RESULT
  S_RESULT --> S_IDLE
```

Notes:

- **PROG→VERIFY** is unconditional after `PROG_COMPLETE` for the direct-address flow.
- **VERIFY** may loop to **PROGRAM** (under-programmed, within retry limit) or to **ERASE** (over-programmed, or reprog limit exceeded).
- **ERASE** returns to **PROGRAM** for another attempt while `retry_cnt < 3` after `ERASE_COMPLETE`; otherwise **IDLE** with error semantics in RTL.
- **COLLECT_DATA** stays in place until `valid`; the eighth pixel in a row triggers **COMPUTE** (combinational next_state when `data_count == 7` and `valid`).

## Programming sub-FSM (`S_PROGRAM` only)

```mermaid
stateDiagram-v2
  [*] --> PROG_HIZ
  PROG_HIZ --> PROG_SELECT
  PROG_SELECT --> PROG_SELECT: until op_done
  PROG_SELECT --> PROG_WRITE: op_done
  PROG_WRITE --> PROG_WRITE: until pulse_done
  PROG_WRITE --> PROG_WAIT_ACK: pulse_done
  PROG_WAIT_ACK --> PROG_WAIT_ACK: until op_done
  PROG_WAIT_ACK --> PROG_COMPLETE: op_done
  PROG_COMPLETE --> PROG_HIZ: via transition to S_VERIFY
```

After `PROG_COMPLETE`, the **main** state goes to `S_VERIFY` and `next_prog_state` resets to `PROG_HIZ` for a possible later program phase.

## Verify sub-FSM (`S_VERIFY`)

```mermaid
stateDiagram-v2
  [*] --> VERIFY_IDLE
  VERIFY_IDLE --> VERIFY_WAIT: PULSE_TOTAL_READ greater 1
  VERIFY_IDLE --> VERIFY_CHECK: PULSE_TOTAL_READ le 1
  VERIFY_WAIT --> VERIFY_WAIT: verify_pulse_idx not last
  VERIFY_WAIT --> VERIFY_CHECK: read pulse train done
  VERIFY_CHECK --> VERIFY_DONE: read equals expected
  VERIFY_CHECK --> VERIFY_IDLE: mismatch paths via S_PROGRAM or S_ERASE
  VERIFY_DONE --> [*]: main state to S_IDLE
```

## Erase sub-FSM (`S_ERASE`)

```mermaid
stateDiagram-v2
  [*] --> ERASE_HIZ
  ERASE_HIZ --> ERASE_SELECT
  ERASE_SELECT --> ERASE_SELECT: until op_done
  ERASE_SELECT --> ERASE_PULSE: op_done
  ERASE_PULSE --> ERASE_PULSE: until pulse_done
  ERASE_PULSE --> ERASE_WAIT_ACK: pulse_done
  ERASE_WAIT_ACK --> ERASE_WAIT_ACK: until op_done
  ERASE_WAIT_ACK --> ERASE_COMPLETE: op_done
  ERASE_COMPLETE --> [*]: main state to S_PROGRAM or S_IDLE
```

## Pulse and `ann_core_word` summary

- **`ann_core_word`:** For non-idle states, `{data_byte_for_ann, one_hot_tail}` via `pack_ann_core_word` (see RTL). In `S_COLLECT_DATA`, the data byte comes from **live** `data`; in `S_PROGRAM`/`S_VERIFY`/`S_READ`/`S_ERASE`, from **registered** `data_reg`.
- **`pulses`:** PROG during `PROG_WRITE`; READ during `S_READ` and verify read/wait; ERASE during `ERASE_PULSE`; INF during `S_COMPUTE`. `op_done` from the core advances `PROG_SELECT`→`PROG_WRITE`, `PROG_WAIT_ACK`→`PROG_COMPLETE`, `ERASE_SELECT`→`ERASE_PULSE`, and `ERASE_WAIT_ACK`→`ERASE_COMPLETE`.

Parameter names and cycle counts: [`controller_pkg`](../../source/Controller/controller_pkg.sv) (`TREAD`, `TPROG`, `TERASE`, `TINF`, pulse totals, `MAX_PROG_RETRIES`).
