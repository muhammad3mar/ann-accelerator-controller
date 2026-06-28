//------------------------------------------------------------------------------
// ANN Controller 
//------------------------------------------------------------------------------




import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module ann_controller #(
    parameter int ADDR_WIDTH   = controller_pkg::DEFAULT_ADDR_WIDTH,
    parameter int WEIGHT_WIDTH = controller_pkg::DEFAULT_WEIGHT_WIDTH,
    parameter bit USE_WEIGHT_PULSE_LUT = 1'b1,
    parameter string WEIGHT_PULSE_LUT_FILE = "target/Controller/programming_inputs/weight_pulse_lut.mem"
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
    // ann_core_word: [31:24] = host data byte (quantized weight in [27:24] for PROG);
    //                [23:0] = {PE, SA, col, row} one-hot (see host_addr_to_ann_addr_out)
    // pulses: operation / pulse mode toward core (READ/PROG/ERASE/INF)
    //======================================================================
    output logic                     ann_reset,
    // Core handshake: asserted to advance PROG_SELECT->PROG_WRITE, PROG_WAIT_ACK->PROG_COMPLETE,
    // ERASE_SELECT->ERASE_PULSE, ERASE_WAIT_ACK->ERASE_COMPLETE (see program/erase sub-FSMs).
    input  logic                     op_done,
    output logic [31:0]              ann_core_word,
    output logic [2:0]               pulses,

    // ADC/quantizer input for verification read (from ANN core)
    input  logic [3:0]               weight_read_data,  // Read weight from memristor during VERIFY

    //======================================================================
    // Controller <-> Input Buffer
    //======================================================================
    output logic [5:0]               buf_reg_add,      
    output logic [2:0]               buf_reg_ctrl,     // buffer control signals
    output logic                     buf_read_write,   // 1 = write, 0 = read
    output logic [2:0]               buf_bit_sel,     // bit index 0-7 for D0-D7 bit-serial output (LSB-first)
    output logic [7:0]               buf_data_out,     // Captured data for buffer write (from parallel interface)
    input  logic                     buf_ready,
    input  logic [BUFFER_DATA_WIDTH-1:0] buf_data, // Data from input buffer (full byte at current addr)        

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
        VERIFY_IDLE,
        VERIFY_WAIT,
        VERIFY_CHECK,
        VERIFY_DONE
    } verify_state_t;

    verify_state_t verify_state, verify_next;

    erase_state_t erase_state, erase_next;

    //--------------------------------------------------------------------------
    // VERIFY and ERASE sub-FSM Signals
    //--------------------------------------------------------------------------
    // Retry counter (counts how many ERASE attempts for current weight)
    logic [1:0] retry_cnt;     // 0..3

    // Re-program counter (counts PROG retries without ERASE when read < expected)
    logic [1:0] prog_retry_cnt;  // 0..MAX_PROG_RETRIES

    // S_VERIFY read pulse train: VERIFY_IDLE is cycle 0; VERIFY_WAIT uses verify_pulse_idx 1..PULSE_TOTAL_READ-1
    logic [7:0] verify_pulse_idx;

    // Outputs (or internal signals connected to outputs)
    logic        weight_read_en;      // enable read in VERIFY (internal; use weight_read_data input port)
    logic [3:0]  expected_weight;     // from buffer/host
    // VERIFY_CHECK: set when mismatch forces entry to S_ERASE (max reprog or over-programmed)
    logic        verify_failure_starts_erase;
    // ERASE_COMPLETE: set when erase retry_cnt reached limit and controller aborts to idle
    logic        erase_max_retries_exhausted;

   
    logic        program_stronger;

    // Host CMD_ERASE from S_IDLE: after erase sub-FSM, return to idle (no PROG/VERIFY).
    // Verify-failure path clears this when entering S_ERASE from S_VERIFY.
    logic        erase_from_host;

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
    logic [2:0] bit_count;     // Bit index (0-7) during S_COMPUTE for D0-D7 bit-serial output

    //--------------------------------------------------------------------------
    // Pulse Timing (per spec: T*N cycles per mode)
    //--------------------------------------------------------------------------
    logic [7:0] pulse_cnt;     // Cycle counter for pulse duration
    logic       pulse_done;    // Asserted when pulse_cnt reaches total for current mode
    logic [7:0] pulse_total;   // Total cycles for current mode (T*N or max(8, T*N) for INF)

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

   
    logic [7:0] weight_pulse_cycles_lut [0:15];

    initial
        $readmemh(WEIGHT_PULSE_LUT_FILE, weight_pulse_cycles_lut);

    // LUT row for expected_weight: repeat count for the (TPROG x PULSE_NUM_PROG) macro train
    wire [7:0] lut_entry_expected_weight;
    assign lut_entry_expected_weight = weight_pulse_cycles_lut[expected_weight];

    //--------------------------------------------------------------------------
    // Address Parsing: Direct address from parallel interface (all commands)
    //--------------------------------------------------------------------------
    `comb(
        // All commands use direct address from host packet
        parse_ann_address(address_reg, block_id, sub_block_id, row_id, col_id);
        weight_addr_reg = {block_id, sub_block_id, row_id, col_id};
    )

    //--------------------------------------------------------------------------
    // Packed ANN core bus: host data byte + one-hot address tail
    //--------------------------------------------------------------------------
    logic [7:0] data_byte_for_ann;
    always_comb begin
        data_byte_for_ann = 8'b0;
        unique case (state)
            S_PROGRAM,
            S_VERIFY,
            S_READ,
            S_ERASE: data_byte_for_ann = data_reg;
            S_COLLECT_DATA: data_byte_for_ann = data;
            default: data_byte_for_ann = 8'b0;
        endcase
    end

    always_comb begin
        if (state == S_IDLE)
            ann_core_word = 32'b0;
        else
            ann_core_word = pack_ann_core_word(data_byte_for_ann, block_id, sub_block_id, row_id, col_id);
    end

    //--------------------------------------------------------------------------
    //--------------------------------------------------------------------------
    // Pulse total and done (burst train: N bursts of T cycles, (N-1) gaps of PULSE_GAP)
    //--------------------------------------------------------------------------
    `comb(
        automatic int Tp;
        automatic int Np;
        pulse_total = 8'd0;
        if (state == S_READ)
            pulse_total = PULSE_TOTAL_READ[7:0];
        else if (state == S_PROGRAM && prog_state == PROG_WRITE) begin
            if (!USE_WEIGHT_PULSE_LUT) begin
                Tp = TPROG;
                Np = PULSE_NUM_PROG;
                pulse_total = pulse_train_total(Tp, Np, PULSE_GAP)[7:0];
            end else if (prog_retry_cnt > 2'd0) begin
                Tp = 1;
                Np = 1;
                pulse_total = pulse_train_total(Tp, Np, PULSE_GAP)[7:0];
            end else begin
                // First PROG: R copies of macro train, PULSE_GAP HIZ between copies (R from LUT)
                automatic int Rlut;
                automatic int Mmacro;
                Mmacro = pulse_train_total(TPROG, PULSE_NUM_PROG, PULSE_GAP);
                Rlut = int'(weight_pulse_cycles_lut[expected_weight]);
                if (Rlut < 1)
                    Rlut = 1;
                pulse_total = 8'(pulse_lut_macro_repeat_total(Rlut, Mmacro, PULSE_GAP));
            end
        end
        else if (state == S_ERASE && erase_state == ERASE_PULSE)
            pulse_total = PULSE_TOTAL_ERASE[7:0];
        else if (state == S_COMPUTE)
            pulse_total = PULSE_TOTAL_INF[7:0];

        pulse_done = (pulse_total > 8'd0) && (pulse_cnt >= pulse_total - 1'b1);
    )

    //--------------------------------------------------------------------------
    // 3-bit Pulse Output to ANN Core (pulsed: active mode only during burst high phases)
    //--------------------------------------------------------------------------
    `comb(
        automatic int Tv;
        automatic int Tpp;
        automatic int Npp;
        automatic logic rd_on;
        automatic logic pg_on;
        automatic logic er_on;
        automatic logic inf_on;
        pulses = 3'b000;
        // S_READ
        if (state == S_READ) begin
            rd_on = pulse_train_active(int'(pulse_cnt), TREAD, PULSE_NUM_READ, PULSE_GAP);
            pulses = rd_on ? PULSE_MODE_READ : PULSE_MODE_HIZ;
        end
        else if (state == S_PROGRAM && prog_state == PROG_WRITE) begin
            if (!USE_WEIGHT_PULSE_LUT) begin
                Tpp = TPROG;
                Npp = PULSE_NUM_PROG;
                pg_on = pulse_train_active(int'(pulse_cnt), Tpp, Npp, PULSE_GAP);
            end else if (prog_retry_cnt > 2'd0) begin
                Tpp = 1;
                Npp = 1;
                pg_on = pulse_train_active(int'(pulse_cnt), Tpp, Npp, PULSE_GAP);
            end else begin
                automatic int Mmacro;
                automatic int Rlut;
                Mmacro = pulse_train_total(TPROG, PULSE_NUM_PROG, PULSE_GAP);
                Rlut = int'(weight_pulse_cycles_lut[expected_weight]);
                if (Rlut < 1)
                    Rlut = 1;
                pg_on = pulse_lut_macro_repeat_active(int'(pulse_cnt), Rlut, Mmacro, TPROG, PULSE_NUM_PROG, PULSE_GAP);
            end
            pulses = pg_on ? PULSE_MODE_PROG : PULSE_MODE_HIZ;
        end
        else if (state == S_ERASE && erase_state == ERASE_PULSE) begin
            er_on = pulse_train_active(int'(pulse_cnt), TERASE, PULSE_NUM_ERASE, PULSE_GAP);
            pulses = er_on ? PULSE_MODE_ERASE : PULSE_MODE_HIZ;
        end
        else if (state == S_VERIFY && (verify_state == VERIFY_IDLE || verify_state == VERIFY_WAIT)) begin
            Tv = (verify_state == VERIFY_IDLE) ? 0 : int'(verify_pulse_idx);
            rd_on = pulse_train_active(Tv, TREAD, PULSE_NUM_READ, PULSE_GAP);
            pulses = rd_on ? PULSE_MODE_READ : PULSE_MODE_HIZ;
        end
        else if (state == S_COMPUTE) begin
            inf_on = pulse_train_active(int'(pulse_cnt), TINF, PULSE_NUM_INF, PULSE_GAP);
            pulses = inf_on ? PULSE_MODE_INF : PULSE_MODE_HIZ;
        end
    )
    
    //--------------------------------------------------------------------------
    // Buffer Address and Weight Selection Mapping
    //--------------------------------------------------------------------------
    `comb(
        // For PROG/VERIFY: use address_reg[5:0]; else use buffer_idx for legacy
        buf_addr_reg = (state == S_PROGRAM || state == S_VERIFY) ? address_reg[5:0] : buffer_idx_reg[WEIGHT_COUNT_WIDTH-1:1];
        weight_sel   = buffer_idx_reg[0];
        
        // Extract weight data from buffer
        // For PROG and VERIFY (direct address): weight in buf_data[3:0] at address_reg[5:0]
        if (state == S_PROGRAM || state == S_VERIFY) begin
            weight_from_buffer = buf_data[3:0];
        end else begin
            // Legacy: use weight_sel for buffer_idx mapping
            if (weight_sel == 1'b0) begin
                weight_from_buffer = buf_data[3:0];
            end else begin
                weight_from_buffer = buf_data[7:4];
            end
        end
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
            bit_count          <= '0;
            pulse_cnt          <= '0;

            // Keep these for ERASE/VERIFY compatibility
            buffer_idx_reg     <= '0;
            weight_count_reg   <= DEFAULT_NUM_WEIGHTS;  // Default: 640 weights
            weight_count_valid <= 1'b0;
            weight_prog_done   <= 1'b0;
            matrix_rows        <= DEFAULT_MATRIX_ROWS;  // Default: 10 rows
            matrix_cols        <= DEFAULT_MATRIX_COLS;  // Default: 64 columns
            erase_from_host    <= 1'b0;
        end else begin
            state <= next_state;
            prog_state <= next_prog_state;

            // Host-initiated erase vs verify-driven erase
            if (state == S_VERIFY && next_state == S_ERASE)
                erase_from_host <= 1'b0;
            else if (state == S_IDLE && valid && cmd == CMD_ERASE)
                erase_from_host <= 1'b1;
            else if (state == S_ERASE && next_state == S_IDLE)
                erase_from_host <= 1'b0;
            
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
            end else if (state == S_COMPUTE) begin
                // Advance bit index for D0-D7 bit-serial output (LSB-first, wrap after 8 cycles)
                bit_count <= (bit_count == 3'd7) ? 3'd0 : bit_count + 1'b1;
            end else if (state != S_COMPUTE && next_state == S_COMPUTE) begin
                bit_count <= '0;
            end

            // Pulse timing counter: reset on enter, increment until done
            if ((state != S_READ && next_state == S_READ) ||
                (state == S_PROGRAM && prog_state != PROG_WRITE && next_prog_state == PROG_WRITE) ||
                (state == S_ERASE && erase_state != ERASE_PULSE && erase_next == ERASE_PULSE) ||
                (state != S_COMPUTE && next_state == S_COMPUTE)) begin
                pulse_cnt <= 8'd0;
            end else if (((state == S_READ && next_state == S_READ) ||
                         (state == S_PROGRAM && prog_state == PROG_WRITE && next_prog_state == PROG_WRITE) ||
                         (state == S_ERASE && erase_state == ERASE_PULSE && erase_next == ERASE_PULSE) ||
                         (state == S_COMPUTE && next_state == S_COMPUTE)) && !pulse_done) begin
                pulse_cnt <= pulse_cnt + 1'b1;
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
            
            // Check completion during programming (direct address: one weight per PROG command)
            if (state == S_PROGRAM && prog_state == PROG_COMPLETE) begin
                weight_prog_done <= 1'b1;  // Direct address flow: one weight per command
            end
        end
    end

    //--------------------------------------------------------------------------
    // VERIFY, ERASE, and PROGRAM sub-FSM state registers
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            verify_state     <= VERIFY_IDLE;
            erase_state      <= ERASE_HIZ;
            retry_cnt        <= 2'd0;
            prog_retry_cnt   <= 2'd0;
            verify_pulse_idx <= 8'd0;
            program_stronger <= 1'b0;
        end else begin
            verify_state <= verify_next;
            erase_state  <= erase_next;
            // prog_state is updated in the main state register block above

            // -------- retry_cnt and prog_retry_cnt: reset on success (VERIFY_DONE) --------
            if (state == S_VERIFY && verify_state == VERIFY_DONE) begin
                retry_cnt      <= 2'd0;
                prog_retry_cnt <= 2'd0;
                program_stronger <= 1'b0;
            end
            // -------- prog_retry_cnt: increment when re-progging without ERASE --------
            else if (state == S_VERIFY && verify_state == VERIFY_CHECK && weight_read_data < expected_weight && prog_retry_cnt < controller_pkg::MAX_PROG_RETRIES) begin
                prog_retry_cnt <= prog_retry_cnt + 1'b1;
            end
            // -------- prog_retry_cnt: reset when going to ERASE (over-programmed or max re-prog exceeded) --------
            else if (state == S_VERIFY && verify_state == VERIFY_CHECK && (weight_read_data > expected_weight || prog_retry_cnt >= controller_pkg::MAX_PROG_RETRIES)) begin
                prog_retry_cnt <= 2'd0;
            end
            // -------- retry_cnt: increment on ERASE_COMPLETE; prog_retry_cnt reset --------
            else if (state == S_ERASE && erase_state == ERASE_COMPLETE) begin
                retry_cnt      <= retry_cnt + 1'b1;
                prog_retry_cnt <= 2'd0;
            end
            // -------- retry_cnt: legacy reset when advancing buffer index --------
            else if (state == S_PROGRAM && prog_state == PROG_COMPLETE && buffer_idx_reg < (weight_count_reg - 1)) begin
                retry_cnt <= 2'd0;
                program_stronger <= 1'b0;
            end

            // -------- verify pulse index (aligned with PULSE_TOTAL_READ burst train) --------
            if (state != S_VERIFY) begin
                verify_pulse_idx <= 8'd0;
            end else if (verify_state == VERIFY_IDLE) begin
                verify_pulse_idx <= 8'd1;
            end else if (verify_state == VERIFY_WAIT && verify_next == VERIFY_WAIT) begin
                verify_pulse_idx <= verify_pulse_idx + 8'd1;
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

        
        // Default buffer address (will be overridden in each state)
        buf_reg_add      = {{(6-BUF_ADDR_WIDTH){1'b0}}, buf_addr_reg};
        buf_reg_ctrl     = CTRL_IDLE;
        buf_read_write   = 1'b0;   // 0 = read, 1 = write
        buf_bit_sel      = (state == S_COMPUTE) ? bit_count : 3'd0;

        busy             = 1'b0;

        next_state       = state;
        next_prog_state  = prog_state;

        verify_failure_starts_erase = 1'b0;
        erase_max_retries_exhausted = 1'b0;

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
            // PROGRAM: program weights into ANN (buffer load + program sub-FSM)
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
                        next_prog_state = PROG_SELECT;
                    end
                    
                    PROG_SELECT: begin
                        next_prog_state = op_done ? PROG_WRITE : PROG_SELECT;
                    end
                    
                    PROG_WRITE: begin
                        // Hold PROG pulses until train done; then wait core op_done
                        if (pulse_done)
                            next_prog_state = PROG_WAIT_ACK;
                        else
                            next_prog_state = PROG_WRITE;
                    end
                    
                    PROG_WAIT_ACK: begin
                        next_prog_state = op_done ? PROG_COMPLETE : PROG_WAIT_ACK;
                    end
                    
                    PROG_COMPLETE: begin
                        // Weight programming complete, proceed to verify
                        next_state = S_VERIFY;
                        next_prog_state = PROG_HIZ;  // Reset for next weight (if any)
                    end
                    
                    default: begin
                        next_prog_state = PROG_HIZ;
                    end
                endcase
            end

            //--------------------------------------------------------------
            // VERIFY: Verify programmed weights (uses direct address)
            //--------------------------------------------------------------
            S_VERIFY: begin
                busy            = 1'b1;
                buf_reg_add     = address_reg[5:0];   // Read expected weight from buffer
                buf_reg_ctrl    = CTRL_WEIGHT_READ;
                buf_read_write  = 1'b0;               // Read from buffer
                weight_read_en  = (verify_state == VERIFY_IDLE) ? 1'b1 : 1'b0;
                
                // VERIFY sub-FSM logic
                unique case (verify_state)
                    VERIFY_IDLE: begin
                        // Initiate read; single-cycle train skips WAIT
                        if (PULSE_TOTAL_READ <= 8'd1)
                            verify_next = VERIFY_CHECK;
                        else
                            verify_next = VERIFY_WAIT;
                    end
                    
                    VERIFY_WAIT: begin
                        // One cycle per burst-train index (see verify_pulse_idx seq block)
                        if (verify_pulse_idx == PULSE_TOTAL_READ[7:0] - 8'd1)
                            verify_next = VERIFY_CHECK;
                        else
                            verify_next = VERIFY_WAIT;
                    end
                    
                    VERIFY_CHECK: begin
                        // Compare read weight with expected weight
                        if (weight_read_data == expected_weight) begin
                            verify_next = VERIFY_DONE;  // Match: continue to next weight
                        end else if (weight_read_data < expected_weight) begin
                            // Under-programmed: re-apply PROG pulses (no ERASE)
                            if (prog_retry_cnt < controller_pkg::MAX_PROG_RETRIES) begin
                                next_state = S_PROGRAM;
                                next_prog_state = PROG_HIZ;
                            end else begin
                                // Max re-prog attempts exceeded, fall back to ERASE
                                verify_failure_starts_erase = 1'b1;
                                next_state = S_ERASE;
                            end
                            verify_next = VERIFY_IDLE;
                        end else begin
                            // Over-programmed: ERASE then retry
                            verify_failure_starts_erase = 1'b1;
                            next_state = S_ERASE;
                            verify_next = VERIFY_IDLE;
                        end
                    end
                    
                    VERIFY_DONE: begin
                        // Direct address flow: one weight per PROG command, return to idle
                        next_state = S_IDLE;
                        verify_next = VERIFY_IDLE;
                    end
                    
                    default: begin
                        verify_next = VERIFY_IDLE;
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
                        // Erase sequence: outputs high-Z / idle phase
                        erase_next = ERASE_SELECT;
                    end
                    
                    ERASE_SELECT: begin
                        // Address path setup; wait core op_done before pulse phase
                        erase_next = op_done ? ERASE_PULSE : ERASE_SELECT;
                    end
                    
                    ERASE_PULSE: begin
                        // Hold erase pulse for Terase*Pulse_num_erase cycles (per spec)
                        if (pulse_done)
                            erase_next = ERASE_WAIT_ACK;
                        else
                            erase_next = ERASE_PULSE;
                    end
                    
                    ERASE_WAIT_ACK: begin
                        // Pulse train finished; wait op_done before completing erase
                        erase_next = op_done ? ERASE_COMPLETE : ERASE_WAIT_ACK;
                    end
                    
                    ERASE_COMPLETE: begin
                        // Host CMD_ERASE: finish after erase; verify-failure path reprograms
                        if (erase_from_host) begin
                            next_state = S_IDLE;
                            next_prog_state = PROG_HIZ;
                            erase_next = ERASE_HIZ;
                        end else if (retry_cnt < 3) begin
                            // Retry: go back to PROGRAM (with adaptive voltage if program_stronger set)
                            next_state = S_PROGRAM;
                            next_prog_state = PROG_HIZ;
                            erase_next = ERASE_HIZ;
                        end else begin
                            // Erase retry budget exhausted; abort verify/recovery and return to idle
                            erase_max_retries_exhausted = 1'b1;
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
                
                // Pulses held for Tread*Pulse_num_read cycles (per spec)
                if (pulse_done) begin
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
                // Use current counters directly so each valid beat maps 1:1 to target address.
                // (Using registered buf_write_addr introduces a one-cycle lag and can overwrite.)
                buf_reg_add     = (row_count * 8) + data_count;
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
                buf_reg_add     = '0;                 // Read first 8 pixels (addr 0..7) for bit-serial D0-D7
                buf_reg_ctrl    = CTRL_COMPUTE;
                buf_read_write  = 1'b0;              // Read from buffer
                buf_bit_sel     = bit_count;         // LSB-first bit index 0..7 each cycle

                // Pulses held for max(8, Tinf*Pulse_num_inf) cycles (per spec; min 8 for bit-serial)
                if (pulse_done) begin
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