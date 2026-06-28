//------------------------------------------------------------------------------
// Controller Verification File List
//------------------------------------------------------------------------------
// This file lists all verification files for the Controller module
//------------------------------------------------------------------------------

// Include RTL files first
-f tb/Controller/file_list/controller_list.f

// Testbench files
tb/Controller/tb/regular/prog/controller_addr_pulse_tb.sv
tb/Controller/tb/regular/prog/controller_prog_verify_lut_tb.sv
tb/Controller/tb/regular/prog/controller_prog_verify_lut_10w_tb.sv

tb/Controller/tb/parallel_interface_controller_integration_tb.sv
tb/Controller/tb/regular/erase/controller_host_erase_tb.sv
tb/Controller/tb/regular/inf/controller_inf_buffer_flow_tb.sv
tb/Controller/tb/regular/read/controller_host_read_reorder_tb.sv

// Wave wrapper testbenches
tb/Controller/tb/waves/prog/controller_prog_verify_lut_tb_waves_tb.sv
tb/Controller/tb/waves/prog/controller_prog_verify_lut_10w_tb_waves_tb.sv
tb/Controller/tb/waves/parallel_interface_controller_integration_tb_waves_tb.sv
tb/Controller/tb/waves/erase/controller_host_erase_tb_waves_tb.sv
tb/Controller/tb/waves/inf/controller_inf_buffer_flow_tb_waves_tb.sv
