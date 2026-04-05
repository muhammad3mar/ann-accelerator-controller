#------------------------------------------------------------------------------
# Wave setup for controller_program_state_waves_tb (ModelSim)
# Usage (from project root): vsim work.controller_program_state_waves_tb -do verif/Controller/do/controller_program_state_waves.do
# Interactive: waves load; batch: run -all exits when TB calls $finish.
#------------------------------------------------------------------------------

onerror { resume }

quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {TB top}
add wave -noupdate -format Logic /controller_program_state_waves_tb/clk
add wave -noupdate -format Logic /controller_program_state_waves_tb/rst_n
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/host_data
add wave -noupdate -format Logic /controller_program_state_waves_tb/valid
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/data
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/address
add wave -noupdate -format Literal -radix binary /controller_program_state_waves_tb/cmd
add wave -noupdate -format Logic /controller_program_state_waves_tb/busy
add wave -noupdate -format Literal -radix unsigned /controller_program_state_waves_tb/tb_transaction_id
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/tb_scenario
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/inject_expected_weight
add wave -noupdate -format Literal -radix binary /controller_program_state_waves_tb/pulses
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/ann_core_word
add wave -noupdate -format Literal -radix unsigned /controller_program_state_waves_tb/buf_reg_add
add wave -noupdate -format Literal -radix unsigned /controller_program_state_waves_tb/buf_reg_ctrl
add wave -noupdate -format Logic /controller_program_state_waves_tb/buf_read_write
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/buf_data
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/buf_data_out

add wave -noupdate -divider {DUT ann_controller}
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/state
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/next_state
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/prog_state
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/next_prog_state
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/verify_state
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/verify_next
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/erase_state
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/erase_next
add wave -noupdate -format Literal -radix unsigned /controller_program_state_waves_tb/dut/pulse_cnt
add wave -noupdate -format Literal -radix unsigned /controller_program_state_waves_tb/dut/pulse_total
add wave -noupdate -format Logic /controller_program_state_waves_tb/dut/pulse_done
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/address_reg
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/data_reg
add wave -noupdate -format Literal -radix hexadecimal /controller_program_state_waves_tb/dut/expected_weight

configure wave -namecolwidth 220
configure wave -valuecolwidth 80
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

run -all
</think>
Fixing a typo in the DO file.

<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>
StrReplace