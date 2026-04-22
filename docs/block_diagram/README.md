# Block diagrams (memristor / IMC control)

Diagrams in this folder describe the **controller FSMs** that interact with the memristor array: program, verify readback, erase, and host read.

| File | Contents |
|------|-----------|
| [MEMRISTOR_FSMS.md](MEMRISTOR_FSMS.md) | Mermaid state/flow diagrams aligned with current RTL (`ann_controller`) |

RTL source of truth: [`source/Controller/controller.sv`](../../source/Controller/controller.sv), types in [`source/Controller/controller_pkg.sv`](../../source/Controller/controller_pkg.sv).

A broader operations view (including inference) lives in [`../meeting_prep/CONTROLLER_OPERATIONS_DIAGRAM.md`](../meeting_prep/CONTROLLER_OPERATIONS_DIAGRAM.md).
