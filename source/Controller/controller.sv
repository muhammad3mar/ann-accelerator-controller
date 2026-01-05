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
    input  logic                     valid,
    input  logic [CMD_WIDTH-1:0]     cmd,  // Command from parallel interface            

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
    output logic [3:0]               weight_data,  // weight value to write          

    //======================================================================
    // Controller <-> Input Buffer
    //======================================================================
    output logic [5:0]               buf_reg_add,      
    output logic [2:0]               buf_reg_ctrl,     // buffer control signals
    output logic                     buf_read_write,   // 1 = write, 0 = read
    input  logic                     buf_ready,
    input  logic [7:0]               buf_data,         // Buffer data (D0) for weight extraction        

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
    // Command and Data Type Tracking
    //--------------------------------------------------------------------------
    logic [CMD_WIDTH-1:0] cmd_reg;  // Registered command (data type)

    //--------------------------------------------------------------------------
    // Weight Address Mapping (using package constants)
    //--------------------------------------------------------------------------
    logic [WEIGHT_ADDR_WIDTH-1:0]  weight_addr_reg;      
    logic [BLOCK_ID_WIDTH-1:0]      block_id;              
    logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id;          
    logic [ROW_ID_WIDTH-1:0]       row_id;                
    logic [COL_ID_WIDTH-1:0]       col_id;                  
    logic                           weight_prog_done;       // All weights programmed flag

    // Buffer address and weight selection 
    logic [BUF_ADDR_WIDTH-1:0]     buf_addr_reg;          
    logic                           weight_sel;
    
    // Weight data from buffer
    logic [3:0] weight_from_buffer;             

    //--------------------------------------------------------------------------
    // Address Decoding: Extract block, sub-block, row, column from weight address
    //--------------------------------------------------------------------------
    `comb(
        block_id     = get_block_id(weight_addr_reg);
        sub_block_id = get_sub_block_id(weight_addr_reg);
        row_id       = get_row_id(weight_addr_reg);
        col_id       = get_col_id(weight_addr_reg);
    )

    //--------------------------------------------------------------------------
    // Row and Column Selector Generation (using package functions)
    //--------------------------------------------------------------------------
    `comb(
        row_selector = gen_row_selector(weight_addr_reg);
        col_selector = gen_col_selector(weight_addr_reg);
    )
    
    //--------------------------------------------------------------------------
    // Mux Control Signal Generation
    //--------------------------------------------------------------------------
    // Generate control signals for all row and column muxes
    // Each mux control: {enable, mode[1:0]}
    // enable: 1 = enabled, 0 = disabled
    // mode: 00=READ, 01=WRITE, 10=ERASE, 11=HIZ
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
        
        // Generate mux control based on programming sequence state
        if (state == S_PROGRAM) begin
            // Check if we're in the target matrix
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
                        end else begin
                            row_mux_ctrl[block_id][sub_block_id][r] = {1'b0, MUX_MODE_HIZ};
                        end
                    end else begin
                        // Other row muxes: High Z mode
                        if (prog_state == PROG_ENABLE || prog_state == PROG_WRITE) begin
                            row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_HIZ};
                        end else begin
                            row_mux_ctrl[block_id][sub_block_id][r] = {1'b0, MUX_MODE_HIZ};
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
                        end else begin
                            col_mux_ctrl[block_id][sub_block_id][c] = {1'b0, MUX_MODE_HIZ};
                        end
                    end else begin
                        // Other column muxes: High Z mode
                        if (prog_state == PROG_ENABLE || prog_state == PROG_WRITE) begin
                            col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_HIZ};
                        end else begin
                            col_mux_ctrl[block_id][sub_block_id][c] = {1'b0, MUX_MODE_HIZ};
                        end
                    end
                end
            end
        end
    )
    
    //--------------------------------------------------------------------------
    // Buffer Address and Weight Selection Mapping
    //--------------------------------------------------------------------------
   
    `comb(
        // Extract unique weight index within sub-block 
        // This is weight_addr_reg[5:0] = {row_id[2:0], col_id[2:0]}
        buf_addr_reg = weight_addr_reg[5:1];  // Divide unique weight index by 2
        weight_sel   = weight_addr_reg[0];     // Select weight[0] or weight[1] within location
    )
    
    //--------------------------------------------------------------------------
    // Weight Data Extraction from Buffer
    //--------------------------------------------------------------------------
    // Buffer location contains 2 weights: weight[0] in [3:0], weight[1] in [7:4]
    `comb(
        // Extract weight based on weight_sel
        if (weight_sel == 1'b0)
            weight_from_buffer = buf_data[3:0];   // weight[0]
        else
            weight_from_buffer = buf_data[7:4];   // weight[1]
        
        // Output weight data
        weight_data = weight_from_buffer;
    )

    //--------------------------------------------------------------------------
    // State register and weight address counter
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            prog_state         <= PROG_HIZ;
            weight_addr_reg    <= '0;
            weight_prog_done   <= 1'b0;
            cmd_reg            <= '0;
        end else begin
            state <= next_state;
            prog_state <= next_prog_state;
            
            // Register command when valid signal is asserted
            if (valid && state == S_IDLE) begin
                cmd_reg <= cmd;
            end
            
            // Reset weight address when entering RESET state (for weight programming)
            if (state == S_IDLE && next_state == S_RESET && cmd_reg == CMD_WEIGHTS) begin
                weight_addr_reg <= '0;
                weight_prog_done <= 1'b0;
            end
            
            // Handle programming sequence sub-states
            if (state == S_PROGRAM) begin
                // Advance to next weight when programming sequence completes
                if (prog_state == PROG_COMPLETE) begin
                    if (weight_addr_reg < (TOTAL_WEIGHT_LOCATIONS - 1)) begin
                        weight_addr_reg <= weight_addr_reg + 1'b1;
                    end else begin
                        weight_prog_done <= 1'b1;
                    end
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
                
                // When valid signal arrives, check command (data type)
                if (valid) begin
                    if (cmd == CMD_WEIGHTS) begin
                        // Weight programming sequence
                        next_state = S_RESET;
                    end else if (cmd == CMD_CLASSIFY_DATA) begin
                        // Classification sequence
                        next_state = S_READ;
                    end else begin
                        next_state = S_IDLE;
                    end
                end else begin
                    next_state = S_IDLE;
                end
            end

            //--------------------------------------------------------------
            // RESET: Reset ANN core and buffer
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
                
                // Buffer control: read weight data from buffer
                buf_reg_add     = {{(6-BUF_ADDR_WIDTH){1'b0}}, buf_addr_reg};  
                buf_reg_ctrl    = CTRL_WEIGHT_READ;  
                buf_read_write  = 1'b0;              // Read from buffer
                
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
                        // Return to High Z, check if more weights to program
                        weight_write_en = 1'b0;
                        if (weight_prog_done) begin
                            // All weights programmed, proceed to verify
                            next_state = S_VERIFY;
                            next_prog_state = PROG_HIZ;
                        end else begin
                            // Move to next weight
                            next_prog_state = PROG_HIZ;
                        end
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
                
                // For now, assume verification passes (can be extended later)
                next_state = S_IDLE;
            end

            //--------------------------------------------------------------
            // ERASE: Erase weights if needed
            //--------------------------------------------------------------
            S_ERASE: begin
                busy            = 1'b1;
                buf_reg_ctrl    = CTRL_IDLE;
                buf_read_write  = 1'b0;
                
                // After erase, retry programming
                next_state = S_RESET;
            end

            //--------------------------------------------------------------
            // READ: Read classification data from ANN
            //--------------------------------------------------------------
            S_READ: begin
                busy            = 1'b1;
                buf_reg_ctrl    = CTRL_COMPUTE;
                buf_read_write  = 1'b0;
                
                // After read complete, proceed to result output
                // For now, assume read completes immediately (can be extended)
                next_state = S_RESULT;
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