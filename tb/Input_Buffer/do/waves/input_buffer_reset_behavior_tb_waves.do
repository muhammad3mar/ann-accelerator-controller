# Wave: reset-focused visibility for Input Buffer
# Top: input_buffer_reset_behavior_tb_waves_tb

onerror { resume }
quietly WaveActivateNextPane {} 0

set dut /input_buffer_reset_behavior_tb_waves_tb/u_tb/dut
set tb  /input_buffer_reset_behavior_tb_waves_tb/u_tb

add wave -noupdate -divider {DUT clock/reset}
add wave -noupdate ${dut}/clk
add wave -noupdate ${dut}/rst_n

add wave -noupdate -divider {TB reset/load helpers}
add wave -noupdate ${tb}/tb_pi_load_trigger
add wave -noupdate -radix unsigned ${tb}/tb_load_pixel_count

add wave -noupdate -divider {DUT control/data}
add wave -noupdate -radix symbolic ${dut}/reg_ctrl
add wave -noupdate ${dut}/buf_read_write
add wave -noupdate -radix unsigned ${dut}/buf_reg_add
add wave -noupdate -radix unsigned ${dut}/bit_sel
add wave -noupdate -radix hex ${dut}/data_in
add wave -noupdate -radix hex ${dut}/buf_data
add wave -noupdate ${dut}/ready

add wave -noupdate -divider {DUT bit-serial outputs}
add wave -noupdate ${dut}/D0
add wave -noupdate ${dut}/D1
add wave -noupdate ${dut}/D2
add wave -noupdate ${dut}/D3
add wave -noupdate ${dut}/D4
add wave -noupdate ${dut}/D5
add wave -noupdate ${dut}/D6
add wave -noupdate ${dut}/D7

configure wave -namecolwidth 280
configure wave -valuecolwidth 100
run -all
