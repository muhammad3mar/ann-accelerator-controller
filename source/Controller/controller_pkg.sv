//------------------------------------------------------------------------------
// Controller Package 
//------------------------------------------------------------------------------


package controller_pkg;

    //--------------------------------------------------------------------------
    // Controller FSM States
    //--------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE          = 2'd0,   
        S_PROGRAM_WEIGHTS = 2'd1  
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
    // Helper Functions
    //--------------------------------------------------------------------------

    // Extract block ID from weight address
    function automatic logic [BLOCK_ID_WIDTH-1:0] get_block_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[BLOCK_ID_MSB:BLOCK_ID_LSB];
    endfunction

    // Extract sub-block ID from weight address
    function automatic logic [SUB_BLOCK_ID_WIDTH-1:0] get_sub_block_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[SUB_BLOCK_ID_MSB:SUB_BLOCK_ID_LSB];
    endfunction

    // Extract row ID from weight address
    function automatic logic [ROW_ID_WIDTH-1:0] get_row_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[ROW_ID_MSB:ROW_ID_LSB];
    endfunction

    // Extract column ID from weight address
    function automatic logic [COL_ID_WIDTH-1:0] get_col_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[COL_ID_MSB:COL_ID_LSB];
    endfunction

    // Generate row selector from weight address
    function automatic logic [SELECTOR_WIDTH-1:0] gen_row_selector(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return {get_block_id(addr), get_sub_block_id(addr), get_row_id(addr)};
    endfunction

    // Generate column selector from weight address
    function automatic logic [SELECTOR_WIDTH-1:0] gen_col_selector(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return {get_block_id(addr), get_sub_block_id(addr), get_col_id(addr)};
    endfunction

endpackage
