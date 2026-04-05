//------------------------------------------------------------------------------
// Controller Verification File List
//------------------------------------------------------------------------------
// This file lists all verification files for the Controller module
//------------------------------------------------------------------------------

// Include RTL files first
-f verif/Controller/file_list/controller_list.f

// Testbench files
verif/Controller/tb/controller_weight_program_tb.sv
verif/Controller/tb/controller_addr_pulse_tb.sv
verif/Controller/tb/controller_prog_verify_tb.sv
verif/Controller/tb/controller_prog_verify_lut_tb.sv
verif/Controller/tb/controller_program_state_waves_tb.sv

verif/Controller/tb/ann_controller_unit_tb.sv
verif/Controller/tb/parallel_interface_controller_integration_tb.sv
verif/Controller/tb/controller_buffer_integration_tb.sv
verif/Controller/tb/controller_integration_smoke_tb.sv

// Wave wrapper testbenches
verif/Controller/tb/waves/controller_weight_program_tb_waves_tb.sv
verif/Controller/tb/waves/controller_addr_pulse_tb_waves_tb.sv
verif/Controller/tb/waves/controller_prog_verify_tb_waves_tb.sv
verif/Controller/tb/waves/controller_program_state_waves_tb_waves_tb.sv
verif/Controller/tb/waves/ann_controller_unit_tb_waves_tb.sv
verif/Controller/tb/waves/parallel_interface_controller_integration_tb_waves_tb.sv
verif/Controller/tb/waves/controller_buffer_integration_tb_waves_tb.sv
verif/Controller/tb/waves/controller_integration_smoke_tb_waves_tb.sv
