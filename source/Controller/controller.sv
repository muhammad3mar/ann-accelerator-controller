//------------------------------------------------------------------------------
// ANN Controller - Phase 1 (SystemVerilog, clean version)
//------------------------------------------------------------------------------
// - Parallel interface only moves data into buffers (not shown here).
// - Controller:
//      * drives ANN core control signals
//      * optionally drives buffer control signals
//      * waits for buf_ready and op_done
//      * exposes busy + result_ready
//------------------------------------------------------------------------------

module ann_controller #(
    parameter int ADDR_WIDTH   = 8,
    parameter int WEIGHT_WIDTH = 16
) (
    //======================================================================
    // Global
    //======================================================================
    input  logic                     clk,
    input  logic                     rst_n,

    //======================================================================
    // Controller <-> Parallel Interface
    //======================================================================
     input logic                     valid, // check if the data is valid 

    //======================================================================
    // Controller <-> ANN Core
    //======================================================================
    output logic                     ann_reset,        // reset ANN/IMC
    output logic                     weight_write_en,  // write one weight
    output logic [ADDR_WIDTH-1:0]    weight_addr,      // addr for weight write
    output logic [WEIGHT_WIDTH-1:0]  weight_wdata,     // data for weight write
    output logic                     compute_start,    // start forward pass

    input  logic                     op_busy,          // optional (not used now)
    input  logic                     op_done,          // operation finished

    //======================================================================
    // Controller <-> Buffer Regfile
    //======================================================================
    // NOTE:
    //  - In this clean version, we *expose* these signals,
    //    but we don't hard-code their values to specific meanings.
    //  - You will define how buf_reg_add / buf_reg_ctrl / buf_read_write
    //    are used in your datapath and possibly extend the FSM later.
    //======================================================================
    output logic [5:0]               buf_reg_add,      // REG_ADD[5:0]
    output logic [2:0]               buf_reg_ctrl,     // REG_CTRL[2:0]
    output logic                     buf_read_write,   // 1 = write, 0 = read
    input  logic                     buf_ready,        // buffer ready / data valid

    //======================================================================
    // Status to higher-level
    //======================================================================
    output logic                     busy,             // controller busy
    output logic                     result_ready      // inference result valid
);

    //--------------------------------------------------------------------------
    // FSM States
    //--------------------------------------------------------------------------

    typedef enum logic [2:0] {
        S_IDLE     = 3'd0,
        S_RESET    = 3'd1,
        S_PROGRAM    = 3'd2,
        S_COMPUTE  = 3'd3,
        S_RESULT   = 3'd4
    } state_t;

    state_t state, next_state;

    // Latched weight info
    logic [ADDR_WIDTH-1:0]   weight_addr_q;
    logic [WEIGHT_WIDTH-1:0] weight_wdata_q;

    //--------------------------------------------------------------------------
    // Latch weight info when WRITE is requested in IDLE
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_addr_q  <= '0;
            weight_wdata_q <= '0;
        end else begin
            if (state == S_IDLE && req_write) begin
                weight_addr_q  <= weight_addr_in;
                weight_wdata_q <= weight_wdata_in;
            end
        end
    end

    //--------------------------------------------------------------------------
    // State register
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    //--------------------------------------------------------------------------
    // Main FSM: outputs + next-state logic
    //--------------------------------------------------------------------------

    always_comb begin
        // Defaults: ANN core control
        ann_reset        = 1'b0;
        weight_write_en  = 1'b0;
        weight_addr      = weight_addr_q;
        weight_wdata     = weight_wdata_q;
        compute_start    = 1'b0;

        // Defaults: buffer control (for now, neutral)
        buf_reg_add      = 6'd0;
        buf_reg_ctrl     = 3'd0;
        buf_read_write   = 1'b0;   // read by default

        // Defaults: status
        busy             = 1'b0;
        result_ready     = 1'b0;

        next_state       = state;

        unique case (state)

            //--------------------------------------------------------------
            // IDLE: wait for any request (reset / write / compute)
            //--------------------------------------------------------------
            S_IDLE: begin
                busy = 1'b0;
                next_state = S_PROGRAM;
              
            end

            //--------------------------------------------------------------
            // RESET: reset ANN core (and possibly buffers later)
            //--------------------------------------------------------------
            S_RESET: begin
                busy      = 1'b1;
                ann_reset = 1'b1;

                // You can later add buffer commands here using buf_reg_*.

                if (op_done)
                    next_state = S_IDLE;
                else
                    next_state = S_RESET;
            end

            //--------------------------------------------------------------
            // program one weight
            //--------------------------------------------------------------
            S_PROGRAM: begin
                busy           = 1'b1;
                weight_write_en= 1'b1;
                weight_addr    = weight_addr_q;
                weight_wdata   = weight_wdata_q;

                // You can later connect buf_reg_* here if weight writes
                // also need to touch buffer registers.

                if (op_done)
                    next_state = S_IDLE;
                else
                    next_state = S_PROGRAM;
            end

            //--------------------------------------------------------------
            // COMPUTE: run forward pass (inference)
            // - stays in this state until buffer is ready AND op_done is seen
            //--------------------------------------------------------------
            S_COMPUTE: begin
                busy = 1'b1;

                // For now we only use buf_ready as a condition.
                // You can later drive buf_reg_add / buf_reg_ctrl with
                // meaningful values once you finalize buffer mapping.

                if (buf_ready)
                    compute_start = 1'b1;
                else
                    compute_start = 1'b0;

                if (op_done)
                    next_state = S_RESULT;
                else
                    next_state = S_COMPUTE;
            end

            //--------------------------------------------------------------
            // RESULT: one-cycle pulse indicating result is valid in output buffer
            //--------------------------------------------------------------
            S_RESULT: begin
                busy         = 1'b1;
                result_ready = 1'b1;
                next_state   = S_IDLE;
            end

            default: next_state = S_IDLE;

        endcase
    end

endmodule