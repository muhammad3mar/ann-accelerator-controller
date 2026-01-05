//------------------------------------------------------------------------------
// Parallel Interface Package 
//------------------------------------------------------------------------------

package parallel_interface_pkg;

    //--------------------------------------------------------------------------
    // Command Signal Definitions (Data Type Indicators)
    //--------------------------------------------------------------------------
    localparam int CMD_WIDTH = 2;
    
    typedef enum logic [1:0] {
        CMD_WEIGHTS       = 2'b00,  // Data type: weights (for programming)
        CMD_CLASSIFY_DATA = 2'b01   // Data type: classification data (for inference)
        // 2'b10, 2'b11 reserved
    } cmd_t;

endpackage


