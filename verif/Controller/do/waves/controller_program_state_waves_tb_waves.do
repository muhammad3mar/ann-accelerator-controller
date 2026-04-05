# Wrapper around controller_program_state_waves_tb — D0-D7 only under u_buf

onerror { resume }
quietly WaveActivateNextPane {} 0

set TB /controller_program_state_waves_tb_waves_tb/u_tb

add wave -noupdate -divider {TB}
add wave -noupdate $TB/clk
add wave -noupdate $TB/rst_n
add wave -noupdate $TB/reset
add wave -noupdate $TB/host_data
add wave -noupdate $TB/host_cmd
add wave -noupdate $TB/valid
add wave -noupdate $TB/data
add wave -noupdate $TB/address
add wave -noupdate $TB/cmd
add wave -noupdate $TB/ann_reset
add wave -noupdate $TB/op_done
add wave -noupdate $TB/busy
add wave -noupdate $TB/ann_core_word
add wave -noupdate $TB/pulses
add wave -noupdate $TB/buf_reg_add
add wave -noupdate $TB/buf_reg_ctrl
add wave -noupdate $TB/buf_read_write
add wave -noupdate $TB/buf_bit_sel
add wave -noupdate $TB/buf_data_out
add wave -noupdate $TB/buf_data
add wave -noupdate $TB/buf_ready
add wave -noupdate $TB/tb_transaction_id
add wave -noupdate $TB/tb_scenario
add wave -noupdate $TB/inject_expected_weight
add wave -noupdate $TB/weight_read_data_mock
add wave -noupdate $TB/actual_from_ann
add wave -noupdate $TB/dec_blk
add wave -noupdate $TB/dec_sb
add wave -noupdate $TB/dec_row
add wave -noupdate $TB/dec_col
add wave -noupdate $TB/verify_cycle_cnt
add wave -noupdate $TB/was_in_verify
add wave -noupdate $TB/in_verify_phase
add wave -noupdate $TB/arm_stats_pulse
add wave -noupdate $TB/in_prog_core_phase
add wave -noupdate $TB/op_done_cnt
add wave -noupdate $TB/scen_prog_bursts
add wave -noupdate $TB/scen_erase_pulse_cycles
add wave -noupdate $TB/scen_s_read_entry
add wave -noupdate $TB/prev_prog_write
add wave -noupdate $TB/prev_dut_read
add wave -noupdate $TB/prog_in_write
add wave -noupdate $TB/prog_write_rise
add wave -noupdate $TB/dut_in_read
add wave -noupdate $TB/read_rise

add wave -noupdate -divider {DUT_parallel_interface}
add wave -r $TB/u_pi/*

add wave -noupdate -divider {DUT_ann_controller}
add wave -r $TB/dut/*

add wave -noupdate -divider {DUT_input_buffer}
add wave -r $TB/u_buf/*

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
