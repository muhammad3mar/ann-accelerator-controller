onerror { resume }
quietly WaveActivateNextPane {} 0

set TB /parallel_interface_controller_integration_tb_waves_tb/u_tb
set DUT $TB/dut

add wave -noupdate -divider {Clock_Reset}
add wave -noupdate $TB/clk
add wave -noupdate $TB/rst_n

add wave -noupdate -divider {Host_and_PI_decode}
add wave -noupdate -radix hex $TB/host_data
add wave -noupdate -radix binary $TB/host_cmd
add wave -noupdate $TB/valid
add wave -noupdate -radix binary $TB/cmd
add wave -noupdate -radix hex $TB/address
add wave -noupdate -radix hex $TB/pi_data

add wave -noupdate -divider {Controller_flow}
add wave -noupdate $TB/busy
add wave -noupdate $TB/op_done
add wave -noupdate -radix symbolic $DUT/state
add wave -noupdate -radix symbolic $DUT/prog_state
add wave -noupdate -radix symbolic $DUT/verify_state
add wave -noupdate -radix symbolic $DUT/erase_state

add wave -noupdate -divider {Pulses_and_ANN_word}
add wave -noupdate -radix binary $TB/pulses
add wave -noupdate -radix binary $TB/ann_core_word

configure wave -namecolwidth 260
configure wave -valuecolwidth 100
run -all
