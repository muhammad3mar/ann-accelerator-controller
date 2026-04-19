//------------------------------------------------------------------------------
// Input Buffer Verification File List
//------------------------------------------------------------------------------
// This file lists all verification files for the Input Buffer module
//------------------------------------------------------------------------------

// Include RTL files first
-f verif/Input_Buffer/file_list/input_buffer_list.f

// Testbench files
verif/Input_Buffer/tb/input_buffer_bit_serial_tb.sv
verif/Input_Buffer/tb/input_buffer_reset_behavior_tb.sv
verif/Input_Buffer/tb/input_buffer_full_overwrite_tb.sv

// Wave wrapper testbenches
verif/Input_Buffer/tb/waves/input_buffer_bit_serial_tb_waves_tb.sv
verif/Input_Buffer/tb/waves/input_buffer_reset_behavior_tb_waves_tb.sv

