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
    typedef enum logic [3:0] {
        S_IDLE          = 4'd0,  // Idle state
        S_RESET         = 4'd1,  // Reset ANN core and buffer
        S_PROGRAM       = 4'd2,  // Program weights into ANN
        S_VERIFY        = 4'd3,  // Verify programmed weights
        S_ERASE         = 4'd4,  // Erase weights if needed
        S_READ          = 4'd5,  // Read weight from memristor
        S_COLLECT_DATA  = 4'd6,  // Collect data for inference (INF command)
        S_COMPUTE       = 4'd7,  // Inference computation phase
        S_RESULT        = 4'd8   // Output classification results
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
    // Matrix Dimension Constants (for Generic Weight Mapping)
    //--------------------------------------------------------------------------
    localparam int MAX_MATRIX_ROWS = 32;  // Max rows (limited by ANN core)
    localparam int MAX_MATRIX_COLS = 64;  // Max cols (64 = 4 blocks × 16 cols)
    localparam int DEFAULT_MATRIX_ROWS = 10;  // For current 640-weight case (10×64)
    localparam int DEFAULT_MATRIX_COLS = 64;  // For current 640-weight case
    localparam int DEFAULT_NUM_WEIGHTS = DEFAULT_MATRIX_ROWS * DEFAULT_MATRIX_COLS;  // 640
    
    // Weight count tracking
    localparam int WEIGHT_COUNT_WIDTH = 10;  // Support up to 1024 weights
    localparam int MIN_WEIGHT_COUNT = 1;
    localparam int MAX_WEIGHT_COUNT = TOTAL_WEIGHT_LOCATIONS;  // 1024     

    // Max re-program attempts without ERASE (when read < expected)
    localparam int MAX_PROG_RETRIES = 3;

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
    // Note: INF mode uses same encoding as HIZ (2'b11) during computation
    // HIZ is used for idle/disabled muxes, INF is used during inference computation
    typedef enum logic [1:0] {
        MUX_MODE_READ  = 2'b00,
        MUX_MODE_WRITE = 2'b01,
        MUX_MODE_ERASE = 2'b10,
        MUX_MODE_HIZ   = 2'b11  // Also used as MUX_MODE_INF during computation
    } mux_mode_t;
    
    // INF mode constant (same value as HIZ, different usage context)
    localparam logic [1:0] MUX_MODE_INF = MUX_MODE_HIZ;

    //--------------------------------------------------------------------------
    // Pulse Mode Encoding (5 modes, 3 bits) - matches host cmd_t
    //--------------------------------------------------------------------------
    // Used for pulse output: each bit that is 1 in the mode drives a pulse
    typedef enum logic [2:0] {
        PULSE_MODE_HIZ   = 3'b000,
        PULSE_MODE_READ  = 3'b001,
        PULSE_MODE_PROG  = 3'b010,
        PULSE_MODE_ERASE = 3'b011,
        PULSE_MODE_INF   = 3'b100
    } pulse_mode_t;

    //--------------------------------------------------------------------------
    // Pulse Generator Parameters
    //--------------------------------------------------------------------------
    localparam int TREAD         = 2;    // Read pulse width (clock cycles)
    localparam int PULSE_NUM_READ  = 1;  // Number of read pulses
    localparam int TPROG         = 2;    // Program pulse width
    localparam int PULSE_NUM_PROG  = 1;  // Number of program pulses
    localparam int TERASE        = 2;    // Erase pulse width
    localparam int PULSE_NUM_ERASE = 1;  // Number of erase pulses
    localparam int TINF          = 2;    // Inference pulse width
    localparam int PULSE_NUM_INF   = 1;  // Number of inference pulses

    // Total pulse cycles per mode (T * N); controller generates pulses for this duration
    localparam int PULSE_TOTAL_READ  = TREAD  * PULSE_NUM_READ;
    localparam int PULSE_TOTAL_PROG  = TPROG  * PULSE_NUM_PROG;
    localparam int PULSE_TOTAL_ERASE = TERASE * PULSE_NUM_ERASE;
    localparam int PULSE_TOTAL_INF   = (TINF * PULSE_NUM_INF >= 8) ? (TINF * PULSE_NUM_INF) : 8;  // min 8 for bit-serial

    // Output address widths for ANN core interface
    localparam int PE_WIDTH  = 4;   // One-hot PE select
    localparam int SA_WIDTH  = 4;   // One-hot Sub-Array select
    localparam int ROW_WIDTH = 8;   // Row select mask (one-hot)
    localparam int COL_WIDTH = 8;   // Column select mask (one-hot)
    localparam int ADDR_OUT_WIDTH = 32;  // PE[23:20], SA[19:16], col[15:8], row[7:0]

    //--------------------------------------------------------------------------
    // Convert 16-bit host address to 32-bit ANN core output address
    //--------------------------------------------------------------------------
    // Output format: [7:0] row (one-hot), [15:8] col (one-hot), [19:16] SA (one-hot), [23:20] PE (one-hot)
    function automatic logic [ADDR_OUT_WIDTH-1:0] host_addr_to_ann_addr_out(
        input logic [BLOCK_ID_WIDTH-1:0] block_id,
        input logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id,
        input logic [ROW_ID_WIDTH-1:0] row_id,
        input logic [COL_ID_WIDTH-1:0] col_id
    );
        logic [PE_WIDTH-1:0]  pe_onehot;
        logic [SA_WIDTH-1:0]  sa_onehot;
        logic [ROW_WIDTH-1:0] row_onehot;
        logic [COL_WIDTH-1:0] col_onehot;
        pe_onehot  = (1 << block_id);
        sa_onehot  = (1 << sub_block_id);
        row_onehot = (1 << row_id);
        col_onehot = (1 << col_id);
        return {pe_onehot, sa_onehot, col_onehot, row_onehot};
    endfunction

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

    //--------------------------------------------------------------------------
    // Address Parsing Function for Direct Address Interface
    //--------------------------------------------------------------------------
    // Parse 16-bit address field from parallel interface to extract ANN address components
    // Address format: {reserved[15:10], block_id[9:8], sub_block_id[7:6], col_id[5:3], row_id[2:0]}
    function automatic void parse_ann_address(
        input logic [15:0] address,
        output logic [BLOCK_ID_WIDTH-1:0] block_id,
        output logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id,
        output logic [ROW_ID_WIDTH-1:0] row_id,
        output logic [COL_ID_WIDTH-1:0] col_id
    );
        // Extract fields from address[15:0]:
        //   address[9:8]   = block_id (PE/matrix)
        //   address[7:6]   = sub_block_id (sub-array)
        //   address[5:3]   = col_id (column)
        //   address[2:0]   = row_id (row)
        //   address[15:10] = reserved
        block_id     = address[9:8];
        sub_block_id = address[7:6];
        col_id       = address[5:3];
        row_id       = address[2:0];
    endfunction

    //--------------------------------------------------------------------------
    // Generic Weight Mapping Functions
    //--------------------------------------------------------------------------
    // Maps buffer index to ANN core address for variable weight counts
    // For 10×64 matrix (640 weights):
    //   - Block 0: matrix columns 0-15, all rows 0-9
    //   - Block 1: matrix columns 16-31, all rows 0-9
    //   - Block 2: matrix columns 32-47, all rows 0-9
    //   - Block 3: matrix columns 48-63, all rows 0-9
    //   Within each block:
    //     - Sub-block 0: cols 0-7, rows 0-7 (full 8×8)
    //     - Sub-block 1: cols 8-15, rows 0-7 (full 8×8)
    //     - Sub-block 2: cols 0-7, rows 8-9 (partial: 2 rows → ANN rows 0-1)
    //     - Sub-block 3: cols 8-15, rows 8-9 (partial: 2 rows → ANN rows 0-1)
    //--------------------------------------------------------------------------
    
    // Convert buffer index to matrix row and column coordinates
    // For 10 rows × 64 columns: row = idx / 64, col = idx % 64
    // Optimized for 64 columns: division by 64 = shift right by 6, modulo 64 = lower 6 bits
    function automatic void buffer_idx_to_matrix_coords(
        input logic [WEIGHT_COUNT_WIDTH-1:0] buffer_idx,
        input logic [5:0] matrix_rows,  // Number of rows in weight matrix (default: 10)
        input logic [6:0] matrix_cols,  // Number of columns in weight matrix (default: 64)
        output logic [5:0] matrix_row,
        output logic [6:0] matrix_col
    );
        // For matrix_cols = 64: row = buffer_idx / 64, col = buffer_idx % 64
        // Division by 64 = shift right by 6 bits: buffer_idx[9:6] gives row (0-9 for 640 weights)
        // Modulo 64 = keep lower 6 bits: buffer_idx[5:0] gives column (0-63)
        // This works for buffer_idx < 640 (10 × 64)
        // Currently hardcoded for 64 columns for synthesizability
        // Can be extended for other column counts (power-of-2) using similar bit operations
        if (matrix_cols == 64) begin
            // For 64 columns: optimize using bit operations
            matrix_row = buffer_idx[9:6];  // Divide by 64 (shift right 6)
            matrix_col = buffer_idx[5:0];  // Modulo 64 (keep lower 6 bits)
        end else if (matrix_cols == 32) begin
            matrix_row = buffer_idx[9:5];  // Divide by 32
            matrix_col = buffer_idx[4:0];  // Modulo 32
        end else if (matrix_cols == 16) begin
            matrix_row = buffer_idx[9:4];  // Divide by 16
            matrix_col = buffer_idx[3:0];  // Modulo 16
        end else if (matrix_cols == 8) begin
            matrix_row = buffer_idx[9:3];  // Divide by 8
            matrix_col = buffer_idx[2:0];  // Modulo 8
        end else begin
            // Default: assume 64 columns (for backward compatibility)
            matrix_row = buffer_idx[9:6];
            matrix_col = buffer_idx[5:0];
        end
    endfunction
    
    // Convert matrix coordinates to ANN core address
    // Maps (matrix_row, matrix_col) to (block_id, sub_block_id, row_id, col_id)
    function automatic logic [WEIGHT_ADDR_WIDTH-1:0] matrix_coords_to_ann_addr(
        input logic [5:0] matrix_row,   // 0-31 (for up to 32 rows)
        input logic [6:0] matrix_col    // 0-63 (for up to 64 columns)
    );
        logic [BLOCK_ID_WIDTH-1:0] block_id;
        logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id;
        logic [ROW_ID_WIDTH-1:0] ann_row_id;
        logic [COL_ID_WIDTH-1:0] ann_col_id;
        logic [3:0] col_within_block;  // Column within block (0-15)
        
        // Block selection: each block handles 16 columns
        // Block 0: cols 0-15, Block 1: cols 16-31, Block 2: cols 32-47, Block 3: cols 48-63
        block_id = matrix_col[5:4];  // Divide by 16
        
        // Column within block (0-15)
        col_within_block = matrix_col[3:0];
        
        // Sub-block selection within block:
        //   - Sub-block 0: cols 0-7, rows 0-7
        //   - Sub-block 1: cols 8-15, rows 0-7
        //   - Sub-block 2: cols 0-7, rows 8-9 (maps to ANN rows 0-1)
        //   - Sub-block 3: cols 8-15, rows 8-9 (maps to ANN rows 0-1)
        if (matrix_row < 8) begin
            // First 8 rows: sub-block 0 or 1
            sub_block_id = col_within_block[3] ? 2'd1 : 2'd0;  // col >= 8 → sub-block 1
            ann_row_id = matrix_row[2:0];  // rows 0-7 map directly to ANN rows 0-7
        end else begin
            // Rows 8-9: sub-block 2 or 3
            sub_block_id = col_within_block[3] ? 2'd3 : 2'd2;  // col >= 8 → sub-block 3
            // Rows 8-9 map to ANN rows 0-1: row 8 → ANN row 0, row 9 → ANN row 1
            // Since matrix_row is 8 or 9, ann_row_id = matrix_row - 8 = matrix_row[0]
            ann_row_id = {2'b0, matrix_row[0]};  // Convert to 3-bit: row 8 → 0, row 9 → 1
        end
        
        // Column within sub-block (0-7)
        ann_col_id = col_within_block[2:0];
        
        // Combine into 10-bit address: {block_id[1:0], sub_block_id[1:0], ann_row_id[2:0], ann_col_id[2:0]}
        return {block_id, sub_block_id, ann_row_id, ann_col_id};
    endfunction
    
    // Combined function: buffer index to ANN address
    // For now, uses default 10×64 matrix dimensions (optimized for 64 columns)
    function automatic logic [WEIGHT_ADDR_WIDTH-1:0] buffer_idx_to_ann_addr(
        input logic [WEIGHT_COUNT_WIDTH-1:0] buffer_idx,
        input logic [5:0] matrix_rows,  // Number of rows (default: 10)
        input logic [6:0] matrix_cols   // Number of columns (default: 64)
    );
        logic [5:0] matrix_row;
        logic [6:0] matrix_col;
        logic [BLOCK_ID_WIDTH-1:0] block_id;
        logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id;
        logic [ROW_ID_WIDTH-1:0] ann_row_id;
        logic [COL_ID_WIDTH-1:0] ann_col_id;
        logic [3:0] col_within_block;
        
        // Step 1: Convert buffer index to matrix coordinates
        // For 64 columns: row = buffer_idx / 64, col = buffer_idx % 64
        if (matrix_cols == 64) begin
            matrix_row = buffer_idx[9:6];  // Divide by 64 (shift right 6)
            matrix_col = buffer_idx[5:0];  // Modulo 64 (keep lower 6 bits)
        end else begin
            // Default: assume 64 columns
            matrix_row = buffer_idx[9:6];
            matrix_col = buffer_idx[5:0];
        end
        
        // Step 2: Convert matrix coordinates to ANN address
        // Block selection: each block handles 16 columns
        block_id = matrix_col[5:4];  // Divide by 16
        
        // Column within block (0-15)
        col_within_block = matrix_col[3:0];
        
        // Sub-block and row selection
        if (matrix_row < 8) begin
            // First 8 rows: sub-block 0 or 1
            sub_block_id = col_within_block[3] ? 2'd1 : 2'd0;  // col >= 8 → sub-block 1
            ann_row_id = matrix_row[2:0];  // rows 0-7 map directly to ANN rows 0-7
        end else begin
            // Rows 8-9: sub-block 2 or 3
            sub_block_id = col_within_block[3] ? 2'd3 : 2'd2;  // col >= 8 → sub-block 3
            ann_row_id = {2'b0, matrix_row[0]};  // row 8 → 0, row 9 → 1
        end
        
        // Column within sub-block (0-7)
        ann_col_id = col_within_block[2:0];
        
        // Combine into 10-bit address: {block_id[1:0], sub_block_id[1:0], ann_row_id[2:0], ann_col_id[2:0]}
        return {block_id, sub_block_id, ann_row_id, ann_col_id};
    endfunction

endpackage
