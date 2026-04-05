# Wave: TB stimulus + DUT only (no duplicate D0-D7 at TB and dut)

onerror { resume }
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {TB}
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/clk
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/rst_n
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/data_in
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/reg_ctrl
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/buf_read_write
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/buf_reg_add
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/bit_sel
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/ready
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/buf_data
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/pass_count
add wave -noupdate /input_buffer_write_read_tb_waves_tb/u_tb/fail_count

add wave -noupdate -divider {DUT_input_buffer}
add wave -r /input_buffer_write_read_tb_waves_tb/u_tb/dut/*

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
