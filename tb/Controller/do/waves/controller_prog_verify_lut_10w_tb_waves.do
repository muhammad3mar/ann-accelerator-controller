onerror { resume }
quietly WaveActivateNextPane {} 0

# Same signal set as controller_prog_verify_lut_tb_waves.do; TB is the 10-weight compact bench.
set PKG /controller_prog_verify_lut_10w_tb_waves_tb
set TB  $PKG/u_tb
set DUT $TB/dut

add wave -noupdate -divider {TB_clock_reset}
add wave -noupdate $TB/clk
add wave -noupdate $TB/rst_n

add wave -noupdate -divider {TB_command_boundary}
add wave -noupdate -radix hex $TB/host_data
add wave -noupdate -radix binary $TB/cmd
add wave -noupdate -radix hex $TB/data
add wave -noupdate -radix hex $TB/address
add wave -noupdate $TB/busy
add wave -noupdate $TB/op_done

add wave -noupdate -divider {TB_verify_three_cases}
add wave -noupdate -radix unsigned $TB/weight_read_data_mock
add wave -noupdate -radix unsigned $DUT/expected_weight

add wave -noupdate -divider {DUT_pulse_mode_ann_core}
add wave -noupdate -radix binary $TB/pulses
add wave -noupdate -radix binary $TB/ann_address

add wave -noupdate -divider {DUT_main_FSM}
add wave -noupdate -radix symbolic $DUT/state

add wave -noupdate -divider {DUT_prog_subfsm}
add wave -noupdate -radix symbolic $DUT/prog_state

add wave -noupdate -divider {DUT_verify_subfsm}
add wave -noupdate -radix symbolic $DUT/verify_state

add wave -noupdate -divider {DUT_erase_subfsm}
add wave -noupdate -radix symbolic $DUT/erase_state
add wave -noupdate -radix binary $DUT/erase_failure_flag

add wave -noupdate -divider {DUT_PROG_pulse_timing_and_LUT}
add wave -noupdate -radix unsigned $DUT/lut_entry_expected_weight
add wave -noupdate -radix unsigned $DUT/prog_retry_cnt
add wave -noupdate -label erase_retry_cnt -radix unsigned $DUT/retry_cnt
add wave -noupdate -radix unsigned $DUT/pulse_cnt
add wave -noupdate -radix unsigned $DUT/pulse_total

add wave -noupdate -divider {controller_pkg_pulse_params}
add wave -noupdate -decimal $PKG/pkg_TREAD
add wave -noupdate -decimal $PKG/pkg_PULSE_NUM_READ
add wave -noupdate -decimal $PKG/pkg_TPROG
add wave -noupdate -decimal $PKG/pkg_PULSE_NUM_PROG
add wave -noupdate -decimal $PKG/pkg_TERASE
add wave -noupdate -decimal $PKG/pkg_PULSE_NUM_ERASE
add wave -noupdate -decimal $PKG/pkg_TINF
add wave -noupdate -decimal $PKG/pkg_PULSE_NUM_INF

configure wave -namecolwidth 280
configure wave -valuecolwidth 100
run -all
