//------------------------------------------------------------------------------
// Parallel Interface Module
//------------------------------------------------------------------------------
// Parses 32-bit host signal and forwards data, address, and command to controller
//
// Signal Layout (32-bit from host):
//   [31:26] = empty (reserved, 6 bits)
//   [25:24] = cmd (2 bits)
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
    output logic [1:0]      cmd         // Extracted 2-bit command
);

    //--------------------------------------------------------------------------
    // Parse 32-bit host signal into component fields
    //--------------------------------------------------------------------------
    assign data    = extract_data(host_data);     // bits [7:0]
    assign address = extract_address(host_data);  // bits [23:8]
    assign cmd     = extract_cmd(host_data);      // bits [25:24]

    //--------------------------------------------------------------------------
    // Valid signal generation
    //--------------------------------------------------------------------------
    // Valid is asserted when host_data contains a valid command (non-zero command field)
    logic [1:0] cmd_field;
    assign cmd_field = extract_cmd(host_data);
    
    always_comb begin
        // Valid when host_data has a non-zero command field
        // Command field [25:24] is valid for any value (00, 01, 10, 11)
        // Consider host_data valid if cmd field is present (can be extended with handshake)
        valid = (cmd_field != 2'b00 || host_data[7:0] != 8'b0 || host_data[23:8] != 16'b0) ? 1'b1 : 1'b0;
    end

endmodule

