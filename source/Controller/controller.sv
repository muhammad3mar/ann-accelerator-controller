//------------------------------------------------------------------------------
// ANN Controller 
//------------------------------------------------------------------------------


`include "../common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module ann_controller #(
    parameter int ADDR_WIDTH   = controller_pkg::DEFAULT_ADDR_WIDTH,
    parameter int WEIGHT_WIDTH = controller_pkg::DEFAULT_WEIGHT_WIDTH
) (
    //======================================================================
    // Global
    //======================================================================
    input  logic                     clk,
    input  logic                     rst_n,

    //======================================================================
    // Controller <-> Parallel Interface
    //======================================================================
    input  logic                     valid,     // Valid command/data ready
    input  logic [7:0]               data,      // 8-bit data from parallel interface
    input  logic [15:0]              address,   // 16-bit address from parallel interface
    input  logic [CMD_WIDTH-1:0]     cmd,       // Command from parallel interface            

    //======================================================================
    // Controller <-> ANN Core
    //======================================================================
    output logic                     ann_reset,        
    output logic                     weight_write_en,  // write enable for weight programming
    output logic [SELECTOR_WIDTH-1:0] row_selector,     // row selector: block[1:0] + sub_block[1:0] + row[2:0]
    output logic [SELECTOR_WIDTH-1:0] col_selector,     // column selector: block[1:0] + sub_block[1:0] + col[2:0]
    input  logic                     op_done,
    
    // Mux control outputs
    output logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][ROW_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] row_mux_ctrl,
    output logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][COL_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] col_mux_ctrl,
    output logic [3:0]               weight_data,    // weight value to write          

    //======================================================================
    // Controller <-> Input Buffer
    //======================================================================
    output logic [5:0]               buf_reg_add,      
    output logic [2:0]               buf_reg_ctrl,     // buffer control signals
    output logic                     buf_read_write,   // 1 = write, 0 = read
    output logic [7:0]               buf_data_out,     // Captured data for buffer write (from parallel interface)
    input  logic                     buf_ready,
    input  logic [BUFFER_DATA_WIDTH-1:0] buf_data, // Data from input buffer        

    //======================================================================
    // Status to higher-level
    //======================================================================
    output logic                     busy              
);

    //--------------------------------------------------------------------------
    // FSM States (using package type)
    //--------------------------------------------------------------------------
    controller_state_t state, next_state;
    prog_sequence_state_t prog_state, next_prog_state;

    //--------------------------------------------------------------------------
    // VERIFY sub-FSM
    //--------------------------------------------------------------------------
    typedef enum logic [1:0] {
        VERIFY_READ,
        VERIFY_WAIT,
        VERIFY_CHECK,
        VERIFY_DONE
    } verify_state_t;

    verify_state_t verify_state, verify_next;

    //--------------------------------------------------------------------------
    // ERASE sub-FSM
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ERASE_HIZ,
        ERASE_SELECT,
        ERASE_ENABLE,
        ERASE_PULSE,
        ERASE_DISABLE,
        ERASE_COMPLETE
    } erase_state_t;

    erase_state_t erase_state, erase_next;

    //--------------------------------------------------------------------------
    // VERIFY and ERASE sub-FSM Signals
    //--------------------------------------------------------------------------
    // Retry counter (counts how many ERASE attempts for current weight)
    logic [1:0] retry_cnt;     // 0..3

    // Simple "read valid" modeling (timing for verification reads)
    logic [1:0] verify_wait_cnt;

    // Outputs (or internal signals connected to outputs)
    logic        weight_read_en;      // enable read in VERIFY
    logic [3:0]  weight_read_data;    // comes from ADC/quantizer (input in your top)
    logic [3:0]  expected_weight;     // from buffer/host
    logic        error_flag;

    // Optional: flag to strengthen program when read > expected
    logic        program_stronger;

    //--------------------------------------------------------------------------
    // Direct Address and Data from Parallel Interface (for new commands)
    //--------------------------------------------------------------------------
    logic [15:0] address_reg;          // Current address from parallel interface
    logic [7:0]  data_reg;             // Current data from parallel interface (captured with address)
    logic [WEIGHT_ADDR_WIDTH-1:0] weight_addr_reg;  // Parsed ANN address
    
    // Address parsing outputs
    logic [BLOCK_ID_WIDTH-1:0]      block_id;              
    logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id;          
    logic [ROW_ID_WIDTH-1:0]       row_id;                
    logic [COL_ID_WIDTH-1:0]       col_id;

    //--------------------------------------------------------------------------
    // Data Collection Tracking for INF Command
    //--------------------------------------------------------------------------
    logic [2:0] data_count;    // Counter for pixels within current row (0-7)
    logic [2:0] row_count;     // Counter for current row (0-7)
    logic [5:0] buf_write_addr; // Buffer write address for data collection

    //--------------------------------------------------------------------------
    // Weight Count Detection and Tracking (kept for ERASE/VERIFY compatibility)
    //--------------------------------------------------------------------------
    logic [WEIGHT_COUNT_WIDTH-1:0] weight_count_reg;  // Number of weights to program (1-1024)
    logic                           weight_count_valid;  // Weight count is ready
    logic [WEIGHT_COUNT_WIDTH-1:0] buffer_idx_reg;  // Current buffer index (0 to weight_count-1)
    
    // Matrix dimensions (for mapping algorithm - kept for ERASE/VERIFY)
    logic [5:0] matrix_rows;  // Number of rows (default: 10)
    logic [6:0] matrix_cols;  // Number of columns (default: 64)
    logic                           weight_prog_done;       // All weights programmed flag

    // Buffer address and weight selection (kept for ERASE/VERIFY)
    logic [BUF_ADDR_WIDTH-1:0]     buf_addr_reg;          
    logic                           weight_sel;
    
    // Weight data extraction from buffer
    logic [3:0] weight_from_buffer;
    
    // Expected weight for verification (from buffer)
    assign expected_weight = weight_from_buffer;             

    //--------------------------------------------------------------------------
    // Address Parsing: Direct address from parallel interface (for new commands)
    //--------------------------------------------------------------------------
    `comb(
        // For new commands (PROG, ERASE, READ, INF): parse address directly
        if (state != S_VERIFY && state != S_ERASE) begin
            // Parse 16-bit address from parallel interface
            parse_ann_address(address_reg, block_id, sub_block_id, row_id, col_id);
            
            // Form 10-bit ANN address: {block_id[1:0], sub_block_id[1:0], row_id[2:0], col_id[2:0]}
            weight_addr_reg = {block_id, sub_block_id, row_id, col_id};
        end else begin
            // For VERIFY and ERASE: keep using mapping algorithm (compatibility)
            weight_addr_reg = buffer_idx_to_ann_addr(buffer_idx_reg, matrix_rows, matrix_cols);
            block_id     = get_block_id(weight_addr_reg);
            sub_block_id = get_sub_block_id(weight_addr_reg);
            row_id       = get_row_id(weight_addr_reg);
            col_id       = get_col_id(weight_addr_reg);
        end
    )

    //--------------------------------------------------------------------------
    // Row and Column Selector Generation (using package functions)
    //--------------------------------------------------------------------------
    `comb(
        row_selector = gen_row_selector(weight_addr_reg);
        col_selector = gen_col_selector(weight_addr_reg);
    )
    
    //--------------------------------------------------------------------------
    // Buffer Address and Weight Selection Mapping
    //--------------------------------------------------------------------------
    // For new PROG command: use direct address (data stored as 8-bit in buffer)
    // For old mapping: use buffer_idx_reg (2 weights per location)
    `comb(
        // Buffer address: divide buffer index by 2 (since 2 weights per location)
        buf_addr_reg = buffer_idx_reg[WEIGHT_COUNT_WIDTH-1:1];  // Divide by 2 (shift right 1)
        weight_sel   = buffer_idx_reg[0];  // LSB selects which weight in the pair
        
        // Extract weight data from buffer
        // For new PROG command: data is stored as 8-bit in buffer[address_reg[5:0]]
        //   - Lower 4 bits [3:0] contain the weight
        // For old mapping: use weight_sel to choose between lower/upper 4 bits
        if (state == S_PROGRAM) begin
            // New PROG command: extract weight from lower 4 bits of buf_data
            weight_from_buffer = buf_data[3:0];
        end else begin
            // Old mapping: use weight_sel
            if (weight_sel == 1'b0) begin
                weight_from_buffer = buf_data[3:0];   // Weight[0] in lower 4 bits
            end else begin
                weight_from_buffer = buf_data[7:4];   // Weight[1] in upper 4 bits
            end
        end
        
        // Weight data output
        weight_data = weight_from_buffer;
    )

    //--------------------------------------------------------------------------
    // Buffer Data Output Assignment
    //--------------------------------------------------------------------------
    // Output captured data_reg for PROG command, or current data for INF command
    `comb(
        // For PROG state: use captured data_reg (written during PROG_HIZ/PROG_SELECT)
        // For INF state (S_COLLECT_DATA): use current data from parallel interface
        if (state == S_PROGRAM) begin
            buf_data_out = data_reg;  // Use captured data for PROG
        end else begin
            buf_data_out = data;  // Use current data for INF (S_COLLECT_DATA)
        end
    )

    //--------------------------------------------------------------------------
    // Mux Control Signal Generation
    //--------------------------------------------------------------------------
    // Generate control signals for all row and column muxes
    // Each mux control: {enable, mode[1:0]}
    `comb(
        // Default: all muxes disabled and in High Z mode
        for (int b = 0; b < NUM_BLOCKS; b++) begin
            for (int sb = 0; sb < NUM_SUB_BLOCKS; sb++) begin
                for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
                    row_mux_ctrl[b][sb][r] = {1'b0, MUX_MODE_HIZ};
                end
                for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
                    col_mux_ctrl[b][sb][c] = {1'b0, MUX_MODE_HIZ};
                end
            end
        end
        
        // ========== PROGRAM state: programming sequence sub-states ==========
        if (state == S_PROGRAM) begin
            if (prog_state == PROG_SELECT || prog_state == PROG_ENABLE || 
                prog_state == PROG_WRITE) begin
                // Target matrix: block_id, sub_block_id
                // Target row: row_id within matrix
                // Target column: col_id within matrix
                
                // Row muxes
                for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
                    if (r == row_id) begin
                        // Target row mux: write mode
                        if (prog_state == PROG_ENABLE || prog_state == PROG_WRITE) begin
                            row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_WRITE};
                        end else if (prog_state == PROG_SELECT) begin
                            row_mux_ctrl[block_id][sub_block_id][r] = {1'b0, MUX_MODE_WRITE};
                        end
                    end else begin
                        // Other row muxes: High Z mode
                        if (prog_state == PROG_ENABLE || prog_state == PROG_WRITE) begin
                            row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_HIZ};
                        end
                    end
                end
                
                // Column muxes
                for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
                    if (c == col_id) begin
                        // Target column mux: write mode
                        if (prog_state == PROG_ENABLE || prog_state == PROG_WRITE) begin
                            col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_WRITE};
                        end else if (prog_state == PROG_SELECT) begin
                            col_mux_ctrl[block_id][sub_block_id][c] = {1'b0, MUX_MODE_WRITE};
                        end
                    end else begin
                        // Other column muxes: High Z mode
                        if (prog_state == PROG_ENABLE || prog_state == PROG_WRITE) begin
                            col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_HIZ};
                        end
                    end
                end
            end
        end
        
        // ========== READ state: set muxes to READ mode ==========
        if (state == S_READ) begin
            // In READ, select target row/col in READ mode to read weight from memristor
            for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
                if (r == row_id)
                    row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_READ};
            end

            for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
                if (c == col_id)
                    col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_READ};
            end
        end

        // ========== VERIFY state: set muxes to READ mode ==========
        if (state == S_VERIFY) begin
            // In VERIFY, select target row/col in READ mode
            for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
                if (r == row_id)
                    row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_READ};
            end

            for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
                if (c == col_id)
                    col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_READ};
            end
        end

        // ========== COMPUTE state: set muxes to INF mode ==========
        if (state == S_COMPUTE) begin
            // For inference computation, set muxes to INF mode (replaces High Z)
            // INF mode enables matrix multiplication: input_data × stored_weights
            // Set all relevant muxes based on input data being processed
            for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
                if (r == row_id)  // Based on input data row being applied
                    row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_INF};
            end

            for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
                // Column muxes in INF mode for computation
                col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_INF};
            end
        end

        // ========== ERASE state: set muxes to ERASE mode ==========
        if (state == S_ERASE) begin
            // In ERASE, select target row/col in ERASE mode for relevant sub-states
            if (erase_state == ERASE_SELECT || erase_state == ERASE_ENABLE ||
                erase_state == ERASE_PULSE  || erase_state == ERASE_DISABLE) begin

                for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
                    if (r == row_id)
                        row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_ERASE};
                end

                for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
                    if (c == col_id)
                        col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_ERASE};
                end
            end
        end
    )

    //--------------------------------------------------------------------------
    // State register, address tracking, and data collection
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            prog_state         <= PROG_HIZ;
            address_reg        <= '0;
            data_reg           <= '0;
            data_count         <= '0;
            row_count          <= '0;
            buf_write_addr     <= '0;
            
            // Keep these for ERASE/VERIFY compatibility
            buffer_idx_reg     <= '0;
            weight_count_reg   <= DEFAULT_NUM_WEIGHTS;  // Default: 640 weights
            weight_count_valid <= 1'b0;
            weight_prog_done   <= 1'b0;
            matrix_rows        <= DEFAULT_MATRIX_ROWS;  // Default: 10 rows
            matrix_cols        <= DEFAULT_MATRIX_COLS;  // Default: 64 columns
        end else begin
            state <= next_state;
            prog_state <= next_prog_state;
            
            // Capture address and data from parallel interface when valid command arrives
            if (valid && state == S_IDLE) begin
                address_reg <= address;
                data_reg <= data;  // Capture data along with address for PROG command
            end
            
            // Data collection counter for INF command (S_COLLECT_DATA state)
            if (state == S_COLLECT_DATA) begin
                if (valid) begin
                    if (data_count < 7) begin
                        data_count <= data_count + 1'b1;
                    end else begin
                        // Reset counter for next 8-pixel group
                        data_count <= '0;
                        row_count <= row_count + 1'b1;
                    end
                    // Update buffer write address: (row_count * 8) + data_count
                    buf_write_addr <= (row_count * 8) + data_count;
                end
            end else if (state == S_IDLE && next_state == S_COLLECT_DATA) begin
                // Initialize counters when entering collection state
                data_count <= '0;
                row_count <= '0;
                buf_write_addr <= '0;
            end
            
            // Keep ERASE/VERIFY logic for compatibility (unchanged)
            // Weight count detection: For now, use default 640 weights
            // TODO: In the future, can count buffer writes or use explicit count signal
            if (state == S_IDLE && next_state == S_RESET) begin
                // Initialize with default values when starting programming
                weight_count_reg <= DEFAULT_NUM_WEIGHTS;
                weight_count_valid <= 1'b1;
                matrix_rows <= DEFAULT_MATRIX_ROWS;
                matrix_cols <= DEFAULT_MATRIX_COLS;
                buffer_idx_reg <= '0;
                weight_prog_done <= 1'b0;
            end
            
            // Reset buffer index when entering RESET state
            if (state == S_IDLE && next_state == S_RESET) begin
                buffer_idx_reg <= '0;
            end
            
            // Advance buffer index after successful verification when
            // transitioning back into PROGRAM state.
            if (state == S_VERIFY && next_state == S_PROGRAM) begin
                if (buffer_idx_reg < (weight_count_reg - 1)) begin
                    buffer_idx_reg <= buffer_idx_reg + 1'b1;
                end else begin
                    weight_prog_done <= 1'b1;
                end
            end
            
            // Check completion during programming
            if (state == S_PROGRAM && prog_state == PROG_COMPLETE) begin
                if (buffer_idx_reg >= (weight_count_reg - 1)) begin
                    weight_prog_done <= 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // VERIFY, ERASE, and PROGRAM sub-FSM state registers
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            verify_state     <= VERIFY_READ;
            erase_state      <= ERASE_HIZ;
            retry_cnt        <= 2'd0;
            verify_wait_cnt  <= 2'd0;
            program_stronger <= 1'b0;
        end else begin
            verify_state <= verify_next;
            erase_state  <= erase_next;
            // prog_state is updated in the main state register block above

            // -------- retry counter: increment on each ERASE cycle completion --------
            if (state == S_PROGRAM) begin
                // Reset retry counter when starting to program new weight
                if (prog_state == PROG_COMPLETE && buffer_idx_reg < (weight_count_reg - 1)) begin
                    retry_cnt <= 2'd0;
                    program_stronger <= 1'b0;
                end
            end

            // Increment retry counter when ERASE cycle completes
            if (state == S_ERASE && erase_state == ERASE_COMPLETE) begin
                retry_cnt <= retry_cnt + 1'b1;
            end

            // -------- verify wait counter (timing for read latency) --------
            if (state != S_VERIFY) begin
                verify_wait_cnt <= 2'd0;
            end else if (verify_state == VERIFY_READ) begin
                verify_wait_cnt <= 2'd2; // Assume 2 cycles until data is stable
            end else if (verify_state == VERIFY_WAIT && verify_wait_cnt != 0) begin
                verify_wait_cnt <= verify_wait_cnt - 1'b1;
            end

            // -------- program_stronger flag: set in VERIFY_CHECK if needed --------
            if (state == S_VERIFY && verify_state == VERIFY_CHECK) begin
                if (weight_read_data != expected_weight && expected_weight > weight_read_data) begin
                    program_stronger <= 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Main FSM: outputs + next-state logic
    //--------------------------------------------------------------------------
    `comb(
       
        ann_reset        = 1'b0;
        weight_write_en  = 1'b0;

        
        // Default buffer address (will be overridden in each state)
        buf_reg_add      = {{(6-BUF_ADDR_WIDTH){1'b0}}, buf_addr_reg};  
        buf_reg_ctrl     = CTRL_IDLE;
        buf_read_write   = 1'b0;   // 0 = read, 1 = write

        
        busy             = 1'b0;

        next_state       = state;
        next_prog_state  = prog_state;

        unique case (state)

            //--------------------------------------------------------------
            // IDLE: wait for valid signal from parallel interface
            //--------------------------------------------------------------
            S_IDLE: begin
                busy            = 1'b0;
                buf_reg_add     = '0;
                buf_reg_ctrl    = CTRL_IDLE;
                buf_read_write  = 1'b0;
                
                // When valid signal arrives, decode command and proceed
                if (valid) begin
                    unique case (cmd)
                        CMD_PROG: begin
                            // Weight programming - store weight in buffer, then program
                            next_state = S_PROGRAM;
                            next_prog_state = PROG_HIZ;
                        end
                        CMD_ERASE: begin
                            // Weight erase - use direct address
                            next_state = S_ERASE;
                        end
                        CMD_READ: begin
                            // Read weight from memristor - use direct address
                            next_state = S_READ;
                        end
                        CMD_INF: begin
                            // Inference - collect data first
                            next_state = S_COLLECT_DATA;
                        end
                        default: begin
                            next_state = S_IDLE;
                        end
                    endcase
                end else begin
                    next_state = S_IDLE;
                end
            end

            //--------------------------------------------------------------
            // RESET: Reset ANN core and buffer (kept for compatibility)
            //--------------------------------------------------------------
            S_RESET: begin
                busy            = 1'b1;
                ann_reset       = 1'b1;
                buf_reg_ctrl    = CTRL_IDLE;
                buf_read_write  = 1'b0;
                
                // After reset, proceed to programming
                next_state = S_PROGRAM;
                next_prog_state = PROG_HIZ;
            end

            //--------------------------------------------------------------
            // PROGRAM: Program weights into ANN (with mux sequence sub-states)
            //--------------------------------------------------------------
            S_PROGRAM: begin
                busy            = 1'b1;
                
                // For new PROG command: store weight in buffer, then read from buffer for programming
                // Buffer address: use lower 6 bits of ANN address for temporary buffer storage
                // Weight must be stored in buffer for verification/reprogramming
                // Use address_reg (captured from parallel interface in S_IDLE)
                if (prog_state == PROG_HIZ || prog_state == PROG_SELECT) begin
                    // First, store weight data from parallel interface to buffer
                    // Use address_reg[5:0] for buffer storage location
                    buf_reg_add     = address_reg[5:0];
                    buf_reg_ctrl    = CTRL_DATA_LOAD;
                    buf_read_write  = 1'b1;              // Write to buffer
                end else begin
                    // Read weight from buffer for programming
                    buf_reg_add     = address_reg[5:0];
                    buf_reg_ctrl    = CTRL_WEIGHT_READ;  
                    buf_read_write  = 1'b0;              // Read from buffer
                end
                
                // Programming sequence sub-state machine
                unique case (prog_state)
                    PROG_HIZ: begin
                        // Set all muxes to High Z mode (disabled)
                        weight_write_en = 1'b0;
                        next_prog_state = PROG_SELECT;
                    end
                    
                    PROG_SELECT: begin
                        // Set target row/column mux mode to write (but not enabled yet)
                        weight_write_en = 1'b0;
                        next_prog_state = PROG_ENABLE;
                    end
                    
                    PROG_ENABLE: begin
                        // Enable ALL row and column muxes
                        // Target mux: enabled + write mode
                        // Other muxes: enabled + High Z mode
                        weight_write_en = 1'b0;
                        next_prog_state = PROG_WRITE;
                    end
                    
                    PROG_WRITE: begin
                        // Hold write state, wait for op_done
                        weight_write_en = 1'b1;
                        if (op_done) begin
                            next_prog_state = PROG_DISABLE;
                        end else begin
                            next_prog_state = PROG_WRITE;
                        end
                    end
                    
                    PROG_DISABLE: begin
                        // Disable all muxes (already in default state from mux control logic)
                        weight_write_en = 1'b0;
                        next_prog_state = PROG_COMPLETE;
                    end
                    
                    PROG_COMPLETE: begin
                        // Weight programming complete, proceed to verify
                        weight_write_en = 1'b0;
                        next_state = S_VERIFY;
                        next_prog_state = PROG_HIZ;  // Reset for next weight (if any)
                    end
                    
                    default: begin
                        next_prog_state = PROG_HIZ;
                    end
                endcase
            end

            //--------------------------------------------------------------
            // VERIFY: Verify programmed weights
            //--------------------------------------------------------------
            S_VERIFY: begin
                busy            = 1'b1;
                buf_reg_ctrl    = CTRL_IDLE;
                buf_read_write  = 1'b0;
                weight_read_en  = (verify_state == VERIFY_READ) ? 1'b1 : 1'b0;
                
                // VERIFY sub-FSM logic
                unique case (verify_state)
                    VERIFY_READ: begin
                        // Initiate read from current weight location
                        verify_next = VERIFY_WAIT;
                    end
                    
                    VERIFY_WAIT: begin
                        // Wait for read data to be valid (verify_wait_cnt counts down)
                        if (verify_wait_cnt == 0)
                            verify_next = VERIFY_CHECK;
                        else
                            verify_next = VERIFY_WAIT;
                    end
                    
                    VERIFY_CHECK: begin
                        // Compare read weight with expected weight
                        // If mismatch, set error_flag and transition to ERASE
                        if (weight_read_data != expected_weight) begin
                            error_flag = 1'b1;
                            // If expected > read, may need stronger programming
                            // Note: program_stronger is set in sequential block
                            next_state = S_ERASE;  // Erase and retry
                            verify_next = VERIFY_READ;
                        end else begin
                            verify_next = VERIFY_DONE;  // Match: continue
                        end
                    end
                    
                    VERIFY_DONE: begin
                        // Move to next weight or exit verify
                        if (weight_prog_done) begin
                            // All weights verified, return to idle
                            next_state = S_IDLE;
                            verify_next = VERIFY_READ;
                        end else begin
                            // Proceed to program the next weight; the sequential
                            // block will advance `buffer_idx_reg` when entering
                            // PROGRAM from VERIFY.
                            next_state = S_PROGRAM;
                            verify_next = VERIFY_READ;
                        end
                    end
                    
                    default: begin
                        verify_next = VERIFY_READ;
                    end
                endcase
            end

            //--------------------------------------------------------------
            // ERASE: Erase weights if verification fails
            //--------------------------------------------------------------
            S_ERASE: begin
                busy            = 1'b1;
                buf_reg_ctrl    = CTRL_IDLE;
                buf_read_write  = 1'b0;
                
                // ERASE sub-FSM logic
                unique case (erase_state)
                    ERASE_HIZ: begin
                        // All muxes to High Z mode (disabled)
                        erase_next = ERASE_SELECT;
                    end
                    
                    ERASE_SELECT: begin
                        // Set target row/column mux mode to erase (but not enabled yet)
                        erase_next = ERASE_ENABLE;
                    end
                    
                    ERASE_ENABLE: begin
                        // Enable target row and column muxes in ERASE mode
                        erase_next = ERASE_PULSE;
                    end
                    
                    ERASE_PULSE: begin
                        // Hold erase pulse, wait for op_done (single-cell/row/global ERASE supported)
                        if (op_done) begin
                            erase_next = ERASE_DISABLE;
                        end else begin
                            erase_next = ERASE_PULSE;
                        end
                    end
                    
                    ERASE_DISABLE: begin
                        // Disable all muxes
                        erase_next = ERASE_COMPLETE;
                    end
                    
                    ERASE_COMPLETE: begin
                        // Check retry count and decide next action
                        if (retry_cnt < 3) begin
                            // Retry: go back to PROGRAM (with adaptive voltage if program_stronger set)
                            next_state = S_PROGRAM;
                            next_prog_state = PROG_HIZ;
                            erase_next = ERASE_HIZ;
                        end else begin
                            // Max retries exceeded, set error_flag and return to idle
                            error_flag = 1'b1;
                            next_state = S_IDLE;
                            next_prog_state = PROG_HIZ;
                            erase_next = ERASE_HIZ;
                        end
                    end
                    
                    default: begin
                        erase_next = ERASE_HIZ;
                    end
                endcase
            end

            //--------------------------------------------------------------
            // READ: Read weight from memristor at specified address
            //--------------------------------------------------------------
            S_READ: begin
                busy            = 1'b1;
                buf_reg_ctrl    = CTRL_IDLE;
                buf_read_write  = 1'b0;
                
                // Set muxes to READ mode for target row/column (handled in mux control logic)
                // Read value comes from weight_read_data (ADC/quantizer output)
                // After read complete, return to idle
                if (op_done) begin
                    next_state = S_IDLE;
                end else begin
                    next_state = S_READ;
                end
            end

            //--------------------------------------------------------------
            // COLLECT_DATA: Collect data for inference (INF command)
            //--------------------------------------------------------------
            S_COLLECT_DATA: begin
                busy            = 1'b1;
                
                // Write pixel data to input buffer
                buf_reg_add     = buf_write_addr;
                buf_reg_ctrl    = CTRL_DATA_LOAD;
                buf_read_write  = 1'b1;              // Write to buffer
                
                // Collect 8 pixels per row
                if (valid) begin
                    if (data_count < 7) begin
                        // Continue collecting pixels for current row
                        next_state = S_COLLECT_DATA;
                    end else begin
                        // 8 pixels collected, proceed to computation
                        next_state = S_COMPUTE;
                    end
                end else begin
                    next_state = S_COLLECT_DATA;
                end
            end

            //--------------------------------------------------------------
            // COMPUTE: Inference computation phase (INF command)
            //--------------------------------------------------------------
            S_COMPUTE: begin
                busy            = 1'b1;
                buf_reg_ctrl    = CTRL_COMPUTE;
                buf_read_write  = 1'b0;              // Read from buffer
                
                // Set muxes to INF mode for computation (handled in mux control logic)
                // INF mode enables matrix multiplication: input_data × stored_weights
                // Wait for op_done indicating computation complete
                if (op_done) begin
                    next_state = S_RESULT;
                end else begin
                    next_state = S_COMPUTE;
                end
            end

            //--------------------------------------------------------------
            // RESULT: Output classification results
            //--------------------------------------------------------------
            S_RESULT: begin
                busy            = 1'b1;
                buf_reg_ctrl    = CTRL_RESULT_OUT;
                buf_read_write  = 1'b0;
                
                // After result output complete, return to idle
                // For now, assume output completes immediately (can be extended)
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
                next_prog_state = PROG_HIZ;
            end

        endcase
    )

endmodule