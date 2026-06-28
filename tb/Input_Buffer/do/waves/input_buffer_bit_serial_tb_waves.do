# TB: 8 captured data_in lanes � after first load = buffer 0�7; after second load same lanes = buffer 8�15.
# Added helper waves: load trigger + 8-pixel counter before bit-serial starts.
# DUT: clk/rst + bit-serial only.
# Top: input_buffer_bit_serial_tb_waves_tb

onerror { resume }
quietly WaveActivateNextPane {} 0

set dut /input_buffer_bit_serial_tb_waves_tb/u_tb/dut
set tb  /input_buffer_bit_serial_tb_waves_tb/u_tb

add wave -noupdate -divider {DUT � clock / reset}
add wave -noupdate ${dut}/clk
add wave -noupdate ${dut}/rst_n

add wave -noupdate -divider {TB_command_like_inputs}
add wave -noupdate -radix hex ${tb}/data_in
add wave -noupdate -radix unsigned ${tb}/reg_ctrl
add wave -noupdate ${tb}/buf_read_write
add wave -noupdate -radix unsigned ${tb}/buf_reg_add

add wave -noupdate -divider {TB � load trigger + 8-pixel counter}
add wave -noupdate ${tb}/tb_pi_load_trigger
add wave -noupdate -radix unsigned ${tb}/tb_load_pixel_count

add wave -noupdate -divider {TB � captured data_in 0-7 (then 8-15 on same 8 traces after 2nd load)}
add wave -noupdate -radix hex ${tb}/tb_captured_din_0
add wave -noupdate -radix hex ${tb}/tb_captured_din_1
add wave -noupdate -radix hex ${tb}/tb_captured_din_2
add wave -noupdate -radix hex ${tb}/tb_captured_din_3
add wave -noupdate -radix hex ${tb}/tb_captured_din_4
add wave -noupdate -radix hex ${tb}/tb_captured_din_5
add wave -noupdate -radix hex ${tb}/tb_captured_din_6
add wave -noupdate -radix hex ${tb}/tb_captured_din_7

add wave -noupdate -divider {DUT bit-serial activity (D0-D7, pulses-equivalent here)}
add wave -noupdate -radix unsigned ${dut}/bit_sel
add wave -noupdate ${dut}/D0
add wave -noupdate ${dut}/D1
add wave -noupdate ${dut}/D2
add wave -noupdate ${dut}/D3
add wave -noupdate ${dut}/D4
add wave -noupdate ${dut}/D5
add wave -noupdate ${dut}/D6
add wave -noupdate ${dut}/D7

configure wave -namecolwidth 300
configure wave -valuecolwidth 100
run -all
