onerror { resume }
quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {TB}
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/clk
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/reset
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/host_data
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/host_cmd
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/valid
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/data
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/address
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/cmd
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/pass_count
add wave -noupdate /parallel_interface_valid_tb_waves_tb/u_tb/fail_count

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
