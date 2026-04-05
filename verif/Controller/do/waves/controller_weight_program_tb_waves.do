onerror { resume }
quietly WaveActivateNextPane {} 0

set TB /controller_weight_program_tb_waves_tb/u_tb

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
add wave -noupdate $TB/data_in
add wave -noupdate $TB/buf_ready
add wave -noupdate $TB/buf_reg_ctrl_dut
add wave -noupdate $TB/buf_reg_ctrl_tb
add wave -noupdate $TB/buf_reg_ctrl
add wave -noupdate $TB/buf_read_write_dut
add wave -noupdate $TB/buf_read_write_tb
add wave -noupdate $TB/buf_read_write
add wave -noupdate $TB/buf_reg_add_dut
add wave -noupdate $TB/buf_reg_add_tb
add wave -noupdate $TB/buf_reg_add
add wave -noupdate $TB/tb_control_buffer
add wave -noupdate $TB/buf_data
add wave -noupdate $TB/buf_bit_sel_dut
add wave -noupdate $TB/buf_data_out
add wave -noupdate $TB/weight_read_data_mock
add wave -noupdate $TB/dec_blk
add wave -noupdate $TB/dec_sb
add wave -noupdate $TB/dec_row
add wave -noupdate $TB/dec_col
add wave -noupdate $TB/reconstructed_weight_addr
add wave -noupdate $TB/weight_sel
add wave -noupdate $TB/weight_from_buffer
add wave -noupdate $TB/current_weight
add wave -noupdate $TB/in_prog_core_phase
add wave -noupdate $TB/in_prog_write_state
add wave -noupdate $TB/op_done_counter
add wave -noupdate $TB/weights_loaded
add wave -noupdate $TB/weights_programmed
add wave -noupdate $TB/current_weight_addr
add wave -noupdate $TB/weight_loading_done
add wave -noupdate $TB/weight_programming_done

add wave -noupdate -divider {DUT_parallel_interface}
add wave -r $TB/u_parallel_interface/*

add wave -noupdate -divider {DUT_ann_controller}
add wave -r $TB/dut/*

add wave -noupdate -divider {DUT_input_buffer}
add wave -r $TB/u_input_buffer/*

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
