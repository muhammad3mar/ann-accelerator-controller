# Project B Report Foundation

This directory contains the report-ready Markdown documentation generated from the repository sources for the ANN Accelerator Controller project.

## Structure

- `1_Architecture/PROJECT_OVERVIEW_AND_ARCHITECTURE.md`
  - Project scope, module partitioning, interfaces, handshakes, and file organization.
- `2_FSM_Design/CONTROLLER_FSM_AND_CONTROL_LOGIC.md`
  - Main controller FSM and sub-FSMs with raw Mermaid state diagrams.
- `3_Verification/VERIFICATION_STRATEGY_AND_TEST_PLAN.md`
  - ModelSim verification strategy and complete testbench-by-testbench breakdown.
- `4_User_Guide/GETTING_STARTED_AND_EXECUTION_GUIDE.md`
  - Environment setup, compile/run commands, waveform flow, and output interpretation.
- `5_Analysis/ANALYSIS_LIMITATIONS_FUTURE_WORK_AND_TERMINOLOGY.md`
  - Design choices, limitations, future work, test-log conclusions, and terminology.

## Grounding Policy Used

- Every section is derived from the current codebase files under `source/`, `verif/`, `scripts/`, `docs/`, and `target/`.
- If functionality is not implemented or not evidenced in code/logs, it is explicitly labeled as not implemented / not evidenced.
