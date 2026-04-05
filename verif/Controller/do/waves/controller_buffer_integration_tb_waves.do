onerror { resume }
quietly WaveActivateNextPane {} 0

set TB /controller_buffer_integration_tb_waves_tb/u_tb

add wave -noupdate -divider {TB}
add wave -noupdate $TB/clk
add wave -noupdate $TB/rst_n
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
add wave -noupdate $TB/in_prog_core_phase
add wave -noupdate $TB/op_done_cnt
add wave -noupdate $TB/fd
add wave -noupdate $TB/pass_c
add wave -noupdate $TB/fail_c

add wave -noupdate -divider {DUT_ann_controller}
add wave -r $TB/dut/*

add wave -noupdate -divider {DUT_input_buffer}
add wave -r $TB/u_input_buffer/*

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
