//------------------------------------------------------------------------------
// Parallel Interface Package 
//------------------------------------------------------------------------------

package parallel_interface_pkg;

    //--------------------------------------------------------------------------
    // Command Signal Definitions
    //--------------------------------------------------------------------------
    localparam int CMD_WIDTH = 2;
    
    typedef enum logic [1:0] {
        CMD_READ  = 2'b00,  // Read weight value from memristor at specified address
        CMD_PROG  = 2'b01,  // Program weight at specified address
        CMD_ERASE = 2'b10,  // Erase weight at specified address
        CMD_INF   = 2'b11   // Inference/classification - apply input data for matrix multiplication
    } cmd_t;

    //--------------------------------------------------------------------------
    // Address Field Definitions
    //--------------------------------------------------------------------------
    // 32-bit host signal layout:
    //   [31:26] = empty (reserved, 6 bits)
    //   [25:24] = cmd (2 bits)
    //   [23:8]  = address (16 bits)
    //   [7:0]   = data (8 bits)
    //
    // Address field [23:8] (16 bits) breakdown:
    //   [23:18] = empty[15:10] (reserved, 6 bits)
    //   [17:16] = PE/matrix[9:8] → block_id (2 bits)
    //   [15:14] = sub-array[7:6] → sub_block_id (2 bits)
    //   [13:11] = column[5:3] → col_id (3 bits)
    //   [10:8]  = row[2:0] → row_id (3 bits)
    //
    // When extracted from host_data[23:8], internally treated as address[15:0]:
    //   address[15:10] = reserved (6 bits)
    //   address[9:8]   = block_id (2 bits) - PE/matrix
    //   address[7:6]   = sub_block_id (2 bits) - sub-array
    //   address[5:3]   = col_id (3 bits) - column
    //   address[2:0]   = row_id (3 bits) - row
    //--------------------------------------------------------------------------
    
    //--------------------------------------------------------------------------
    // Helper Functions for Address Extraction
    //--------------------------------------------------------------------------
    
    // Extract data field from 32-bit host signal
    function automatic logic [7:0] extract_data(logic [31:0] host_data);
        return host_data[7:0];
    endfunction
    
    // Extract address field from 32-bit host signal (bits [23:8])
    function automatic logic [15:0] extract_address(logic [31:0] host_data);
        return host_data[23:8];
    endfunction
    
    // Extract command field from 32-bit host signal (bits [25:24])
    function automatic logic [1:0] extract_cmd(logic [31:0] host_data);
        return host_data[25:24];
    endfunction

endpackage


