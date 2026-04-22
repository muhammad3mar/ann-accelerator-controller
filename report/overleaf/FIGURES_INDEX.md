# Figures Index

This file lists every figure placeholder referenced by the LaTeX
sources in `report/overleaf/`. When you create the image for a given
figure, save it with **exactly** the filename shown in the
**Filename** column (keep the extension consistent —
either `.pdf` or `.png`, whichever you produce). Drop every finished
image into `report/overleaf/figures/` and the project will compile
unchanged.

- Preferred format: **PDF** (vector, smaller, scalable).
- PNG is acceptable for ModelSim waveform captures.
- All LaTeX `\includegraphics` calls omit the extension, so either
  `.pdf` or `.png` works.

Filenames are stable — the `\label{fig:...}` in the LaTeX mirrors the
filename so that cross-references remain consistent.

---

## Main-Body Figures

| # | Filename (no extension) | Location (.tex) | Ch / Sec | One-line description |
|---|---|---|---|---|
| 1 | `fig_top_level_block_diagram` | `sections/03_architecture.tex` | Ch. 3, Sec. 3.1 | Host → `parallel_interface` → `ann_controller` → `input_buffer` → ANN Core. Label every signal (`host_data`, `host_cmd`, `valid`, `data`, `address`, `cmd`, `ann_core_word`, `pulses`, `op_done`, `weight_read_data`, `buf_*`, `D0..D7`, `busy`) with its width. |
| 2 | `fig_ann_core_word_layout` | `sections/03_architecture.tex` | Ch. 3, Sec. 3.3 | Pictorial 32-bit bit layout: `[31:24]` payload byte, `[23:20]` PE one-hot (4b), `[19:16]` SA one-hot (4b), `[15:8]` col one-hot (8b), `[7:0]` row one-hot (8b). Keep field boundaries clearly marked. |
| 3 | `fig_parallel_addr_layout` | `sections/03_architecture.tex` | Ch. 3, Sec. 3.3 | 16-bit packed `address`: `[15:10]` reserved, `[9:8]` blk, `[7:6]` sb, `[5:3]` col_id, `[2:0]` row_id. |
| 4 | `fig_main_fsm_body` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.5 | Simplified main FSM of `ann_controller` (9 states) showing only the high-level transitions. Detailed version is `fig_app_main_fsm_full`. |
| 5 | `fig_prog_subfsm_body` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.6 | PROG sub-FSM flow `PROG_HIZ → PROG_SELECT → PROG_WRITE → PROG_WAIT_ACK → PROG_COMPLETE` with `op_done` / `pulse_done` conditions. |
| 6 | `fig_verify_subfsm_body` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.7 | VERIFY sub-FSM with its three `VERIFY_CHECK` outcomes (match → DONE, under → re-PROG, over → ERASE). |
| 7 | `fig_erase_subfsm_body` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.8 | ERASE sub-FSM flow `ERASE_HIZ → ERASE_SELECT → ERASE_PULSE → ERASE_WAIT_ACK → ERASE_COMPLETE` with the `erase_from_host` / `retry_cnt` branching. |
| 8 | `fig_pulse_train_model` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.9 | Standard `pulse_train_total(T, N, G)` waveform: N bursts of T active cycles separated by G HIZ gaps. |
| 9 | `fig_lut_macro_repeat` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.9 | LUT-based macro-repeat structure: Rlut copies of the inner macro separated by `PULSE_GAP` cycles. |
| 10 | `fig_inference_dataflow` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.10 | Inference dataflow: `S_COLLECT_DATA` (8 pixel writes) → `S_COMPUTE` (bit-serial D0..D7 with bit_count stepping) → `S_RESULT` → `S_IDLE`. |
| 11 | `fig_recovery_loop_conceptual` | `sections/04_rtl_design.tex` | Ch. 4, Sec. 4.2.11 | Conceptual PROG → VERIFY → {DONE | re-PROG | ERASE → PROG} recovery loop summary. |
| 12 | `fig_testbench_stack` | `sections/05_verification.tex` | Ch. 5, Sec. 5.1 | Testbench stack: PI + controller + buffer DUTs, shadow matrix `ann_weight_matrix`, and `op_done` generator, showing how `weight_read_data_mock` feeds the DUT. |
| 13 | `fig_fault_injection_window` | `sections/05_verification.tex` | Ch. 5, Sec. 5.4 | Timing of fault-injection gating: `busy`, `pulses` (READ/HIZ), `in_verify_phase`, `verify_cycle_cnt ≤ 1` window. Show when the mock overrides `weight_read_data_mock`. |

---

## Appendix Figures

