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
            
            // Increment weight address during programming when operation is done
            if (state == S_PROGRAM_WEIGHTS && op_done) begin
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
                
                
                
                // Check if all weights are programmed
                if (weight_prog_done) begin
                    // All weights programmed, return to idle
                    next_state = S_IDLE;
                end else if (op_done) begin
                    // Current weight programmed, continue to next weight
                    next_state = S_PROGRAM_WEIGHTS;
                end else begin
                    // Wait for current weight programming to complete
                    next_state = S_PROGRAM_WEIGHTS;
                end
            end

            default: next_state = S_IDLE;

        endcase
    )

endmodule