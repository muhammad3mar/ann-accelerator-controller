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
        S_ERASE         = 4'd4,  // Erase weights 
        S_READ          = 4'd5,  // Read weight from memristor
        S_COLLECT_DATA  = 4'd6,  // Collect data for inference (INF command)
        S_COMPUTE       = 4'd7,  // Inference computation phase
        S_RESULT        = 4'd8   // Output classification results
    } controller_state_t;

    //--------------------------------------------------------------------------
    // ANN Architecture — primary knobs (user configures)
    //--------------------------------------------------------------------------
    // NUM_PE / NUM_SA / SA_ROWS / SA_COLS should be powers of 2 for one-hot
    // decoders (default: 4 / 4 / 8 / 8). NUM_SA must be a perfect square so
    // SA_PER_AXIS matches the 2-D sub-array grid used by matrix mapping.
    // $clog2(N) = ceil(log2(N)) — correct binary width even if N is not a power of 2.
    //--------------------------------------------------------------------------
    localparam int NUM_PE   = 4;   // Number of PEs in the ANN array
    localparam int NUM_SA   = 4;   // Sub-arrays per PE
    localparam int SA_ROWS  = 8;   // Rows within one SA
    localparam int SA_COLS  = 8;   // Columns within one SA

    //--------------------------------------------------------------------------
    // Derived address field widths ($clog2 = ceiling log2)
    //--------------------------------------------------------------------------
    localparam int PE_ID_WIDTH  = $clog2(NUM_PE);   // binary PE index width
    localparam int SA_ID_WIDTH  = $clog2(NUM_SA);   // binary SA index width
    localparam int ROW_ID_WIDTH = $clog2(SA_ROWS);  // row within SA
    localparam int COL_ID_WIDTH = $clog2(SA_COLS);  // col within SA

    // Weight address: {pe_id, sa_id, row_id, col_id}
    localparam int WEIGHT_ADDR_WIDTH = PE_ID_WIDTH + SA_ID_WIDTH + ROW_ID_WIDTH + COL_ID_WIDTH;

    // Bit field positions (LSB = col, then row, SA, PE at MSB)
    localparam int COL_ID_LSB = 0;
    localparam int COL_ID_MSB = COL_ID_WIDTH - 1;
    localparam int ROW_ID_LSB = COL_ID_MSB + 1;
    localparam int ROW_ID_MSB = ROW_ID_LSB + ROW_ID_WIDTH - 1;
    localparam int SA_ID_LSB  = ROW_ID_MSB + 1;
    localparam int SA_ID_MSB  = SA_ID_LSB + SA_ID_WIDTH - 1;
    localparam int PE_ID_LSB  = SA_ID_MSB + 1;
    localparam int PE_ID_MSB  = PE_ID_LSB + PE_ID_WIDTH - 1;
    // Default (4×4×8×8): PE[9:8], SA[7:6], row[5:3], col[2:0]

    // Derived array geometry
    localparam int SA_PER_AXIS = 1 << (SA_ID_WIDTH / 2);  // √NUM_SA for square SA grid
    localparam int PE_ROWS     = SA_PER_AXIS * SA_ROWS;   // rows spanned per PE
    localparam int PE_COLS     = SA_PER_AXIS * SA_COLS;   // cols spanned per PE

    localparam int TOTAL_WEIGHT_LOCATIONS = NUM_PE * NUM_SA * SA_ROWS * SA_COLS;  // 1024
    localparam int UNIQUE_WEIGHTS_PER_SA  = SA_ROWS * SA_COLS;                     // 64

    //--------------------------------------------------------------------------
    // Buffer Address Constants
    //--------------------------------------------------------------------------
    localparam int BUF_ADDR_WIDTH = 5;
    localparam int BUF_MAX_ADDR   = 31;

    //--------------------------------------------------------------------------
    // Matrix Dimension Constants (for Generic Weight Mapping)
    //--------------------------------------------------------------------------
    localparam int MAX_MATRIX_ROWS     = 32;  // Max rows (limited by ANN core)
    localparam int MAX_MATRIX_COLS     = NUM_PE * PE_COLS;  // 64 = 4 PEs × 16 cols
    localparam int DEFAULT_MATRIX_ROWS = 10;  // For current 640-weight case (10×64)
    localparam int DEFAULT_MATRIX_COLS = 64;  // For current 640-weight case
    localparam int DEFAULT_NUM_WEIGHTS = DEFAULT_MATRIX_ROWS * DEFAULT_MATRIX_COLS;  // 640

    // Weight count tracking
    localparam int WEIGHT_COUNT_WIDTH = $clog2(TOTAL_WEIGHT_LOCATIONS);  // 10 for 1024
    localparam int MIN_WEIGHT_COUNT   = 1;
    localparam int MAX_WEIGHT_COUNT   = TOTAL_WEIGHT_LOCATIONS;  // 1024

    // Max re-program attempts without ERASE (when read < expected)
    localparam int MAX_PROG_RETRIES = 3;

    //--------------------------------------------------------------------------
    // Default Parameters
    //--------------------------------------------------------------------------
    localparam int DEFAULT_ADDR_WIDTH   = 8;
    localparam int DEFAULT_WEIGHT_WIDTH = 16;

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
    // T*: cycles each burst holds the active pulse mode (READ=001, PROG=010, etc.)
    // PULSE_NUM_*: number of bursts (repeats)
    // PULSE_GAP: HIZ (000) cycles between bursts (none after the last burst)
    // Total train length = N*T + max(0,N-1)*PULSE_GAP
    localparam int TREAD           = 2;  // Read pulse width (clock cycles)
    localparam int PULSE_NUM_READ  = 1;  // Number of read pulses
    localparam int TPROG           = 5;  // Program pulse width
    localparam int PULSE_NUM_PROG  = 1;  // Number of program pulses
    localparam int TERASE          = 2;  // Erase pulse width
    localparam int PULSE_NUM_ERASE = 1;  // Number of erase pulses
    localparam int TINF            = 8;  // Inference pulse width
    localparam int PULSE_NUM_INF   = 1;  // Number of inference pulses
    localparam int PULSE_GAP       = 1;  // Idle cycles between bursts

    // Total cycles for a burst train: N*T + (N-1)*G (returns 0 if N < 1)
    function automatic int pulse_train_total(input int T, input int N, input int G);
        int t_safe;
        t_safe = (T < 1) ? 1 : T;
        if (N < 1)
            return 0;
        return N * t_safe + (N - 1) * G;
    endfunction

    // True when cycle_idx falls inside an active burst (not a HIZ gap)
    function automatic logic pulse_train_active(
        input int cycle_idx,
        input int T,
        input int N,
        input int G
    );
        int t_safe, chunk, r, base;
        t_safe = (T < 1) ? 1 : T;
        if (N < 1 || cycle_idx < 0)
            return 1'b0;
        chunk = t_safe + G;
        for (r = 0; r < N; r++) begin
            base = r * chunk;
            if (cycle_idx >= base && cycle_idx < base + t_safe)
                return 1'b1;
        end
        return 1'b0;
    endfunction

    // Total cycles for R back-to-back copies of one macro train (length Mmacro),
    // separated by G HIZ cycles (no gap after the last copy). Used for LUT PROG.
    function automatic int pulse_lut_macro_repeat_total(input int R, input int Mmacro, input int G);
        int Rc;
        Rc = (R < 1) ? 1 : R;
        if (Mmacro < 1)
            return 0;
        return Rc * Mmacro + (Rc - 1) * G;
    endfunction

    // True when cyc is inside an active burst of the R-fold LUT macro train
    function automatic logic pulse_lut_macro_repeat_active(
        input int cyc,
        input int R,
        input int Mmacro,
        input int T,
        input int N,
        input int G
    );
        int Rc;
        int cum;
        int b;
        Rc = (R < 1) ? 1 : R;
        if (Mmacro < 1 || cyc < 0)
            return 1'b0;
        cum = 0;
        for (b = 0; b < Rc; b++) begin
            if (cyc >= cum && cyc < cum + Mmacro)
                return pulse_train_active(cyc - cum, T, N, G);
            cum += Mmacro;
            if (b < Rc - 1) begin
                if (cyc >= cum && cyc < cum + G)
                    return 1'b0;
                cum += G;
            end
        end
        return 1'b0;
    endfunction

    localparam int PULSE_TOTAL_READ     = pulse_train_total(TREAD, PULSE_NUM_READ, PULSE_GAP);
    localparam int PULSE_TOTAL_PROG     = pulse_train_total(TPROG, PULSE_NUM_PROG, PULSE_GAP);
    localparam int PULSE_TOTAL_ERASE    = pulse_train_total(TERASE, PULSE_NUM_ERASE, PULSE_GAP);
    localparam int PULSE_TOTAL_INF_BASE = pulse_train_total(TINF, PULSE_NUM_INF, PULSE_GAP);
    localparam int PULSE_TOTAL_INF      = (PULSE_TOTAL_INF_BASE >= 8) ? PULSE_TOTAL_INF_BASE : 8;  // min 8 for bit-serial

    // One-hot bus widths on ann_address (must match NUM_PE / NUM_SA / SA_ROWS / SA_COLS)
    localparam int PE_WIDTH       = NUM_PE;    // One-hot PE select
    localparam int SA_WIDTH       = NUM_SA;    // One-hot SA select
    localparam int ROW_WIDTH      = SA_ROWS;   // Row select mask (one-hot)
    localparam int COL_WIDTH      = SA_COLS;   // Column select mask (one-hot)
    localparam int ADDR_OUT_WIDTH = 32;        // PE[23:20], SA[19:16], col[15:8], row[7:0]

    // Convert binary PE/SA/row/col indices to 32-bit one-hot ANN address tail
    // Output: [7:0] row, [15:8] col, [19:16] SA, [23:20] PE (all one-hot)
    function automatic logic [ADDR_OUT_WIDTH-1:0] host_addr_to_ann_addr_out(
        input logic [PE_ID_WIDTH-1:0]  pe_id,
        input logic [SA_ID_WIDTH-1:0]  sa_id,
        input logic [ROW_ID_WIDTH-1:0] row_id,
        input logic [COL_ID_WIDTH-1:0] col_id
    );
        logic [PE_WIDTH-1:0]  pe_onehot;
        logic [SA_WIDTH-1:0]  sa_onehot;
        logic [ROW_WIDTH-1:0] row_onehot;
        logic [COL_WIDTH-1:0] col_onehot;
        pe_onehot  = (1 << pe_id);
        sa_onehot  = (1 << sa_id);
        row_onehot = (1 << row_id);
        col_onehot = (1 << col_id);
        return {pe_onehot, sa_onehot, col_onehot, row_onehot};
    endfunction

    // Map a strict 4-bit one-hot vector to a 2-bit binary index (default 0 if invalid)
    function automatic logic [1:0] onehot4_to_idx(input logic [3:0] oh);
        unique case (oh)
            4'b0001: return 2'd0;
            4'b0010: return 2'd1;
            4'b0100: return 2'd2;
            4'b1000: return 2'd3;
            default: return 2'd0;
        endcase
    endfunction

    // Map a strict 8-bit one-hot vector to a 3-bit binary index (default 0 if invalid)
    function automatic logic [2:0] onehot8_to_idx(input logic [7:0] oh);
        unique case (oh)
            8'b00000001: return 3'd0;
            8'b00000010: return 3'd1;
            8'b00000100: return 3'd2;
            8'b00001000: return 3'd3;
            8'b00010000: return 3'd4;
            8'b00100000: return 3'd5;
            8'b01000000: return 3'd6;
            8'b10000000: return 3'd7;
            default: return 3'd0;
        endcase
    endfunction

    // Decode {PE, SA, col, row} one-hot tail from ann_address[23:0] into binary indices
    function automatic void ann_address_decode(
        input logic [31:0] word,
        output logic [PE_ID_WIDTH-1:0]  o_pe_id,
        output logic [SA_ID_WIDTH-1:0]  o_sa_id,
        output logic [ROW_ID_WIDTH-1:0] o_row_id,
        output logic [COL_ID_WIDTH-1:0] o_col_id
    );
        o_pe_id  = onehot4_to_idx(word[23:20]);
        o_sa_id  = onehot4_to_idx(word[19:16]);
        o_col_id = onehot8_to_idx(word[15:8]);
        o_row_id = onehot8_to_idx(word[7:0]);
    endfunction

    // Pack host data byte [31:24] with one-hot PE/SA/col/row address [23:0]
    function automatic logic [31:0] pack_ann_address(
        input logic [7:0] data_byte,
        input logic [PE_ID_WIDTH-1:0]  pe_id,
        input logic [SA_ID_WIDTH-1:0]  sa_id,
        input logic [ROW_ID_WIDTH-1:0] row_id,
        input logic [COL_ID_WIDTH-1:0] col_id
    );
        logic [ADDR_OUT_WIDTH-1:0] tail;
        tail = host_addr_to_ann_addr_out(pe_id, sa_id, row_id, col_id);
        return {data_byte, tail[23:0]};
    endfunction

    //--------------------------------------------------------------------------
    // Programming Sequence Sub-States
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] {
        PROG_HIZ,
        PROG_SELECT,     // wait op_done (core/setup) before PROG_WRITE
        PROG_WRITE,
        PROG_WAIT_ACK,   // after pulse_done, wait op_done before PROG_COMPLETE
        PROG_COMPLETE
    } prog_sequence_state_t;

    // Erase sub-FSM (S_ERASE only)
    typedef enum logic [2:0] {
        ERASE_HIZ,
        ERASE_SELECT,    // wait op_done before ERASE_PULSE
        ERASE_PULSE,
        ERASE_WAIT_ACK,  // after pulse_done, wait op_done before ERASE_COMPLETE
        ERASE_COMPLETE
    } erase_state_t;

    //--------------------------------------------------------------------------
    // Helper Functions — weight-address field extractors
    //--------------------------------------------------------------------------

    // Extract binary PE index from packed weight address
    function automatic logic [PE_ID_WIDTH-1:0] get_pe_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[PE_ID_MSB:PE_ID_LSB];
    endfunction

    // Extract binary SA index from packed weight address
    function automatic logic [SA_ID_WIDTH-1:0] get_sa_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[SA_ID_MSB:SA_ID_LSB];
    endfunction

    // Extract row index within SA from packed weight address
    function automatic logic [ROW_ID_WIDTH-1:0] get_row_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[ROW_ID_MSB:ROW_ID_LSB];
    endfunction

    // Extract column index within SA from packed weight address
    function automatic logic [COL_ID_WIDTH-1:0] get_col_id(logic [WEIGHT_ADDR_WIDTH-1:0] addr);
        return addr[COL_ID_MSB:COL_ID_LSB];
    endfunction

    //--------------------------------------------------------------------------
    // Address Parsing Function for Direct Address Interface
    //--------------------------------------------------------------------------
    // Parse 16-bit parallel-interface address into PE/SA/row/col binary fields.
    // Format: {reserved[15:10], pe_id[9:8], sa_id[7:6], col_id[5:3], row_id[2:0]}
    // Note: col/row bit order here differs from the 10-bit packed weight address
    //       which is {pe_id, sa_id, row_id, col_id}.
    function automatic void parse_ann_address(
        input logic [15:0] address,
        output logic [PE_ID_WIDTH-1:0]  pe_id,
        output logic [SA_ID_WIDTH-1:0]  sa_id,
        output logic [ROW_ID_WIDTH-1:0] row_id,
        output logic [COL_ID_WIDTH-1:0] col_id
    );
        pe_id  = address[9:8];
        sa_id  = address[7:6];
        col_id = address[5:3];
        row_id = address[2:0];
    endfunction

    //--------------------------------------------------------------------------
    // Generic Weight Mapping Functions
    //--------------------------------------------------------------------------
    // Maps buffer index to ANN core address for variable weight counts
    // For 10×64 matrix (640 weights):
    //   - PE 0: matrix columns 0-15, all rows 0-9
    //   - PE 1: matrix columns 16-31, all rows 0-9
    //   - PE 2: matrix columns 32-47, all rows 0-9
    //   - PE 3: matrix columns 48-63, all rows 0-9
    //   Within each PE:
    //     - SA 0: cols 0-7, rows 0-7 (full 8×8)
    //     - SA 1: cols 8-15, rows 0-7 (full 8×8)
    //     - SA 2: cols 0-7, rows 8-9 (partial: 2 rows → ANN rows 0-1)
    //     - SA 3: cols 8-15, rows 8-9 (partial: 2 rows → ANN rows 0-1)
    //--------------------------------------------------------------------------

    // Convert linear buffer index to (matrix_row, matrix_col) for power-of-2 column counts
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

    // Map (matrix_row, matrix_col) to packed 10-bit ANN weight address {pe, sa, row, col}
    function automatic logic [WEIGHT_ADDR_WIDTH-1:0] matrix_coords_to_ann_addr(
        input logic [5:0] matrix_row,   // 0-31 (for up to 32 rows)
        input logic [6:0] matrix_col    // 0-63 (for up to 64 columns)
    );
        logic [PE_ID_WIDTH-1:0]  pe_id;
        logic [SA_ID_WIDTH-1:0]  sa_id;
        logic [ROW_ID_WIDTH-1:0] ann_row_id;
        logic [COL_ID_WIDTH-1:0] ann_col_id;
        logic [3:0] col_within_pe;  // Column within PE (0-15)

        // PE selection: each PE handles PE_COLS columns (default 16)
        // PE 0: cols 0-15, PE 1: cols 16-31, PE 2: cols 32-47, PE 3: cols 48-63
        pe_id = matrix_col[5:4];  // Divide by 16

        // Column within PE (0-15)
        col_within_pe = matrix_col[3:0];

        // SA selection within PE:
        //   - SA 0: cols 0-7, rows 0-7
        //   - SA 1: cols 8-15, rows 0-7
        //   - SA 2: cols 0-7, rows 8-9 (maps to ANN rows 0-1)
        //   - SA 3: cols 8-15, rows 8-9 (maps to ANN rows 0-1)
        if (matrix_row < 8) begin
            // First 8 rows: SA 0 or 1
            sa_id = col_within_pe[3] ? 2'd1 : 2'd0;  // col >= 8 → SA 1
            ann_row_id = matrix_row[2:0];  // rows 0-7 map directly to ANN rows 0-7
        end else begin
            // Rows 8-9: SA 2 or 3
            sa_id = col_within_pe[3] ? 2'd3 : 2'd2;  // col >= 8 → SA 3
            // Rows 8-9 map to ANN rows 0-1: row 8 → ANN row 0, row 9 → ANN row 1
            ann_row_id = {2'b0, matrix_row[0]};  // Convert to 3-bit: row 8 → 0, row 9 → 1
        end

        // Column within SA (0-7)
        ann_col_id = col_within_pe[2:0];

        // Combine into 10-bit address: {pe_id, sa_id, ann_row_id, ann_col_id}
        return {pe_id, sa_id, ann_row_id, ann_col_id};
    endfunction

    // Combined: linear buffer index → packed ANN weight address (default 10×64 matrix)
    function automatic logic [WEIGHT_ADDR_WIDTH-1:0] buffer_idx_to_ann_addr(
        input logic [WEIGHT_COUNT_WIDTH-1:0] buffer_idx,
        input logic [5:0] matrix_rows,  // Number of rows (default: 10)
        input logic [6:0] matrix_cols   // Number of columns (default: 64)
    );
        logic [5:0] matrix_row;
        logic [6:0] matrix_col;
        logic [PE_ID_WIDTH-1:0]  pe_id;
        logic [SA_ID_WIDTH-1:0]  sa_id;
        logic [ROW_ID_WIDTH-1:0] ann_row_id;
        logic [COL_ID_WIDTH-1:0] ann_col_id;
        logic [3:0] col_within_pe;

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
        pe_id = matrix_col[5:4];  // Divide by 16
        col_within_pe = matrix_col[3:0];

        if (matrix_row < 8) begin
            sa_id = col_within_pe[3] ? 2'd1 : 2'd0;
            ann_row_id = matrix_row[2:0];
        end else begin
            sa_id = col_within_pe[3] ? 2'd3 : 2'd2;
            ann_row_id = {2'b0, matrix_row[0]};
        end

        ann_col_id = col_within_pe[2:0];

        return {pe_id, sa_id, ann_row_id, ann_col_id};
    endfunction

    // Build 32-bit host payload in ann_address layout (wrapper around build_host_ann_word)
    function automatic logic [31:0] host_parallel_packet_to_ann_word(
        input logic [7:0] data_byte,
        input logic [15:0] parallel_addr
    );
        return build_host_ann_word(data_byte, parallel_addr);
    endfunction

endpackage
