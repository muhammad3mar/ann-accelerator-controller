//------------------------------------------------------------------------------
// Controller Package 
//------------------------------------------------------------------------------


package controller_pkg;

    //--------------------------------------------------------------------------
    // Import parallel interface package for command types
    //--------------------------------------------------------------------------
    import parallel_interface_pkg::*;

    //--------------------------------------------------------------------------
    // Controller FSM States
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE          = 3'd0,  // Idle state
        S_RESET         = 3'd1,  // Reset ANN core and buffer
        S_PROGRAM       = 3'd2,  // Program weights into ANN
        S_VERIFY        = 3'd3,  // Verify programmed weights
        S_ERASE         = 3'd4,  // Erase weights if needed
        S_READ          = 3'd5,  // Read data from ANN
        S_RESULT        = 3'd6   // Output classification results
    } controller_state_t;

    //--------------------------------------------------------------------------
    // ANN Architecture Constants
    //--------------------------------------------------------------------------
    
    localparam int NUM_BLOCKS        = 4;      
    localparam int NUM_SUB_BLOCKS    = 4;     
    localparam int SUB_BLOCK_ROWS    = 8;      
    localparam int SUB_BLOCK_COLS    = 8;      
    localparam int BLOCK_ROWS        = 16;     
    localparam int BLOCK_COLS        = 16;     
    
    // Total weight locations
    localparam int TOTAL_WEIGHT_LOCATIONS = NUM_BLOCKS * NUM_SUB_BLOCKS * SUB_BLOCK_ROWS * SUB_BLOCK_COLS;  // 1024

    //--------------------------------------------------------------------------
    // Address Bit Field Definitions
    //--------------------------------------------------------------------------
    // Weight address encoding (10 bits total):
    //   [9:8]   = block_id (0-3)
    //   [7:6]   = sub_block_id (0-3)
    //   [5:3]   = row within sub-block (0-7)
    //   [2:0]   = column within sub-block (0-7)
    //--------------------------------------------------------------------------
    localparam int WEIGHT_ADDR_WIDTH = 10;     // Total weight address width
    
    // Bit field positions
    localparam int BLOCK_ID_MSB       = 9;
    localparam int BLOCK_ID_LSB       = 8;
    localparam int SUB_BLOCK_ID_MSB   = 7;
    localparam int SUB_BLOCK_ID_LSB   = 6;
    localparam int ROW_ID_MSB         = 5;
    localparam int ROW_ID_LSB         = 3;
    localparam int COL_ID_MSB         = 2;
    localparam int COL_ID_LSB         = 0;
    
    // Bit widths for each field
    localparam int BLOCK_ID_WIDTH     = 2;     
    localparam int SUB_BLOCK_ID_WIDTH = 2;     
    localparam int ROW_ID_WIDTH       = 3;     
    localparam int COL_ID_WIDTH       = 3;     

    //--------------------------------------------------------------------------
    // Row/Column Selector Definitions
    //--------------------------------------------------------------------------
    // Row/Column Selector encoding (7 bits each):
    //   [6:5]   = block_id
    //   [4:3]   = sub_block_id
    //   [2:0]   = row/column within sub-block
    //--------------------------------------------------------------------------
    localparam int SELECTOR_WIDTH    = 7;      // Row/column selector width
    
    // Selector bit field positions
    localparam int SEL_BLOCK_ID_MSB  = 6;
    localparam int SEL_BLOCK_ID_LSB  = 5;
    localparam int SEL_SUB_BLOCK_ID_MSB = 4;
    localparam int SEL_SUB_BLOCK_ID_LSB = 3;
    localparam int SEL_ROW_COL_MSB   = 2;
    localparam int SEL_ROW_COL_LSB   = 0;

    //--------------------------------------------------------------------------
    // Buffer Address Constants
    //--------------------------------------------------------------------------
    
    localparam int UNIQUE_WEIGHTS_PER_SUB_BLOCK = SUB_BLOCK_ROWS * SUB_BLOCK_COLS;  // 64
    localparam int BUF_ADDR_WIDTH     = 5;      
    localparam int BUF_MAX_ADDR       = 31;     

    //--------------------------------------------------------------------------
    // Default Parameters
    //--------------------------------------------------------------------------
    localparam int DEFAULT_ADDR_WIDTH   = 8;   
    localparam int DEFAULT_WEIGHT_WIDTH = 16;

    //--------------------------------------------------------------------------
    // Mux Control Constants
    //--------------------------------------------------------------------------
    localparam int MUX_ENABLE_WIDTH = 1;
    localparam int MUX_MODE_WIDTH = 2;
    localparam int MUX_CONTROL_WIDTH = 3;  // enable + mode
    localparam int ROW_MUXES_PER_MATRIX = 8;
    localparam int COL_MUXES_PER_MATRIX = 8;
    localparam int MUX_CONTROL_BITS_PER_MATRIX = 48;  // (8+8) * 3

    //--------------------------------------------------------------------------
    // Mux Mode Encoding
    //--------------------------------------------------------------------------
    typedef enum logic [1:0] {
        MUX_MODE_READ  = 2'b00,
        MUX_MODE_WRITE = 2'b01,
        MUX_MODE_ERASE = 2'b10,
        MUX_MODE_HIZ   = 2'b11
    } mux_mode_t;

    //--------------------------------------------------------------------------
    // Programming Sequence Sub-States
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] {
        PROG_HIZ,
        PROG_SELECT,
        PROG_ENABLE,
        PROG_WRITE,
        PROG_DISABLE,
        PROG_COMPLETE
    } prog_sequence_state_t;   

    //--------------------------------------------------------------------------
    // Helper Functions
    //--------------------------------------------------------------------------

    
    function automatic logic [BLOCK_ID_WIDTH-1:0] get_block_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[BLOCK_ID_MSB:BLOCK_ID_LSB];
    endfunction

    
    function automatic logic [SUB_BLOCK_ID_WIDTH-1:0] get_sub_block_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[SUB_BLOCK_ID_MSB:SUB_BLOCK_ID_LSB];
    endfunction

    
    function automatic logic [ROW_ID_WIDTH-1:0] get_row_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[ROW_ID_MSB:ROW_ID_LSB];
    endfunction

    
    function automatic logic [COL_ID_WIDTH-1:0] get_col_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[COL_ID_MSB:COL_ID_LSB];
    endfunction

    
    function automatic logic [SELECTOR_WIDTH-1:0] gen_row_selector(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return {get_block_id(addr), get_sub_block_id(addr), get_row_id(addr)};
    endfunction

    
    function automatic logic [SELECTOR_WIDTH-1:0] gen_col_selector(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return {get_block_id(addr), get_sub_block_id(addr), get_col_id(addr)};
    endfunction

endpackage
