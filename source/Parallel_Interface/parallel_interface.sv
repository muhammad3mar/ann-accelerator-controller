//------------------------------------------------------------------------------
// Parallel Interface Module
//------------------------------------------------------------------------------
// Host presents the same 32-bit layout as ann_core_word:
//   host_data[31:24] = data byte
//   host_data[23:0]  = one-hot {PE, SA, col, row}
//
// Command is a separate synchronous input host_cmd[2:0] (parallel_interface_pkg::cmd_t).
// Decoded outputs match what ann_controller expects: data[7:0], address[15:0], cmd.
//------------------------------------------------------------------------------

`include "../common/macros.svh"

import parallel_interface_pkg::*;

module parallel_interface(
    //======================================================================
    // Global
    //======================================================================
    input  logic            clk,
    input  logic            reset,      // Active high reset

    //======================================================================
    // Host Interface
    //======================================================================
    input  logic [31:0]     host_data,  // ann_core_word format
    input  logic [2:0]      host_cmd,   // command (HIZ when idle / no transaction)

    //======================================================================
    // Controller Interface
    //======================================================================
    output logic            valid,      // Valid command/data ready
    output logic [7:0]      data,       // host_data[31:24]
    output logic [15:0]     address,    // decoded from host_data[23:0]
    output logic [2:0]      cmd         // host_cmd
);

    assign data    = host_data[31:24];
    assign address = ann_tail_to_parallel_addr(host_data[23:0]);
    assign cmd     = host_cmd;

    assign valid = (host_cmd != CMD_HIZ);

endmodule
