//------------------------------------------------------------------------------
// Parallel Interface Module
//------------------------------------------------------------------------------
// Parses 32-bit host signal and forwards data, address, and command to controller
//
// Signal Layout (32-bit from host):
//   [31:27] = reserved (5 bits)
//   [26:24] = cmd (3 bits)
//   [23:8]  = address (16 bits)
//   [7:0]   = data (8 bits)
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
    input  logic [31:0]     host_data,  // 32-bit signal from host

    //======================================================================
    // Controller Interface
    //======================================================================
    output logic            valid,      // Valid command/data ready
    output logic [7:0]      data,       // Extracted 8-bit data
    output logic [15:0]     address,    // Extracted 16-bit address
    output logic [2:0]      cmd         // Extracted 3-bit command
);

    //--------------------------------------------------------------------------
    // Parse 32-bit host signal into component fields
    //--------------------------------------------------------------------------
    assign data    = extract_data(host_data);     // bits [7:0]
    assign address = extract_address(host_data);  // bits [23:8]
    assign cmd     = extract_cmd(host_data);      // bits [26:24]

    //--------------------------------------------------------------------------
    // Valid signal generation
    //--------------------------------------------------------------------------
    // Valid is asserted when host_data contains a valid command
    // CMD_HIZ (000) with no address/data is idle; other commands or non-zero data/address are valid
    logic [2:0] cmd_field;
    assign cmd_field = extract_cmd(host_data);
    
    always_comb begin
        // Valid when host_data has non-zero command (not HIZ) or non-zero data/address
        valid = (cmd_field != 3'b000 || host_data[7:0] != 8'b0 || host_data[23:8] != 16'b0) ? 1'b1 : 1'b0;
    end

endmodule

