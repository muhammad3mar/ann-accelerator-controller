`timescale 1ns/1ps

import controller_pkg::*;

module controller_host_erase_tb_waves_tb;
    controller_host_erase_tb u_tb ();

    // Mirrors of controller_pkg pulse params (constants) for waveform viewer
    wire [31:0] pkg_TREAD            = 32'(TREAD);
    wire [31:0] pkg_PULSE_NUM_READ   = 32'(PULSE_NUM_READ);
    wire [31:0] pkg_TPROG            = 32'(TPROG);
    wire [31:0] pkg_PULSE_NUM_PROG   = 32'(PULSE_NUM_PROG);
    wire [31:0] pkg_TERASE           = 32'(TERASE);
    wire [31:0] pkg_PULSE_NUM_ERASE  = 32'(PULSE_NUM_ERASE);
    wire [31:0] pkg_TINF             = 32'(TINF);
    wire [31:0] pkg_PULSE_NUM_INF    = 32'(PULSE_NUM_INF);
endmodule
