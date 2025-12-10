//------------------------------------------------------------------------------
// Input Buffer Package 
//------------------------------------------------------------------------------


package input_buffer_pkg;

    //--------------------------------------------------------------------------
    // Buffer Size Constants
    //--------------------------------------------------------------------------
    
    localparam int BUFFER_SIZE       = 64;      // Number of buffer locations
    localparam int BUFFER_ADDR_WIDTH = 6;      // Address width (0-63)
    localparam int BUFFER_DATA_WIDTH = 8;      // Data width per location 
    localparam int BUFFER_MAX_ADDR   = 63;     // Maximum valid address

    //--------------------------------------------------------------------------
    // Control Signal Encodings (reg_ctrl)
    //--------------------------------------------------------------------------
    
    typedef enum logic [2:0] {
        CTRL_IDLE         = 3'd0,  
        CTRL_DATA_LOAD    = 3'd1,  // Data load (MNIST)
        CTRL_COMPUTE      = 3'd2,  // Compute mode 
        CTRL_RESULT_OUT   = 3'd3,  // Result output 
        CTRL_WEIGHT_READ  = 3'd4   // Weight read (weight programming)
    } buffer_ctrl_t;

    //--------------------------------------------------------------------------
    // Data Organization Constants
    //--------------------------------------------------------------------------
    
    localparam int MNIST_ROWS        = 8;      
    localparam int MNIST_COLS        = 8;       
    localparam int MNIST_PIXELS      = 64;      
    localparam int PIXELS_PER_ROW   = 8;       
    localparam int PIXELS_PER_ADDR  = 8;       // Pixels output per address (D0-D7)

    // Address ranges for each row 
    localparam int ROW0_START        = 0;
    localparam int ROW0_END          = 7;
    localparam int ROW1_START        = 8;
    localparam int ROW1_END          = 15;
    localparam int ROW2_START        = 16;
    localparam int ROW2_END          = 23;
    localparam int ROW3_START        = 24;
    localparam int ROW3_END          = 31;
    localparam int ROW4_START        = 32;
    localparam int ROW4_END          = 39;
    localparam int ROW5_START        = 40;
    localparam int ROW5_END          = 47;
    localparam int ROW6_START        = 48;
    localparam int ROW6_END          = 55;
    localparam int ROW7_START        = 56;
    localparam int ROW7_END          = 63;

    //--------------------------------------------------------------------------
    // Weight Storage Organization
    //--------------------------------------------------------------------------
   
    localparam int WEIGHTS_PER_LOC   = 2;       // Number of weights per location
    localparam int WEIGHT_BITS       = 4;       
    localparam int WEIGHT0_LSB       = 0;       // Weight[0] bit range: [3:0]
    localparam int WEIGHT0_MSB       = 3;
    localparam int WEIGHT1_LSB       = 4;       // Weight[1] bit range: [7:4]
    localparam int WEIGHT1_MSB       = 7;

    //--------------------------------------------------------------------------
    // Output Data Lines
    //--------------------------------------------------------------------------
    
    localparam int NUM_DATA_LINES    = 8;       
    localparam int DATA_LINE_WIDTH   = 8;       

    //--------------------------------------------------------------------------
    // Helper Functions
    //--------------------------------------------------------------------------
    
    // Check if address is valid
    function automatic logic is_valid_addr(logic [BUFFER_ADDR_WIDTH-1:0] addr);
        return (addr < BUFFER_SIZE);
    endfunction

    // Get row number from address (for MNIST 8x8 organization)
    function automatic logic [2:0] get_row_from_addr(logic [BUFFER_ADDR_WIDTH-1:0] addr);
        return addr[5:3];  // Upper 3 bits represent row (0-7)
    endfunction

    // Get column offset from address (for MNIST 8x8 organization)
    function automatic logic [2:0] get_col_from_addr(logic [BUFFER_ADDR_WIDTH-1:0] addr);
        return addr[2:0];  // Lower 3 bits represent column offset (0-7)
    endfunction

    // Extract weight[0] from buffer data (bits [3:0])
    function automatic logic [WEIGHT_BITS-1:0] extract_weight0(logic [BUFFER_DATA_WIDTH-1:0] data);
        return data[WEIGHT0_MSB:WEIGHT0_LSB];
    endfunction

    // Extract weight[1] from buffer data (bits [7:4])
    function automatic logic [WEIGHT_BITS-1:0] extract_weight1(logic [BUFFER_DATA_WIDTH-1:0] data);
        return data[WEIGHT1_MSB:WEIGHT1_LSB];
    endfunction

endpackage
