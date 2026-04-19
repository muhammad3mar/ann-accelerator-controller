onerror { resume }
quietly WaveActivateNextPane {} 0

set TB /controller_host_erase_tb_waves_tb/u_tb

add wave -noupdate -divider {TB}
add wave -noupdate $TB/clk
add wave -noupdate $TB/rst_n
add wave -noupdate $TB/reset
add wave -noupdate $TB/host_data
add wave -noupdate $TB/host_cmd
add wave -noupdate $TB/valid
add wave -noupdate $TB/pi_data
add wave -noupdate $TB/address
add wave -noupdate $TB/cmd
add wave -noupdate $TB/ann_reset
add wave -noupdate $TB/op_done
add wave -noupdate $TB/busy
add wave -noupdate $TB/ann_core_word
add wave -noupdate $TB/pulses
add wave -noupdate $TB/buf_reg_ctrl
add wave -noupdate $TB/buf_read_write
add wave -noupdate $TB/prev_erase_state
add wave -noupdate $TB/idx_A_b
add wave -noupdate $TB/idx_A_sb
add wave -noupdate $TB/idx_A_r
add wave -noupdate $TB/idx_A_c

add wave -noupdate -divider {DUT_FSM}
add wave -noupdate $TB/dut/state
add wave -noupdate $TB/dut/erase_state

add wave -noupdate -divider {DUT_ann_controller}
add wave -r $TB/dut/*

add wave -noupdate -divider {DUT_parallel_interface}
add wave -r $TB/u_pi/*

add wave -noupdate -divider {DUT_input_buffer}
add wave -r $TB/u_buf/*

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
