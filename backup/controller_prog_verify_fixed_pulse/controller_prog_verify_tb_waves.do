onerror { resume }
quietly WaveActivateNextPane {} 0

set TB /controller_prog_verify_tb_waves_tb/u_tb

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
add wave -noupdate $TB/ann_address
add wave -noupdate $TB/pulses
add wave -noupdate $TB/buf_reg_add
add wave -noupdate $TB/buf_reg_ctrl
add wave -noupdate $TB/buf_read_write
add wave -noupdate $TB/buf_bit_sel
add wave -noupdate $TB/buf_data_out
add wave -noupdate $TB/buf_data
add wave -noupdate $TB/buf_ready
add wave -noupdate $TB/weight_read_data_mock
add wave -noupdate $TB/actual_from_ann
add wave -noupdate $TB/dec_blk
add wave -noupdate $TB/dec_sb
add wave -noupdate $TB/dec_row
add wave -noupdate $TB/dec_col
add wave -noupdate $TB/current_weight_idx
add wave -noupdate $TB/verify_cycle_cnt
add wave -noupdate $TB/was_in_verify
add wave -noupdate $TB/in_verify_phase
add wave -noupdate $TB/in_prog_core_phase
add wave -noupdate $TB/op_done_cnt
add wave -noupdate $TB/prev_pulses
add wave -noupdate $TB/prev_busy
add wave -noupdate $TB/prog_count
add wave -noupdate $TB/verify_count
add wave -noupdate $TB/erase_count
add wave -noupdate $TB/current_addr
add wave -noupdate $TB/fd
add wave -noupdate $TB/errs
add wave -noupdate $TB/erase_phase_count
add wave -noupdate $TB/reprog_retry_count
add wave -noupdate $TB/weights_logged
add wave -noupdate $TB/saw_idle

add wave -noupdate -divider {DUT_parallel_interface}
add wave -r $TB/u_pi/*

add wave -noupdate -divider {DUT_ann_controller}
add wave -r $TB/dut/*

add wave -noupdate -divider {DUT_input_buffer}
add wave -r $TB/u_buf/*

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
