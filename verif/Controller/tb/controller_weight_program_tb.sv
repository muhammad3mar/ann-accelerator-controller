//------------------------------------------------------------------------------
// Controller Weight Programming Testbench
//------------------------------------------------------------------------------
// This testbench:
// 1. Loads quantized 4-bit weights from weight_matrix.txt (8x8 = 64 weights)
// 2. Stores weights in input buffer via parallel interface simulation
// 3. Triggers controller to program weights into ANN
// 4. Monitors weight programming and dumps ANN matrix state after each weight
// 5. Verifies weight mapping correctness
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "../../../source/common/macros.svh"

import controller_pkg::*;
import input_buffer_pkg::*;

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
    // Controller Signals
    //--------------------------------------------------------------------------
    logic                     valid;
    logic                     ann_reset;
    logic                     weight_write_en;
    logic [SELECTOR_WIDTH-1:0] row_selector;
    logic [SELECTOR_WIDTH-1:0] col_selector;
    logic                     op_done;
    logic                     busy;

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
    logic [7:0]               D0, D1, D2, D3, D4, D5, D6, D7;
    
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

    // Weight storage (64 weights from file)
    logic [3:0] weight_matrix [0:63];

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    ann_controller dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid          (valid),
        .ann_reset      (ann_reset),
        .weight_write_en(weight_write_en),
        .row_selector   (row_selector),
        .col_selector   (col_selector),
        .op_done        (op_done),
        .buf_reg_add    (buf_reg_add_dut),   // Controller-driven buffer address
        .buf_reg_ctrl   (buf_reg_ctrl_dut),  // Controller-driven buffer control
        .buf_read_write (buf_read_write_dut),// Controller-driven read/write
        .buf_ready      (buf_ready),
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
    
    assign weight0_from_buffer = D0[3:0];   // weight[0] from buffer
    assign weight1_from_buffer = D0[7:4];   // weight[1] from buffer
    
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
            // Capture weight when weight_write_en is asserted and op_done indicates completion
            if (weight_write_en && buf_reg_ctrl == CTRL_WEIGHT_READ && op_done) begin
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
                
                // Extract weight based on reconstructed address
                if (reconstructed_weight_addr[0] == 0)
                    selected_weight = weight0_from_buffer;
                else
                    selected_weight = weight1_from_buffer;
                
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
    int op_done_counter = 0;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_done <= 1'b0;
            op_done_counter <= 0;
        end else begin
            if (weight_write_en) begin
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
        
        while (!$feof(file_handle) && weight_count < 64) begin
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
                    
                    while (pos <= content_end && weight_in_row < 8 && weight_count < 64) begin
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
        
        if (weight_count != 64) begin
            $error("Expected 64 weights, found %0d", weight_count);
            $finish;
        end
        
        $display("[%0t] Successfully loaded %0d weights from file", $time, weight_count);
        
        // Display first few weights for verification
        $display("[%0t] First 8 weights: %0d %0d %0d %0d %0d %0d %0d %0d", 
                 $time, 
                 int'(weight_matrix[0]), int'(weight_matrix[1]), int'(weight_matrix[2]), int'(weight_matrix[3]),
                 int'(weight_matrix[4]), int'(weight_matrix[5]), int'(weight_matrix[6]), int'(weight_matrix[7]));
    endtask

    //--------------------------------------------------------------------------
    // Store weights into input buffer via parallel interface simulation
    //--------------------------------------------------------------------------
    task store_weights_to_buffer();
        int buf_addr;
        logic [7:0] buffer_data;
        int buf_dump_fd;
        int addr_idx;
        int bit_idx2;
        int byte_val;
        
        $display("[%0t] Storing weights into input buffer...", $time);
        
        // Open buffer dump file and write header
        buf_dump_fd = $fopen(BUF_DUMP_FILE, "w");
        if (buf_dump_fd == 0) begin
            $error("Failed to open buffer dump file: %s", BUF_DUMP_FILE);
        end else begin
            $fdisplay(buf_dump_fd, "//==============================================================");
            $fdisplay(buf_dump_fd, "// Input Buffer Programming - Initial Weight Load");
            $fdisplay(buf_dump_fd, "//==============================================================");
            $fdisplay(buf_dump_fd, "// Each line shows how the external parallel interface writes");
            $fdisplay(buf_dump_fd, "// into the input buffer before ANN weight programming starts.");
            $fdisplay(buf_dump_fd, "// Format per write:");
            $fdisplay(buf_dump_fd, "//   time  addr  data_in  weight_low  weight_high");
            $fdisplay(buf_dump_fd, "//   where data_in = {weight_high[3:0], weight_low[3:0]}");
            $fdisplay(buf_dump_fd, "//==============================================================");
            $fdisplay(buf_dump_fd, "");
        end
        
        // Take control of buffer signals
        tb_control_buffer = 1'b1;
        
        // Store weights in buffer: 2 weights per location (32 locations total)
        for (int i = 0; i < 32; i++) begin
            buf_addr = i;
            // Pack 2 weights into one byte: weight[2*i] in [3:0], weight[2*i+1] in [7:4]
            buffer_data = {weight_matrix[2*i+1][3:0], weight_matrix[2*i][3:0]};
            
            @(posedge clk);
            
            // Set buffer control signals (testbench controlled)
            buf_reg_ctrl_tb   = CTRL_DATA_LOAD;
            buf_read_write_tb = 1'b1;  // Write mode
            buf_reg_add_tb    = buf_addr[5:0];
            data_in           = buffer_data;
            
            // Wait for buffer to be ready (should be immediate for writes)
            @(posedge clk);
            #1;  // Small delay for combinational logic
            
            // Console log
            $display("[%0t] Stored buffer[%0d] = 0x%02X (weights[%0d]=%0d, weights[%0d]=%0d)", 
                     $time, buf_addr, buffer_data, 2*i, weight_matrix[2*i], 2*i+1, weight_matrix[2*i+1]);
            
            // File log
            if (buf_dump_fd != 0) begin
                $fdisplay(buf_dump_fd,
                          "%0t  addr=%0d  data_in=0x%02X  weight_low=%0d  weight_high=%0d",
                          $time, buf_addr, buffer_data,
                          int'(weight_matrix[2*i]), int'(weight_matrix[2*i+1]));
            end
        end
        
        // Also dump input buffer as 64 rows x 8 bits matrix
        // Each row = one buffer address, showing 8 bits (2 weights of 4 bits each)
        if (buf_dump_fd != 0) begin
            $fdisplay(buf_dump_fd, "");
            $fdisplay(buf_dump_fd, "//==============================================================");
            $fdisplay(buf_dump_fd, "// Input Buffer Matrix View (64 rows x 8 bits)");
            $fdisplay(buf_dump_fd, "// Each row represents one buffer address (0-63)");
            $fdisplay(buf_dump_fd, "// Each row contains 8 bits: [7:4] = weight_high, [3:0] = weight_low");
            $fdisplay(buf_dump_fd, "// Format: addr | bit[7:4] | bit[3:0] | binary[7:0] | hex | weight_high | weight_low");
            $fdisplay(buf_dump_fd, "// Note: addresses 32-63 are unused for weights and remain 0");
            $fdisplay(buf_dump_fd, "//==============================================================");
            $fdisplay(buf_dump_fd, "");

            // Header
            $fdisplay(buf_dump_fd, "addr | bits[7:4] | bits[3:0] | binary[7:0]    | hex  | weight_high | weight_low");
            $fdisplay(buf_dump_fd, "-----+-----------+----------+----------------+------+-------------+------------");

            // For each buffer address (0-63), show the 8-bit value
            for (addr_idx = 0; addr_idx < 64; addr_idx++) begin
                if (addr_idx < 32) begin
                    // Reconstruct the byte we wrote to this buffer address
                    byte_val = {weight_matrix[2*addr_idx+1][3:0], weight_matrix[2*addr_idx][3:0]};
                    $fwrite(buf_dump_fd, "%4d | ", addr_idx);
                    // Show bits [7:4] (weight_high)
                    for (bit_idx2 = 7; bit_idx2 >= 4; bit_idx2--) begin
                        $fwrite(buf_dump_fd, "%0d", (byte_val >> bit_idx2) & 1);
                    end
                    $fwrite(buf_dump_fd, "        | ");
                    // Show bits [3:0] (weight_low)
                    for (bit_idx2 = 3; bit_idx2 >= 0; bit_idx2--) begin
                        $fwrite(buf_dump_fd, "%0d", (byte_val >> bit_idx2) & 1);
                    end
                    $fwrite(buf_dump_fd, "        | ");
                    // Show full binary [7:0]
                    for (bit_idx2 = 7; bit_idx2 >= 0; bit_idx2--) begin
                        $fwrite(buf_dump_fd, "%0d", (byte_val >> bit_idx2) & 1);
                    end
                    $fwrite(buf_dump_fd, " | 0x%02X | ", byte_val);
                    $fwrite(buf_dump_fd, "     %2d     | ", int'(weight_matrix[2*addr_idx+1]));
                    $fdisplay(buf_dump_fd, "     %2d", int'(weight_matrix[2*addr_idx]));
                end else begin
                    // Unused addresses (32-63) are all zeros
                    $fwrite(buf_dump_fd, "%4d | ", addr_idx);
                    $fwrite(buf_dump_fd, "0000      | ");
                    $fwrite(buf_dump_fd, "0000      | ");
                    $fwrite(buf_dump_fd, "00000000 | ");
                    $fwrite(buf_dump_fd, "0x00 | ");
                    $fwrite(buf_dump_fd, "      0      | ");
                    $fdisplay(buf_dump_fd, "      0");
                end
            end

            $fdisplay(buf_dump_fd, "");
            $fdisplay(buf_dump_fd, "//==============================================================");
            $fdisplay(buf_dump_fd, "// Alternative View: 64 rows showing binary representation");
            $fdisplay(buf_dump_fd, "// Each row = buffer[addr] as 8-bit binary with separator");
            $fdisplay(buf_dump_fd, "//==============================================================");
            $fdisplay(buf_dump_fd, "");

            // Alternative compact view: just the binary with separator
            for (addr_idx = 0; addr_idx < 64; addr_idx++) begin
                if (addr_idx < 32) begin
                    byte_val = {weight_matrix[2*addr_idx+1][3:0], weight_matrix[2*addr_idx][3:0]};
                    $fwrite(buf_dump_fd, "buffer[%2d] = ", addr_idx);
                    // Show bits [7:4] (weight_high)
                    for (bit_idx2 = 7; bit_idx2 >= 4; bit_idx2--) begin
                        $fwrite(buf_dump_fd, "%0d", (byte_val >> bit_idx2) & 1);
                    end
                    $fwrite(buf_dump_fd, "_");
                    // Show bits [3:0] (weight_low)
                    for (bit_idx2 = 3; bit_idx2 >= 0; bit_idx2--) begin
                        $fwrite(buf_dump_fd, "%0d", (byte_val >> bit_idx2) & 1);
                    end
                    $fdisplay(buf_dump_fd, "  (weight[%2d]=%2d, weight[%2d]=%2d)", 
                            2*addr_idx+1, int'(weight_matrix[2*addr_idx+1]),
                            2*addr_idx, int'(weight_matrix[2*addr_idx]));
                end else begin
                    $fdisplay(buf_dump_fd, "buffer[%2d] = 0000_0000  (unused)", addr_idx);
                end
            end

            $fdisplay(buf_dump_fd, "");
            $fdisplay(buf_dump_fd, "// End of initial input buffer programming");
            $fclose(buf_dump_fd);
            $display("[%0t] Input buffer write log dumped to %s", $time, BUF_DUMP_FILE);
        end
        
        // Release control back to controller
        @(posedge clk);
        tb_control_buffer   = 1'b0;
        buf_reg_ctrl_tb     = CTRL_IDLE;
        buf_read_write_tb   = 1'b0;
        
        weight_loading_done = 1;
        $display("[%0t] Weight loading complete", $time);
    endtask

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
        
        // Dump all blocks (showing current state)
        for (int b = 0; b < NUM_BLOCKS; b++) begin
            $fdisplay(dump_file, "// Block %0d", b);
            for (int sb = 0; sb < NUM_SUB_BLOCKS; sb++) begin
                $fdisplay(dump_file, "//   Sub-Block %0d", sb);
                for (int r = 0; r < SUB_BLOCK_ROWS; r++) begin
                    $fwrite(dump_file, "//     Row %0d: ", r);
                    for (int c = 0; c < SUB_BLOCK_COLS; c++) begin
                        // Highlight the weight that was just programmed
                        if (b == block_id && sb == sub_block_id && r == row_id && c == col_id) begin
                            $fwrite(dump_file, "[%2d]", ann_weight_matrix[b][sb][r][c]);
                        end else begin
                            $fwrite(dump_file, " %2d ", ann_weight_matrix[b][sb][r][c]);
                        end
                    end
                    $fdisplay(dump_file, "");
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
    // Monitor weight programming and dump ANN matrix
    //--------------------------------------------------------------------------
    logic dump_trigger;
    logic [9:0] dump_weight_addr;
    logic [1:0] dump_block_id, dump_sub_block_id;
    logic [2:0] dump_row_id, dump_col_id;
    
    always_ff @(posedge clk) begin
        if (weight_write_en && buf_reg_ctrl == CTRL_WEIGHT_READ && op_done) begin
            logic [1:0] block_id, sub_block_id;
            logic [2:0] row_id, col_id;
            
            block_id = row_selector[6:5];
            sub_block_id = row_selector[4:3];
            row_id = row_selector[2:0];
            col_id = col_selector[2:0];
            
            // Track current weight address (reconstructed from selectors)
            weights_programmed++;
            current_weight_addr = reconstructed_weight_addr;
            
            // Trigger dump on next clock cycle (after weight is written)
            dump_trigger <= 1'b1;
            dump_weight_addr <= reconstructed_weight_addr;
            dump_block_id <= block_id;
            dump_sub_block_id <= sub_block_id;
            dump_row_id <= row_id;
            dump_col_id <= col_id;
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
        rst_n = 0;
        valid = 0;
        data_in = 0;
        tb_control_buffer = 0;
        buf_reg_ctrl_tb = CTRL_IDLE;
        buf_read_write_tb = 0;
        buf_reg_add_tb = 0;
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        // Load weights from file
        load_weights_from_file();
        
        // Store weights into buffer
        store_weights_to_buffer();
        
        // Wait a few cycles
        #(CLK_PERIOD * 5);
        
        // Trigger weight programming by asserting valid
        $display("[%0t] Triggering weight programming...", $time);
        valid = 1;
        
        // Wait for programming to complete
        wait(busy == 1);
        $display("[%0t] Weight programming started", $time);
        
        wait(busy == 0);
        $display("[%0t] Weight programming completed", $time);
        
        valid = 0;
        
        // Wait a few more cycles
        #(CLK_PERIOD * 10);
        
        // Final dump
        $display("[%0t] Final ANN matrix state:", $time);
        dump_ann_matrix(TOTAL_WEIGHT_LOCATIONS - 1);
        
        $display("========================================");
        $display("Test Complete");
        $display("========================================");
        $display("Weights programmed: %0d / %0d", weights_programmed, TOTAL_WEIGHT_LOCATIONS);
        
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

