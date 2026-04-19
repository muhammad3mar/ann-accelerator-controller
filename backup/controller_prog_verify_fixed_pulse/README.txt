Archived: program-verify sweep with USE_WEIGHT_PULSE_LUT=0 (fixed PULSE_TOTAL_PROG for PROG_WRITE).

The active tree now defaults ann_controller to USE_WEIGHT_PULSE_LUT=1 and uses
controller_prog_verify_lut_tb as the compiled 640-weight sweep.

To restore this variant into verif/:
  - Copy the .sv and .do files back under verif/Controller/... (see paths in
    verif/Controller/file_list/controller_verif_list.f history).
  - Add ann_controller #(.USE_WEIGHT_PULSE_LUT(1'b0)) in the restored TB if the
    RTL default remains LUT-on.

Wave DO script uses hierarchy: /controller_prog_verify_tb_waves_tb/u_tb
