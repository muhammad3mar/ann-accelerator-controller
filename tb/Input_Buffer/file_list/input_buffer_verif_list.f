//------------------------------------------------------------------------------
// Input Buffer Verification File List
//------------------------------------------------------------------------------
// This file lists all verification files for the Input Buffer module
//------------------------------------------------------------------------------

// Include RTL files first
-f tb/Input_Buffer/file_list/input_buffer_list.f

// Testbench files
tb/Input_Buffer/tb/input_buffer_bit_serial_tb.sv
tb/Input_Buffer/tb/input_buffer_reset_behavior_tb.sv
tb/Input_Buffer/tb/input_buffer_full_overwrite_tb.sv

// Wave wrapper testbenches
tb/Input_Buffer/tb/waves/input_buffer_bit_serial_tb_waves_tb.sv
tb/Input_Buffer/tb/waves/input_buffer_reset_behavior_tb_waves_tb.sv

