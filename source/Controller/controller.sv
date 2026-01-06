//------------------------------------------------------------------------------
// ANN Controller 
//------------------------------------------------------------------------------


`include "../common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;

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

    //======================================================================
    // Controller <-> ANN Core
    //======================================================================
    output logic                     ann_reset,        
    output logic                     weight_write_en,  // write enable for weight programming
    output logic [SELECTOR_WIDTH-1:0] row_selector,     // row selector: block[1:0] + sub_block[1:0] + row[2:0]
    output logic [SELECTOR_WIDTH-1:0] col_selector,     // column selector: block[1:0] + sub_block[1:0] + col[2:0]
    input  logic                     op_done,          

    //======================================================================
    // Controller <-> Input Buffer
    //======================================================================
    output logic [5:0]               buf_reg_add,      
    output logic [2:0]               buf_reg_ctrl,     // buffer control signals
    output logic                     buf_read_write,   // 1 = write, 0 = read
    input  logic                     buf_ready,        

    //======================================================================
    // Status to higher-level
    //======================================================================
    output logic                     busy              
);

    //--------------------------------------------------------------------------
    // FSM States (using package type)
    //--------------------------------------------------------------------------
    controller_state_t state, next_state;

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
    // Buffer Address and Weight Selection Mapping
    //--------------------------------------------------------------------------
   
    `comb(
        // Extract unique weight index within sub-block 
        // This is weight_addr_reg[5:0] = {row_id[2:0], col_id[2:0]}
        buf_addr_reg = weight_addr_reg[5:1];  // Divide unique weight index by 2
        weight_sel   = weight_addr_reg[0];     // Select weight[0] or weight[1] within location
    )

    //--------------------------------------------------------------------------
    // Mux Control Signal Generation for VERIFY and ERASE
    //--------------------------------------------------------------------------
    `comb(
        // ========== VERIFY state: set muxes to READ mode ==========
        if (state == S_VERIFY) begin
            // In VERIFY, select target row/col in READ mode
            for (int r = 0; r < SUB_BLOCK_ROWS; r++) begin
                if (r == row_id)
                    row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_READ};
                else
                    row_mux_ctrl[block_id][sub_block_id][r] = {1'b0, MUX_MODE_HIZ};
            end

            for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                if (c == col_id)
                    col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_READ};
                else
                    col_mux_ctrl[block_id][sub_block_id][c] = {1'b0, MUX_MODE_HIZ};
            end
        end

        // ========== ERASE state: set muxes to ERASE mode ==========
        if (state == S_ERASE) begin
            // In ERASE, select target row/col in ERASE mode for relevant sub-states
            if (erase_state == ERASE_SELECT || erase_state == ERASE_ENABLE ||
                erase_state == ERASE_PULSE  || erase_state == ERASE_DISABLE) begin

                for (int r = 0; r < SUB_BLOCK_ROWS; r++) begin
                    if (r == row_id)
                        row_mux_ctrl[block_id][sub_block_id][r] = {1'b1, MUX_MODE_ERASE};
                    else
                        row_mux_ctrl[block_id][sub_block_id][r] = {1'b0, MUX_MODE_HIZ};
                end

                for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                    if (c == col_id)
                        col_mux_ctrl[block_id][sub_block_id][c] = {1'b1, MUX_MODE_ERASE};
                    else
                        col_mux_ctrl[block_id][sub_block_id][c] = {1'b0, MUX_MODE_HIZ};
                end
            end
        end
    )

    //--------------------------------------------------------------------------
    // State register and weight address counter
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            weight_addr_reg    <= '0;
            weight_prog_done   <= 1'b0;
        end else begin
            state <= next_state;
            
            // Reset weight address when entering PROGRAM_WEIGHTS state
            if (state == S_IDLE && next_state == S_PROGRAM_WEIGHTS) begin
                weight_addr_reg <= '0;
                weight_prog_done <= 1'b0;
            end
            
            // When a programming operation completes, mark if this was the last
            // programmed weight but do NOT advance the address yet — verification
            // must occur for the just-programmed location.
            if (state == S_PROGRAM_WEIGHTS && op_done) begin
                if (weight_addr_reg >= (TOTAL_WEIGHT_LOCATIONS - 1)) begin
                    weight_prog_done <= 1'b1;
                end
            end

            // Advance the address only after successful verification when
            // transitioning back into PROGRAM_WEIGHTS.
            if (state == S_VERIFY && next_state == S_PROGRAM_WEIGHTS) begin
                if (weight_addr_reg < (TOTAL_WEIGHT_LOCATIONS - 1)) begin
                    weight_addr_reg <= weight_addr_reg + 1'b1;
                    // Note: buf_addr_reg and weight_sel are computed from weight_addr_reg
                    // in combinational logic, so no need to update them here
                end else begin
                    weight_prog_done <= 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // VERIFY and ERASE sub-FSM state registers
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

            // -------- retry counter: increment on each ERASE cycle completion --------
            if (state == S_PROGRAM_WEIGHTS) begin
                // Reset retry counter when starting to program new weight
                if (op_done && weight_addr_reg < (TOTAL_WEIGHT_LOCATIONS - 1)) begin
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

        unique case (state)

            //--------------------------------------------------------------
            // IDLE: wait for valid signal from parallel interface
            //--------------------------------------------------------------
            S_IDLE: begin
                busy            = 1'b0;
                buf_reg_add     = '0;
                buf_reg_ctrl    = CTRL_IDLE;
                buf_read_write  = 1'b0;
                
                // When valid signal arrives, start programming weights
                if (valid)
                    next_state = S_PROGRAM_WEIGHTS;
                else
                    next_state = S_IDLE;
            end

            //--------------------------------------------------------------
            // PROGRAM_WEIGHTS: program weights into ANN core
            //--------------------------------------------------------------
           
            S_PROGRAM_WEIGHTS: begin
                busy            = 1'b1;
                weight_write_en = 1'b1;  
                
                // Buffer control: read weight data from buffer
                buf_reg_add     = {{(6-BUF_ADDR_WIDTH){1'b0}}, buf_addr_reg};  
                buf_reg_ctrl    = CTRL_WEIGHT_READ;  
                buf_read_write  = 1'b0;              // Read from buffer
                
                
                
                // After programming current weight, move to VERIFY
                if (op_done) begin
                    next_state = S_VERIFY;
                end else begin
                    next_state = S_PROGRAM_WEIGHTS;
                end
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
                            if (expected_weight > weight_read_data)
                                program_stronger = 1'b1;
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
                            // block will advance `weight_addr_reg` when entering
                            // PROGRAM_WEIGHTS from VERIFY.
                            next_state = S_PROGRAM_WEIGHTS;
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
                            // Retry: go back to PROGRAM_WEIGHTS (with adaptive voltage if program_stronger set)
                            next_state = S_PROGRAM_WEIGHTS;
                            erase_next = ERASE_HIZ;
                        end else begin
                            // Max retries exceeded, set error_flag and return to idle
                            error_flag = 1'b1;
                            next_state = S_IDLE;
                            erase_next = ERASE_HIZ;
                        end
                    end
                    
                    default: begin
                        erase_next = ERASE_HIZ;
                    end
                endcase
            end

            default: next_state = S_IDLE;

        endcase
    )

endmodule