//------------------------------------------------------------------------------
// Controller Weight Programming Testbench
//------------------------------------------------------------------------------
// This testbench:
// 1. Loads quantized 4-bit weights from weight_matrix.txt (10×64 = 640 weights)
// 2. Sends weights to controller via parallel interface using 32-bit packet format
// 3. Controller programs weights into ANN core using direct address mapping
// 4. Monitors weight programming and dumps ANN matrix state after each weight
// 5. Verifies weight mapping correctness
// 6. Uses new architecture: 32-bit packets with CMD_PROG command
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;
import parallel_interface_pkg::*;

module controller_weight_program_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    localparam int CLK_PERIOD = 10;  // 10ns = 100MHz
    localparam string WEIGHT_FILE      = "target/Controller/weight_matrix.txt";
    localparam string ANN_DUMP_FILE    = "target/Controller/ann_matrix_dump.txt";
    localparam string BUF_DUMP_FILE    = "target/Controller/input_buffer_dump.txt";

    //--------------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    //--------------------------------------------------------------------------
    // Parallel Interface Signals
    //--------------------------------------------------------------------------
    logic                     reset;  // Active high reset for parallel interface
    logic [31:0]              host_data;  // 32-bit packet from host
    logic                     valid;
    logic [7:0]               data;  // Extracted data from parallel interface
    logic [15:0]              address;  // Extracted address from parallel interface
    logic [CMD_WIDTH-1:0]     cmd;  // Extracted command from parallel interface
    
    //--------------------------------------------------------------------------
    // Controller Signals
    //--------------------------------------------------------------------------
    logic                     ann_reset;
    logic                     weight_write_en;
    logic [SELECTOR_WIDTH-1:0] row_selector;
    logic [SELECTOR_WIDTH-1:0] col_selector;
    logic                     op_done;
    logic                     busy;
    
    // Mux control signals
    logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][ROW_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] row_mux_ctrl;
    logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][COL_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] col_mux_ctrl;
    logic [3:0]               weight_data;

    //--------------------------------------------------------------------------
    // Input Buffer Signals
    //--------------------------------------------------------------------------
    logic [7:0]               data_in;
    logic                     buf_ready;
    logic [2:0]               buf_reg_ctrl_dut;  // From controller DUT
    logic [2:0]               buf_reg_ctrl_tb;  // From testbench
    logic [2:0]               buf_reg_ctrl;      // Muxed to buffer
    logic                     buf_read_write_dut;  // From controller DUT
    logic                     buf_read_write_tb;  // From testbench
    logic                     buf_read_write;      // Muxed to buffer
    logic [5:0]               buf_reg_add_dut;  // From controller DUT
    logic [5:0]               buf_reg_add_tb;  // From testbench
    logic [5:0]               buf_reg_add;      // Muxed to buffer
    logic                     tb_control_buffer;  // Testbench takes control
    logic                     D0, D1, D2, D3, D4, D5, D6, D7;
    logic [7:0]               buf_data;  // Buffer data (full byte at current addr) to controller
    logic [2:0]               buf_bit_sel_dut;  // From controller for bit-serial D0-D7
    logic [7:0]               buf_data_out;  // Captured data from controller for buffer write
    
    // Mux between controller and testbench control
    assign buf_reg_ctrl = tb_control_buffer ? buf_reg_ctrl_tb : buf_reg_ctrl_dut;
    assign buf_read_write = tb_control_buffer ? buf_read_write_tb : buf_read_write_dut;
    assign buf_reg_add = tb_control_buffer ? buf_reg_add_tb : buf_reg_add_dut;

    //--------------------------------------------------------------------------
    // Mock ANN Core - Captures weight programming
    //--------------------------------------------------------------------------
    // ANN matrix: 4 blocks × 4 sub-blocks × 8 rows × 8 cols = 1024 locations
    logic [3:0] ann_weight_matrix [0:NUM_BLOCKS-1][0:NUM_SUB_BLOCKS-1][0:SUB_BLOCK_ROWS-1][0:SUB_BLOCK_COLS-1];
    
    // Weight data from buffer (extracted from D0-D7 or directly from buffer)
    logic [3:0] current_weight;
    logic [3:0] weight_from_buffer;

    //--------------------------------------------------------------------------
    // Testbench State
    //--------------------------------------------------------------------------
    int weight_file_handle;
    int ann_dump_handle;
    int weights_loaded = 0;
    int weights_programmed = 0;
    logic [9:0] current_weight_addr = 0;
    logic weight_loading_done = 0;
    logic weight_programming_done = 0;
    logic dump_file_initialized = 0;

    // Weight storage (640 weights from file: 10 rows × 64 columns)
    logic [3:0] weight_matrix [0:639];

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    parallel_interface u_parallel_interface (
        .clk        (clk),
        .reset      (reset),
        .host_data  (host_data),
        .valid      (valid),
        .data       (data),
        .address    (address),
        .cmd        (cmd)
    );
    
    // Connect parallel interface data to input buffer
    // Use buf_data_out from controller for PROG (captured data), otherwise use data from parallel interface
    assign data_in = buf_data_out;
    
    // New controller outputs (32-bit addr, 3-bit pulses)
    logic [ADDR_OUT_WIDTH-1:0] addr_out;
    logic [2:0]               pulses;

    // Mock ADC output for VERIFY: return programmed weight from mock ANN
    logic [3:0] weight_read_data_mock;
    always_comb begin
        weight_read_data_mock = ann_weight_matrix[row_selector[6:5]][row_selector[4:3]][row_selector[2:0]][col_selector[2:0]];
    end

    ann_controller dut (
        .clk            (clk),
        .rst_n          (~reset),  // Controller uses active low reset
        .valid          (valid),
        .data           (data),
        .address        (address),
        .cmd            (cmd),
        .ann_reset      (ann_reset),
        .weight_write_en(weight_write_en),
        .row_selector   (row_selector),
        .col_selector   (col_selector),
        .op_done        (op_done),
        .row_mux_ctrl   (row_mux_ctrl),
        .col_mux_ctrl   (col_mux_ctrl),
        .weight_data    (weight_data),
        .addr_out       (addr_out),
        .pulses         (pulses),
        .weight_read_data(weight_read_data_mock),  // Mock ADC: programmed weight for VERIFY
        .buf_reg_add    (buf_reg_add_dut),   // Controller-driven buffer address
        .buf_reg_ctrl   (buf_reg_ctrl_dut),  // Controller-driven buffer control
        .buf_read_write (buf_read_write_dut),// Controller-driven read/write
        .buf_bit_sel    (buf_bit_sel_dut),
        .buf_data_out   (buf_data_out),      // Captured data from controller for buffer write
        .buf_ready      (buf_ready),
        .buf_data       (buf_data),
        .busy           (busy)
    );

    input_buffer u_input_buffer (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in        (data_in),
        .ready          (buf_ready),
        .reg_ctrl       (buf_reg_ctrl),
        .buf_read_write(buf_read_write),
        .buf_reg_add    (buf_reg_add),
        .bit_sel        (tb_control_buffer ? 3'd0 : buf_bit_sel_dut),
        .buf_data       (buf_data),
        .D0             (D0),
        .D1             (D1),
        .D2             (D2),
        .D3             (D3),
        .D4             (D4),
        .D5             (D5),
        .D6             (D6),
        .D7             (D7)
    );

    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // Extract weight from buffer data based on weight_sel
    //--------------------------------------------------------------------------
    // Controller uses weight_addr_reg[5:1] for buffer address and weight_addr_reg[0] for weight select
    // Buffer location contains 2 weights: weight[0] in [3:0], weight[1] in [7:4]
    // We can reconstruct weight_addr_reg from row_selector and col_selector:
    //   weight_addr_reg[9:8] = row_selector[6:5] = col_selector[6:5] (block_id)
    //   weight_addr_reg[7:6] = row_selector[4:3] = col_selector[4:3] (sub_block_id)
    //   weight_addr_reg[5:3] = row_selector[2:0] (row_id)
    //   weight_addr_reg[2:0] = col_selector[2:0] (col_id)
    
    // Reconstruct weight address from selectors
    logic [9:0] reconstructed_weight_addr;
    logic weight_sel;
    logic [3:0] weight0_from_buffer, weight1_from_buffer;
    
    assign weight0_from_buffer = buf_data[3:0];   // weight[0] from buffer (full byte at addr)
    assign weight1_from_buffer = buf_data[7:4];   // weight[1] from buffer
    
    // Reconstruct full weight address from selectors
    always_comb begin
        reconstructed_weight_addr = {row_selector[6:5],    // block_id [9:8]
                                      row_selector[4:3],    // sub_block_id [7:6]
                                      row_selector[2:0],    // row_id [5:3]
                                      col_selector[2:0]};    // col_id [2:0]
        weight_sel = reconstructed_weight_addr[0];  // LSB determines which weight
    end
    
    // Extract weight based on reconstructed address
    always_comb begin
        if (weight_sel == 0)
            weight_from_buffer = weight0_from_buffer;  // weight[0]
        else
            weight_from_buffer = weight1_from_buffer;  // weight[1]
    end

    //--------------------------------------------------------------------------
    // Mock ANN Core - Capture weight programming
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize ANN matrix to zero
            for (int b = 0; b < NUM_BLOCKS; b++) begin
                for (int sb = 0; sb < NUM_SUB_BLOCKS; sb++) begin
                    for (int r = 0; r < SUB_BLOCK_ROWS; r++) begin
                        for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                            ann_weight_matrix[b][sb][r][c] <= 4'b0;
                        end
                    end
                end
            end
        end else begin
            // Capture weight when weight_write_en is asserted
            // Use weight_data from controller (extracted from buffer)
            if (weight_write_en) begin
                // Extract block, sub-block, row, col from selectors
                logic [1:0] block_id;
                logic [1:0] sub_block_id;
                logic [2:0] row_id;
                logic [2:0] col_id;
                logic [3:0] selected_weight;
                
                block_id = row_selector[6:5];
                sub_block_id = row_selector[4:3];
                row_id = row_selector[2:0];
                col_id = col_selector[2:0];
                
                // Use weight_data from controller (already extracted from buffer)
                selected_weight = weight_data;
                
                // Program weight into ANN matrix
                ann_weight_matrix[block_id][sub_block_id][row_id][col_id] <= selected_weight;
                
                $display("[%0t] Programming weight: Block=%0d, SubBlock=%0d, Row=%0d, Col=%0d, Weight=%0d (addr=0x%03X, buffer[%0d], sel=%0d)", 
                         $time, block_id, sub_block_id, row_id, col_id, selected_weight, 
                         reconstructed_weight_addr, buf_reg_add[4:0], reconstructed_weight_addr[0]);
            end
        end
    end

    //--------------------------------------------------------------------------
    // Mock op_done signal (simulate ANN core programming delay)
    //--------------------------------------------------------------------------
    // op_done should be asserted when PROG_WRITE state is active and delay has elapsed
    int op_done_counter = 0;
    logic in_prog_write_state;
    
    // Detect when we're in PROG_WRITE state (weight_write_en is asserted)
    assign in_prog_write_state = weight_write_en;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_done <= 1'b0;
            op_done_counter <= 0;
        end else begin
            if (in_prog_write_state) begin
                if (op_done_counter < 2) begin  // 2 cycle delay
                    op_done <= 1'b0;
                    op_done_counter <= op_done_counter + 1;
                end else begin
                    op_done <= 1'b1;
                    op_done_counter <= 0;
                end
            end else begin
                op_done <= 1'b0;
                op_done_counter <= 0;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Monitor Reset Behavior
    //--------------------------------------------------------------------------
    logic prev_ann_reset;
    logic prev_valid;
    logic prev_cmd;
    logic prev_busy;
    int reset_assert_count = 0;
    int reset_deassert_count = 0;
    time reset_assert_time = 0;
    time reset_deassert_time = 0;
    logic reset_observed = 0;
    
    // Track weight address from selectors to verify reset
    logic [9:0] prev_reconstructed_addr;
    logic [9:0] first_weight_addr_after_reset;
    logic addr_reset_verified = 0;
    
    always_ff @(posedge clk) begin
        prev_ann_reset <= ann_reset;
        prev_valid <= valid;
        prev_cmd <= cmd;
        prev_busy <= busy;
        prev_reconstructed_addr <= reconstructed_weight_addr;
        
        // Detect reset assertion
        if (ann_reset && !prev_ann_reset) begin
            reset_assert_count++;
            reset_assert_time = $time;
            reset_observed = 1;
            addr_reset_verified = 0;
            $display("[%0t] RESET ASSERTED: ann_reset went HIGH", $time);
            $display("[%0t]   Current weight address (from selectors): 0x%03X", 
                     $time, reconstructed_weight_addr);
        end
        
        // Detect reset deassertion
        if (!ann_reset && prev_ann_reset) begin
            reset_deassert_count++;
            reset_deassert_time = $time;
            $display("[%0t] RESET DEASSERTED: ann_reset went LOW (was asserted for %0t ns)", 
                     $time, reset_deassert_time - reset_assert_time);
        end
        
        // Monitor when new CMD_PROG is received while controller is busy or idle
        if (valid && !prev_valid && cmd == CMD_PROG) begin
            $display("[%0t] NEW CMD_PROG received: valid=1, cmd=CMD_PROG, busy=%0d", $time, busy);
            $display("[%0t]   Previous weight address: 0x%03X", $time, prev_reconstructed_addr);
        end
        
        // Track first weight address after reset (when programming starts)
        if (reset_observed && !addr_reset_verified && busy && !prev_busy) begin
            first_weight_addr_after_reset = reconstructed_weight_addr;
            if (first_weight_addr_after_reset == 0) begin
                $display("[%0t] ✓ ADDRESS RESET VERIFIED: First weight address after reset is 0x000", $time);
                addr_reset_verified = 1;
            end else begin
                $warning("[%0t] WARNING: First weight address after reset is not 0 (current: 0x%03X)", 
                         $time, first_weight_addr_after_reset);
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Monitor mux control signals and verify sequence
    //--------------------------------------------------------------------------
    logic [1:0] prev_block_id, prev_sub_block_id;
    logic [2:0] prev_row_id, prev_col_id;
    logic prev_weight_write_en;
    
    always_ff @(posedge clk) begin
        prev_weight_write_en <= weight_write_en;
        
        if (weight_write_en && !prev_weight_write_en) begin
            // Weight write just started - verify mux control
            logic [1:0] block_id_check, sub_block_id_check;
            logic [2:0] row_id_check, col_id_check;
            
            block_id_check = row_selector[6:5];
            sub_block_id_check = row_selector[4:3];
            row_id_check = row_selector[2:0];
            col_id_check = col_selector[2:0];
            
            // Verify target row mux is enabled and in write mode
            if (row_mux_ctrl[block_id_check][sub_block_id_check][row_id_check][MUX_CONTROL_WIDTH-1] != 1'b1 ||
                row_mux_ctrl[block_id_check][sub_block_id_check][row_id_check][MUX_MODE_WIDTH-1:0] != MUX_MODE_WRITE) begin
                $error("[%0t] ERROR: Target row mux not properly configured for write", $time);
            end
            
            // Verify target column mux is enabled and in write mode
            if (col_mux_ctrl[block_id_check][sub_block_id_check][col_id_check][MUX_CONTROL_WIDTH-1] != 1'b1 ||
                col_mux_ctrl[block_id_check][sub_block_id_check][col_id_check][MUX_MODE_WIDTH-1:0] != MUX_MODE_WRITE) begin
                $error("[%0t] ERROR: Target column mux not properly configured for write", $time);
            end
            
            // Verify other row muxes are in High Z mode (but enabled)
            for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
                if (r != row_id_check) begin
                    if (row_mux_ctrl[block_id_check][sub_block_id_check][r][MUX_CONTROL_WIDTH-1] != 1'b1 ||
                        row_mux_ctrl[block_id_check][sub_block_id_check][r][MUX_MODE_WIDTH-1:0] != MUX_MODE_HIZ) begin
                        $error("[%0t] ERROR: Row mux %0d not in High Z mode", $time, r);
                    end
                end
            end
            
            // Verify other column muxes are in High Z mode (but enabled)
            for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
                if (c != col_id_check) begin
                    if (col_mux_ctrl[block_id_check][sub_block_id_check][c][MUX_CONTROL_WIDTH-1] != 1'b1 ||
                        col_mux_ctrl[block_id_check][sub_block_id_check][c][MUX_MODE_WIDTH-1:0] != MUX_MODE_HIZ) begin
                        $error("[%0t] ERROR: Column mux %0d not in High Z mode", $time, c);
                    end
                end
            end
            
            $display("[%0t] Mux control verified: Block=%0d, SubBlock=%0d, Row=%0d, Col=%0d, Weight=%0d", 
                     $time, block_id_check, sub_block_id_check, row_id_check, col_id_check, weight_data);
        end
    end

    //--------------------------------------------------------------------------
    // Function to convert matrix coordinates to ANN address
    //--------------------------------------------------------------------------
    function automatic logic [15:0] matrix_coords_to_address(
        input int matrix_row,   // 0-9
        input int matrix_col    // 0-63
    );
        logic [BLOCK_ID_WIDTH-1:0] block_id;
        logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id;
        logic [ROW_ID_WIDTH-1:0] row_id;
        logic [COL_ID_WIDTH-1:0] col_id;
        logic [3:0] col_within_block;
        
        // Block selection: each block handles 16 columns
        block_id = matrix_col[5:4];  // Divide by 16
        
        // Column within block (0-15)
        col_within_block = matrix_col[3:0];
        
        // Sub-block and row selection
        if (matrix_row < 8) begin
            // First 8 rows: sub-block 0 or 1
            sub_block_id = col_within_block[3] ? 2'd1 : 2'd0;
            row_id = matrix_row[2:0];
        end else begin
            // Rows 8-9: sub-block 2 or 3
            sub_block_id = col_within_block[3] ? 2'd3 : 2'd2;
            row_id = {2'b0, matrix_row[0]};  // row 8 → 0, row 9 → 1
        end
        
        // Column within sub-block (0-7)
        col_id = col_within_block[2:0];
        
        // Form 16-bit address: {reserved[15:10], block_id[9:8], sub_block_id[7:6], col_id[5:3], row_id[2:0]}
        return {6'b0, block_id, sub_block_id, col_id, row_id};
    endfunction
    
    // Address mapping for each weight
    logic [15:0] weight_addresses [0:639];  // Store address for each weight
    
    //--------------------------------------------------------------------------
    // Track current weight index and address for dump (declared before tasks that use it)
    //--------------------------------------------------------------------------
    int current_weight_idx_reg = -1;
    logic [15:0] current_weight_16bit_addr_reg;
    logic [9:0] current_weight_10bit_addr_reg;
    
    // Function to convert 16-bit address to 10-bit ANN address
    function automatic logic [9:0] convert_16bit_to_10bit_addr(logic [15:0] addr_16bit);
        logic [BLOCK_ID_WIDTH-1:0] block_id_f;
        logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id_f;
        logic [ROW_ID_WIDTH-1:0] row_id_f;
        logic [COL_ID_WIDTH-1:0] col_id_f;
        parse_ann_address(addr_16bit, block_id_f, sub_block_id_f, row_id_f, col_id_f);
        return {block_id_f, sub_block_id_f, row_id_f, col_id_f};
    endfunction
    
    //--------------------------------------------------------------------------
    // Send Weight Programming Command (32-bit packet format)
    //--------------------------------------------------------------------------
    task send_prog_command(int weight_idx);
        logic [31:0] packet;
        logic [7:0] weight_val;
        logic [15:0] addr;
        int wait_cycles;
        
        weight_val = {4'b0, weight_matrix[weight_idx]};  // Pack 4-bit weight into 8-bit
        addr = weight_addresses[weight_idx];
        
        // Store weight index and address for dump (before sending packet)
        current_weight_idx_reg = weight_idx;
        current_weight_16bit_addr_reg = addr;
        current_weight_10bit_addr_reg = convert_16bit_to_10bit_addr(addr);
        
        // Construct 32-bit packet: {reserved[31:27], cmd[26:24], address[23:8], data[7:0]}
        packet = {5'b0, CMD_PROG, addr, weight_val};
        
        // Clear host_data first to reset valid
        @(posedge clk);
        host_data = 32'b0;
        @(posedge clk);
        
        // Send packet
        host_data = packet;
        
        // Wait for controller to start processing (busy goes high)
        wait_cycles = 0;
        while (!busy && wait_cycles < 10) begin
            @(posedge clk);
            wait_cycles++;
        end
        
        if (wait_cycles >= 10) begin
            $error("Controller did not start processing weight %0d", weight_idx);
            return;
        end
        
        // Wait for weight to be programmed (weight_write_en and op_done)
        wait_cycles = 0;
        while (!(weight_write_en && op_done) && wait_cycles < 200) begin
            @(posedge clk);
            wait_cycles++;
        end
        
        // Wait for controller to finish (busy goes low)
        wait_cycles = 0;
        while (busy && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles++;
        end
        
        if (wait_cycles >= 100) begin
            $warning("Timeout waiting for weight %0d programming to complete", weight_idx);
        end
        
        // Small delay between weights
        repeat(2) @(posedge clk);
    endtask
    
    //--------------------------------------------------------------------------
    // Load weights from file
    //--------------------------------------------------------------------------
    // Supports binary bracket format: [ [0010 0010 ...] [0010 0011 ...] ... ]
    // Each row has 8 binary values (4 bits each)
    //--------------------------------------------------------------------------
    task automatic load_weights_from_file();
        automatic int file_handle;
        automatic int weight_count = 0;
        automatic string line;
        automatic int line_num = 0;
        automatic int binary_val;
        automatic int char_idx;
        automatic int bit_idx;
        automatic int found_binary;
        automatic int i;
        automatic int bracket_start;
        automatic int bracket_end;
        automatic int content_start;
        automatic int content_end;
        automatic int pos;
        automatic int weight_in_row;
        automatic int scan_result;
        
        $display("[%0t] Loading weights from file: %s", $time, WEIGHT_FILE);
        
        file_handle = $fopen(WEIGHT_FILE, "r");
        if (file_handle == 0) begin
            $error("Failed to open weight file: %s", WEIGHT_FILE);
            $finish;
        end
        
        // Parse binary bracket format
        $display("[%0t] Parsing binary bracket format...", $time);
        
        while (!$feof(file_handle) && weight_count < 640) begin
            scan_result = $fgets(line, file_handle);
            line_num++;
            
            if (scan_result > 0) begin
                // Skip comment lines
                if (line.len() > 1 && line[0] == "/" && line[1] == "/") continue;
                
                // Skip standalone bracket lines
                if (line == "[\n" || line == "]\n") continue;
                
                // Check if line contains binary values in brackets
                // Format: [0010 0010 0101 1010 ...]
                bracket_start = -1;
                bracket_end = -1;
                
                // Find opening and closing brackets
                for (i = 0; i < line.len(); i++) begin
                    if (line[i] == "[" && bracket_start < 0) begin
                        bracket_start = i;
                    end
                    if (line[i] == "]") begin
                        bracket_end = i;
                        break;
                    end
                end
                
                if (bracket_start >= 0 && bracket_end > bracket_start) begin
                    // Extract content between brackets
                    content_start = bracket_start + 1;
                    content_end = bracket_end - 1;
                    
                    // Parse binary values (4 bits each, separated by spaces)
                    pos = content_start;
                    weight_in_row = 0;
                    
                    while (pos <= content_end && weight_in_row < 64 && weight_count < 640) begin
                        // Skip spaces
                        while (pos <= content_end && (line[pos] == " " || line[pos] == "\t")) begin
                            pos++;
                        end
                        
                        if (pos > content_end) break;
                        
                        // Read 4 binary digits
                        binary_val = 0;
                        found_binary = 0;
                        
                        for (bit_idx = 0; bit_idx < 4 && pos <= content_end; bit_idx++) begin
                            if (line[pos] == "0") begin
                                binary_val = binary_val << 1;
                                pos++;
                                found_binary = 1;
                            end else if (line[pos] == "1") begin
                                binary_val = (binary_val << 1) | 1;
                                pos++;
                                found_binary = 1;
                            end else begin
                                break;
                            end
                        end
                        
                        if (found_binary && bit_idx == 4) begin
                            weight_matrix[weight_count] = binary_val[3:0];
                            weight_count++;
                            weight_in_row++;
                        end else begin
                            // Invalid format, skip to next space or end
                            while (pos <= content_end && line[pos] != " " && line[pos] != "\t") begin
                                pos++;
                            end
                        end
                    end
                end
            end
        end
        
        $fclose(file_handle);
        
        if (weight_count != 640) begin
            $error("Expected 640 weights (10×64 matrix), found %0d", weight_count);
            $finish;
        end
        
        $display("[%0t] Successfully loaded %0d weights from file", $time, weight_count);
        
        // Calculate addresses for each weight (10 rows × 64 columns)
        for (int row = 0; row < 10; row++) begin
            for (int col = 0; col < 64; col++) begin
                int idx = row * 64 + col;
                weight_addresses[idx] = matrix_coords_to_address(row, col);
            end
        end
        
        // Display first few weights for verification
        $display("[%0t] First 8 weights: %0d %0d %0d %0d %0d %0d %0d %0d", 
                 $time, 
                 int'(weight_matrix[0]), int'(weight_matrix[1]), int'(weight_matrix[2]), int'(weight_matrix[3]),
                 int'(weight_matrix[4]), int'(weight_matrix[5]), int'(weight_matrix[6]), int'(weight_matrix[7]));
    endtask

    //--------------------------------------------------------------------------
    // Store weights into input buffer via parallel interface simulation
    // NOTE: This task is no longer used with the new architecture.
    // The controller automatically stores weights in the buffer when receiving CMD_PROG.
    //--------------------------------------------------------------------------
    task store_weights_to_buffer();
        // This task is deprecated - controller handles buffer writes automatically
        $display("[%0t] NOTE: store_weights_to_buffer() is not used with new architecture", $time);
    endtask
    //--------------------------------------------------------------------------
    // Mux Control Snapshot Storage
    //--------------------------------------------------------------------------
    // Store mux control snapshot when weight_write_en is first asserted (PROG_WRITE state)
    logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][ROW_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] snapshot_row_mux_ctrl;
    logic [NUM_BLOCKS-1:0][NUM_SUB_BLOCKS-1:0][COL_MUXES_PER_MATRIX-1:0][MUX_CONTROL_WIDTH-1:0] snapshot_col_mux_ctrl;
    string snapshot_prog_state;
    logic capture_mux_snapshot;
    
    //--------------------------------------------------------------------------
    // Initialize dump file header
    //--------------------------------------------------------------------------
    task initialize_dump_file();
        int dump_file;
        dump_file = $fopen(ANN_DUMP_FILE, "w");
        if (dump_file == 0) begin
            $error("Failed to open ANN dump file: %s", ANN_DUMP_FILE);
            return;
        end
        $fdisplay(dump_file, "//==============================================================================");
        $fdisplay(dump_file, "// ANN Weight Matrix Programming - Step-by-Step Progression");
        $fdisplay(dump_file, "//==============================================================================");
        $fdisplay(dump_file, "// This file shows the ANN matrix state after each weight is programmed");
        $fdisplay(dump_file, "// Format: Block[%0d:%0d] SubBlock[%0d:%0d] Row[%0d:%0d] Col[%0d:%0d] = Weight[3:0]", 
                  int'(NUM_BLOCKS-1), 0, int'(NUM_SUB_BLOCKS-1), 0, int'(SUB_BLOCK_ROWS-1), 0, int'(SUB_BLOCK_COLS-1), 0);
        $fdisplay(dump_file, "// Total weights to program: %0d (1024 locations)", TOTAL_WEIGHT_LOCATIONS);
        $fdisplay(dump_file, "//==============================================================================");
        $fdisplay(dump_file, "");
        $fclose(dump_file);
        dump_file_initialized = 1;
    endtask

    //--------------------------------------------------------------------------
    // Dump ANN matrix state to file (append mode)
    //--------------------------------------------------------------------------
    task dump_ann_matrix(int weight_addr);
        int dump_file;
        logic [1:0] block_id, sub_block_id;
        logic [2:0] row_id, col_id;
        logic [3:0] programmed_weight;
        
        // Initialize file header on first call
        if (!dump_file_initialized) begin
            initialize_dump_file();
        end
        
        // Open file in append mode
        dump_file = $fopen(ANN_DUMP_FILE, "a");
        if (dump_file == 0) begin
            $error("Failed to open ANN dump file: %s", ANN_DUMP_FILE);
            return;
        end
        
        // Extract current address components
        block_id = get_block_id(weight_addr);
        sub_block_id = get_sub_block_id(weight_addr);
        row_id = get_row_id(weight_addr);
        col_id = get_col_id(weight_addr);
        
        // Get the weight that was just programmed (should be available now after one clock cycle)
        programmed_weight = ann_weight_matrix[block_id][sub_block_id][row_id][col_id];
        
        // Write step header
        $fdisplay(dump_file, "//==============================================================================");
        $fdisplay(dump_file, "// STEP %0d: Weight Address 0x%03X (%0d)", weights_programmed, weight_addr, weight_addr);
        $fdisplay(dump_file, "//==============================================================================");
        $fdisplay(dump_file, "// Programmed: Block=%0d, SubBlock=%0d, Row=%0d, Col=%0d, Weight=%0d", 
                  block_id, sub_block_id, row_id, col_id, programmed_weight);
        $fdisplay(dump_file, "// Buffer Address: %0d, Weight Select: %0d", 
                  buf_reg_add[4:0], reconstructed_weight_addr[0]);
        $fdisplay(dump_file, "// Time: %0t ns", $time);
        $fdisplay(dump_file, "");
        
        // Write programming sequence information
        $fdisplay(dump_file, "//------------------------------------------------------------------------------");
        $fdisplay(dump_file, "// Programming Sequence Sent to ANN Core");
        $fdisplay(dump_file, "//------------------------------------------------------------------------------");
        $fdisplay(dump_file, "// Sequence State: %s", snapshot_prog_state);
        $fdisplay(dump_file, "// Sequence: PROG_HIZ -> PROG_SELECT -> PROG_ENABLE -> PROG_WRITE -> PROG_DISABLE -> PROG_COMPLETE");
        $fdisplay(dump_file, "//------------------------------------------------------------------------------");
        $fdisplay(dump_file, "");
        
        // Dump mux control for target matrix
        $fdisplay(dump_file, "//------------------------------------------------------------------------------");
        $fdisplay(dump_file, "// Mux Control for Target Matrix: Block=%0d, SubBlock=%0d", block_id, sub_block_id);
        $fdisplay(dump_file, "//------------------------------------------------------------------------------");
        $fdisplay(dump_file, "// Format: Mux[Index] = {Enable, Mode} = Mode_String");
        $fdisplay(dump_file, "// Enable: 1=ON, 0=OFF");
        $fdisplay(dump_file, "// Mode: 00=READ, 01=WRITE, 10=ERASE, 11=HIZ");
        $fdisplay(dump_file, "");
        
        // Mux Control Matrix View - Visual Format
        $fdisplay(dump_file, "// Mux Control Matrix (8x8):");
        $fdisplay(dump_file, "//");
        $fdisplay(dump_file, "// Row Muxes (horizontal, one per row):");
        $fwrite(dump_file, "//   R0  R1  R2  R3  R4  R5  R6  R7");
        $fdisplay(dump_file, "");
        $fwrite(dump_file, "//   ");
        for (int r = 0; r < ROW_MUXES_PER_MATRIX; r++) begin
            automatic string mode_str = get_mux_mode_str(snapshot_row_mux_ctrl[block_id][sub_block_id][r]);
            if (r == row_id) begin
                $fwrite(dump_file, "%4s*", mode_str);
            end else begin
                $fwrite(dump_file, "%4s ", mode_str);
            end
        end
        $fdisplay(dump_file, "");
        $fdisplay(dump_file, "");
        $fdisplay(dump_file, "// Column Muxes (vertical, one per column):");
        $fdisplay(dump_file, "//   C0  C1  C2  C3  C4  C5  C6  C7");
        $fwrite(dump_file, "//   ");
        for (int c = 0; c < COL_MUXES_PER_MATRIX; c++) begin
            automatic string mode_str = get_mux_mode_str(snapshot_col_mux_ctrl[block_id][sub_block_id][c]);
            if (c == col_id) begin
                $fwrite(dump_file, "%4s*", mode_str);
            end else begin
                $fwrite(dump_file, "%4s ", mode_str);
            end
        end
        $fdisplay(dump_file, "");
        $fdisplay(dump_file, "");
        $fdisplay(dump_file, "//   * = TARGET mux (Row=%0d, Col=%0d) in WRITE mode", row_id, col_id);
        $fdisplay(dump_file, "//   All other muxes are in HIZ mode (enabled but high-impedance)");
        $fdisplay(dump_file, "");
        $fdisplay(dump_file, "//------------------------------------------------------------------------------");
        $fdisplay(dump_file, "");
        
        // Dump all blocks (showing current state)
        for (int b = 0; b < NUM_BLOCKS; b++) begin
            $fdisplay(dump_file, "// Block %0d", b);
            for (int sb = 0; sb < NUM_SUB_BLOCKS; sb++) begin
                $fdisplay(dump_file, "//   Sub-Block %0d", sb);
                
                // Only show mux control for the target matrix being programmed
                if (b == block_id && sb == sub_block_id) begin
                    // Print column mux header row - aligned with weight columns (5 chars each: "[ 2] " or "  2  ")
                    $fwrite(dump_file, "//         ");
                    for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                        automatic string col_mode_str = get_mux_mode_str(snapshot_col_mux_ctrl[b][sb][c]);
                        // Format to exactly 5 characters to match weight column width
                        // Weight format: "[%2d] " = 5 chars (with trailing space) or " %2d  " = 5 chars
                        if (c == col_id) begin
                            // Target column: match "[ 2] " format = 5 chars with trailing space
                            if (col_mode_str.len() == 3) begin
                                $fwrite(dump_file, "%3s* ", col_mode_str);  // "HIZ* " = 5 chars
                            end else if (col_mode_str.len() == 4) begin
                                $fwrite(dump_file, "%4s*", col_mode_str);  // "READ*" = 5 chars
                            end else if (col_mode_str.len() == 5) begin
                                // Match "[ 2] " format: use 4 chars + "*" = 5 chars total
                                $fwrite(dump_file, "%4s*", col_mode_str.substr(0, 3));  // "WRIT*" = 5 chars
                            end else begin
                                $fwrite(dump_file, "%5s", col_mode_str);
                            end
                        end else begin
                            // Non-target columns: match "  2  " format = 5 chars with spaces
                            if (col_mode_str.len() == 3) begin
                                $fwrite(dump_file, " %3s ", col_mode_str);  // " HIZ " = 5 chars
                            end else if (col_mode_str.len() == 4) begin
                                $fwrite(dump_file, "%4s ", col_mode_str);  // "READ " = 5 chars
                            end else if (col_mode_str.len() == 5) begin
                                $fwrite(dump_file, "%5s", col_mode_str);  // "WRITE" = 5 chars
                            end else begin
                                $fwrite(dump_file, "%5s", col_mode_str);
                            end
                        end
                    end
                    $fdisplay(dump_file, "  <- Column Muxes");
                    
                    // Print each row with row mux value and weight values
                    for (int r = 0; r < SUB_BLOCK_ROWS; r++) begin
                        automatic string row_mode_str = get_mux_mode_str(snapshot_row_mux_ctrl[b][sb][r]);
                        // Format row mux to exactly 5 characters to match weight column width
                        automatic string padded_row_str;
                        if (row_mode_str.len() == 3) begin
                            padded_row_str = {row_mode_str, "  "};  // "HIZ  " = 5 chars
                        end else if (row_mode_str.len() == 4) begin
                            padded_row_str = {row_mode_str, " "};  // "READ " = 5 chars
                        end else if (row_mode_str.len() == 5) begin
                            padded_row_str = row_mode_str;  // "WRITE" = 5 chars
                        end else begin
                            padded_row_str = row_mode_str;
                        end
                        if (r == row_id) begin
                            // Target row: format to 4 chars + "*" = 5 chars total
                            if (row_mode_str.len() == 3) begin
                                $fwrite(dump_file, "// R%0d %3s* ", r, row_mode_str);  // "HIZ* " = 5 chars
                            end else if (row_mode_str.len() == 4) begin
                                $fwrite(dump_file, "// R%0d %4s* ", r, row_mode_str);  // "READ*" = 5 chars
                            end else if (row_mode_str.len() == 5) begin
                                $fwrite(dump_file, "// R%0d %4s* ", r, row_mode_str.substr(0, 3));  // "WRIT*" = 5 chars
                            end else begin
                                $fwrite(dump_file, "// R%0d %5s ", r, row_mode_str);
                            end
                        end else begin
                            $fwrite(dump_file, "// R%0d %5s ", r, padded_row_str);
                        end
                        for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                            // Highlight the weight that was just programmed
                            if (r == row_id && c == col_id) begin
                                $fwrite(dump_file, "[%2d] ", ann_weight_matrix[b][sb][r][c]);
                            end else begin
                                $fwrite(dump_file, " %2d  ", ann_weight_matrix[b][sb][r][c]);
                            end
                        end
                        $fdisplay(dump_file, "");
                    end
                    $fdisplay(dump_file, "//      ^");
                    $fdisplay(dump_file, "//      Row Muxes");
                end else begin
                    // For other matrices, show without mux control but with aligned column headers
                    // Column header row - aligned with weight columns (5 chars each, matching target matrix format)
                    $fwrite(dump_file, "//         ");  // Same indentation as target matrix (10 spaces)
                    for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                        // Format to match target matrix: "WRIT*" = 5 chars starting at position 11
                        // Shift right by 1 space to better align: " C%0d  " = 5 chars (space, C, digit, space, space)
                        $fwrite(dump_file, " C%0d  ", c);  // " C0  " = 5 chars (space, C, digit, space, space)
                    end
                    $fdisplay(dump_file, "");
                    // Weight rows - use same format as target matrix for consistency
                    for (int r = 0; r < SUB_BLOCK_ROWS; r++) begin
                        $fwrite(dump_file, "// R%0d      ", r);  // Match target matrix row format spacing
                        for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                            $fwrite(dump_file, " %2d  ", ann_weight_matrix[b][sb][r][c]);  // "  2  " = 5 chars
                        end
                        $fdisplay(dump_file, "");
                    end
                end
                $fdisplay(dump_file, "");
            end
        end
        
        $fdisplay(dump_file, "");
        $fclose(dump_file);
        $display("[%0t] Step %0d: ANN matrix updated - Block=%0d, SubBlock=%0d, Row=%0d, Col=%0d, Weight=%0d", 
                 $time, weights_programmed, block_id, sub_block_id, row_id, col_id, programmed_weight);
    endtask

    //--------------------------------------------------------------------------
    // Programming Sequence State Tracking
    //--------------------------------------------------------------------------
    // Track sequence states by monitoring signals
    string prog_sequence_state_str;
    logic prev_op_done;
    int sequence_step_count;
    
    // Function to get mux mode string
    function string get_mux_mode_str(logic [MUX_CONTROL_WIDTH-1:0] mux_ctrl);
        logic enable;
        logic [1:0] mode;
        enable = mux_ctrl[MUX_CONTROL_WIDTH-1];
        mode = mux_ctrl[MUX_MODE_WIDTH-1:0];
        
        if (!enable) return "OFF";
        else case (mode)
            MUX_MODE_READ:  return "READ";
            MUX_MODE_WRITE: return "WRITE";
            MUX_MODE_ERASE: return "ERASE";
            MUX_MODE_HIZ:   return "HIZ";
            default: return "UNK";
        endcase
    endfunction
    
    // Function to infer programming sequence state
    function string infer_prog_state();
        if (!busy) return "IDLE";
        else if (ann_reset) return "RESET";
        else if (weight_write_en) return "PROG_WRITE";
        else if (buf_reg_ctrl == CTRL_WEIGHT_READ && !weight_write_en) return "PROG_ENABLE/SELECT";
        else return "PROG_HIZ/DISABLE";
    endfunction
    
    // Monitor programming sequence
    always_ff @(posedge clk) begin
        prev_weight_write_en <= weight_write_en;
        prev_op_done <= op_done;
        
        if (busy && !ann_reset) begin
            if (weight_write_en && !prev_weight_write_en) begin
                sequence_step_count++;
                prog_sequence_state_str = "PROG_WRITE";
            end else if (!weight_write_en && prev_weight_write_en && op_done) begin
                sequence_step_count++;
                prog_sequence_state_str = "PROG_DISABLE";
            end else if (!weight_write_en && buf_reg_ctrl == CTRL_WEIGHT_READ) begin
                if (sequence_step_count == 0) prog_sequence_state_str = "PROG_HIZ";
                else if (sequence_step_count == 1) prog_sequence_state_str = "PROG_SELECT";
                else if (sequence_step_count == 2) prog_sequence_state_str = "PROG_ENABLE";
            end
        end else begin
            sequence_step_count = 0;
            prog_sequence_state_str = infer_prog_state();
        end
    end
    
    //--------------------------------------------------------------------------
    // Monitor weight programming and dump ANN matrix
    //--------------------------------------------------------------------------
    logic dump_trigger;
    logic [9:0] dump_weight_addr;
    logic [1:0] dump_block_id, dump_sub_block_id;
    logic [2:0] dump_row_id, dump_col_id;
    
    // Capture mux snapshot when weight_write_en is first asserted (PROG_WRITE state)
    always_ff @(posedge clk) begin
        if (weight_write_en && !prev_weight_write_en && buf_reg_ctrl == CTRL_WEIGHT_READ) begin
            // Capture mux control at start of PROG_WRITE state
            snapshot_row_mux_ctrl <= row_mux_ctrl;
            snapshot_col_mux_ctrl <= col_mux_ctrl;
            snapshot_prog_state <= "PROG_WRITE";
            capture_mux_snapshot <= 1'b1;
        end else begin
            capture_mux_snapshot <= 1'b0;
        end
    end
    
    // Trigger dump when programming is complete (op_done) - use stored address from send_prog_command
    always_ff @(posedge clk) begin
        if (valid && cmd == CMD_PROG && busy && !prev_busy) begin
            // Controller just started processing a new PROG command - capture the address
            logic [BLOCK_ID_WIDTH-1:0] block_id_parsed;
            logic [SUB_BLOCK_ID_WIDTH-1:0] sub_block_id_parsed;
            logic [ROW_ID_WIDTH-1:0] row_id_parsed;
            logic [COL_ID_WIDTH-1:0] col_id_parsed;
            
            // Parse 16-bit address from parallel interface to get ANN address components
            parse_ann_address(address, block_id_parsed, sub_block_id_parsed, row_id_parsed, col_id_parsed);
            
            // Store captured address components
            dump_block_id <= block_id_parsed;
            dump_sub_block_id <= sub_block_id_parsed;
            dump_row_id <= row_id_parsed;
            dump_col_id <= col_id_parsed;
            
            // Construct 10-bit ANN address from parsed components
            dump_weight_addr <= {block_id_parsed, sub_block_id_parsed, row_id_parsed, col_id_parsed};
            
            // Store 16-bit address for reference
            current_weight_16bit_addr_reg <= address;
        end
    end
    
    // Capture address when weight_write_en is first asserted
    logic [9:0] captured_addr_when_write_en;
    
    always_ff @(posedge clk) begin
        if (weight_write_en && !prev_weight_write_en) begin
            // Capture the address at the moment weight_write_en goes high
            captured_addr_when_write_en <= current_weight_10bit_addr_reg;
        end
    end
    
    // Trigger dump when programming is complete (op_done) - use captured address
    always_ff @(posedge clk) begin
        if (weight_write_en && op_done) begin
            // Track current weight address (use address captured when weight_write_en first asserted)
            weights_programmed++;
            current_weight_addr = captured_addr_when_write_en;
            dump_weight_addr <= captured_addr_when_write_en;
            
            // Trigger dump on next clock cycle (after weight is written)
            dump_trigger <= 1'b1;
        end else begin
            dump_trigger <= 1'b0;
        end
    end
    
    // Dump on next clock cycle after weight is written
    always_ff @(posedge clk) begin
        if (dump_trigger) begin
            // Dump ANN matrix after each weight is programmed
            if (weights_programmed <= TOTAL_WEIGHT_LOCATIONS) begin
                dump_ann_matrix(dump_weight_addr);
            end
        end
    end

    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("Controller Weight Programming Testbench");
        $display("========================================");
        
        // Initialize
        reset = 1'b1;  // Active high reset for parallel interface
        host_data = 32'b0;
        rst_n = 0;  // Active low reset for controller
        tb_control_buffer = 0;
        buf_reg_ctrl_tb = CTRL_IDLE;
        buf_read_write_tb = 0;
        buf_reg_add_tb = 0;
        
        // Reset
        #(CLK_PERIOD * 5);
        reset = 1'b0;
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        // Load weights from file (also calculates addresses)
        load_weights_from_file();
        
        // Initialize dump file
        initialize_dump_file();
        
        // Wait a few cycles
        #(CLK_PERIOD * 5);
        
        //============================================================
        // Test: Weight Programming Sequence (640 weights)
        //============================================================
        $display("\n========================================");
        $display("Weight Programming Sequence");
        $display("========================================");
        $display("[%0t] Starting weight programming...", $time);
        
        // Program all 640 weights one at a time
        for (int i = 0; i < 640; i++) begin
            send_prog_command(i);
        end
        
        $display("\n========================================");
        $display("Weight Programming Complete!");
        $display("Total weights programmed: %0d", weights_programmed);
        $display("========================================");
        
        // Wait for final programming to complete
        wait(busy == 0);
        
        // Final dump
        $display("\n[%0t] Final ANN matrix state:", $time);
        dump_ann_matrix(reconstructed_weight_addr);
        
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================");
        $display("Weights programmed: %0d / %0d", weights_programmed, 640);
        
        #(CLK_PERIOD * 10);
        $finish;
    end

    //--------------------------------------------------------------------------
    // Timeout
    //--------------------------------------------------------------------------
    initial begin
        #(1000000 * CLK_PERIOD);
        $error("Testbench timeout!");
        $finish;
    end

endmodule