| # | Filename (no extension) | Location (.tex) | Appendix | One-line description |
|---|---|---|---|---|
| 14 | `fig_app_main_fsm_full` | `appendices/A_fsm_diagrams.tex` | App. A.1 | Fully-labeled main FSM with every transition condition (see the caption text in `A_fsm_diagrams.tex` for the exact labels). Rendered large enough to fill most of an A4 page. |
| 15 | `fig_app_prog_subfsm_full` | `appendices/A_fsm_diagrams.tex` | App. A.2 | Fully-labeled PROG sub-FSM. |
| 16 | `fig_app_verify_subfsm_full` | `appendices/A_fsm_diagrams.tex` | App. A.3 | Fully-labeled VERIFY sub-FSM, showing the three `VERIFY_CHECK` branches with their complete conditions (match, under + retries available, under + retries exhausted, over). |
| 17 | `fig_app_erase_subfsm_full` | `appendices/A_fsm_diagrams.tex` | App. A.4 | Fully-labeled ERASE sub-FSM, including the three `ERASE_COMPLETE` exit branches driven by `erase_from_host` and `retry_cnt`. |
| 18 | `fig_app_address_roundtrip` | `appendices/C_addressing_packing.tex` | App. C.4 | Address round-trip diagram: host tail → PI decode → `address_reg` → `parse_ann_address` → `pack_ann_core_word` → outbound `ann_core_word` tail. Show each 16/24/32-bit intermediate. |
| 19 | `fig_app_pulse_cycle_waveform` | `appendices/D_pulse_timing.tex` | App. D.5 | Conceptual LUT-based PROG_WRITE waveform: `pulses`, `pulse_cnt`, `pulse_done`, `prog_state` over one full `Rlut`-macro cycle. |
| 20 | `fig_app_wave_prog_verify_ok` | `appendices/F_waveforms.tex` | App. F.1 | ModelSim capture of a clean PROG → VERIFY (no injection) from `controller_prog_verify_lut_10w_tb_waves_tb`. |
| 21 | `fig_app_wave_under_injection` | `appendices/F_waveforms.tex` | App. F.2 | ModelSim capture of an under-programmed injection leading to re-PROG. |
| 22 | `fig_app_wave_over_injection` | `appendices/F_waveforms.tex` | App. F.3 | ModelSim capture of an over-programmed injection leading to ERASE → PROG retry. |
| 23 | `fig_app_wave_inf_compute` | `appendices/F_waveforms.tex` | App. F.4 | ModelSim capture of the inference path (collect + compute + result) from `controller_inf_buffer_flow_tb_waves_tb`. |
| 24 | `fig_app_wave_integration` | `appendices/F_waveforms.tex` | App. F.5 | ModelSim capture of several transactions back-to-back from `parallel_interface_controller_integration_tb_waves_tb`. |

---

## How to Capture a ModelSim Waveform (Appendix F)

1. Run the corresponding wave wrapper testbench with `scripts/run_sim.py` and `--do-file`.
   Example:
   ```
   python scripts/run_sim.py sim -m Controller \
       -tb controller_prog_verify_lut_10w_tb_waves_tb \
       --do-file verif/Controller/do/waves/controller_prog_verify_lut_10w_tb_waves.do
   ```
2. In the ModelSim wave window, zoom to the relevant time range.
3. File → Export → Waveform (PDF or PNG). Save directly as the
   filename listed above, into `report/overleaf/figures/`.

---

## Suggested Tools for the Non-Waveform Figures

- TikZ inside LaTeX (already configured in `preamble.tex`). Good for
  the bit-layout diagrams (`fig_ann_core_word_layout`,
  `fig_parallel_addr_layout`) and the dataflow diagrams.
- **draw.io** (diagrams.net) or **Lucidchart** for the block diagrams
  (`fig_top_level_block_diagram`, `fig_testbench_stack`,
  `fig_inference_dataflow`, `fig_recovery_loop_conceptual`). Export as
  PDF.
- **Mermaid** (renderable to PDF via Mermaid CLI or online) for the
  FSM diagrams, starting from the Mermaid source in
  `report/Context/2_FSM_Design/CONTROLLER_FSM_AND_CONTROL_LOGIC.md`.
  Export as PDF.

---

## Quick Compile Sanity Check

With every image filename above present in `figures/`, the project
should compile cleanly with the standard Overleaf recipe:

```
pdflatex  main.tex
biber     main
pdflatex  main.tex
pdflatex  main.tex
```

If a figure is not yet ready, you can either
1. insert a temporary placeholder PDF/PNG with that exact filename, or
2. comment out the corresponding `\includegraphics{...}` line
   temporarily. The `\label{fig:...}` will then still exist but
   `\Cref{fig:...}` to an unresolved figure will produce a `??` in the
   PDF, which is easy to spot.

---

_Total figures: 13 main-body + 11 appendix = **24** placeholders._
