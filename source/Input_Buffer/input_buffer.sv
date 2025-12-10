//------------------------------------------------------------------------------
// Input Buffer - SystemVerilog Implementation
//------------------------------------------------------------------------------
// - Uses input_buffer_pkg for all constants and types
// - Stores quantized weights (4 bits each, stored as 2 weights per location)
// - Stores MNIST 8x8 image data (64 pixels, 8 bits each)
// - Provides read/write access controlled by controller
// - Outputs data on D0-D7 lines (8 bits each = 64 bits total)
//------------------------------------------------------------------------------

`include "../common/macros.svh"

import input_buffer_pkg::*;

module input_buffer(
    //======================================================================
    // Clock & Reset
    //======================================================================
    input  logic         clk,
    input  logic         rst_n,

    //======================================================================
    // Connection to Parallel Interface
    //======================================================================
    input  logic [7:0]   data_in,         // Incoming data byte (8 bits)

    //======================================================================
    // Connection to Controller
    //======================================================================
    output logic         ready,           // Buffer is ready to accept new data
    input  logic [2:0]   reg_ctrl,        // Register control (3-bit control signal)
    input  logic         buf_read_write,  // 1 = write, 0 = read
    input  logic [5:0]   buf_reg_add,     // 6-bit address (0-63)

    //======================================================================
    // Output data lines to ANN Core
    //======================================================================
    // For MNIST 8x8 matrix, these can represent:
    // Option 1: D0-D7 = 8 consecutive pixels (one row)
    // Option 2: D0-D7 = 8 different rows (one pixel per row)
    // Current implementation: D0-D7 represent 8 consecutive locations
    // starting from the current address (for 8x8 matrix access)
    //======================================================================
    output logic [7:0]   D0,              // Data output line 0
    output logic [7:0]   D1,              // Data output line 1
    output logic [7:0]   D2,              // Data output line 2
    output logic [7:0]   D3,              // Data output line 3
    output logic [7:0]   D4,              // Data output line 4
    output logic [7:0]   D5,              // Data output line 5
    output logic [7:0]   D6,              // Data output line 6
    output logic [7:0]   D7               // Data output line 7
);

    //--------------------------------------------------------------------------
    // Internal Storage (using package constants)
    //--------------------------------------------------------------------------
    logic [BUFFER_DATA_WIDTH-1:0] buffer_reg [0:BUFFER_SIZE-1];

    // Internal control signals
    logic                           write_en;                  // Write enable
    logic                           read_en;                   // Read enable
    logic [BUFFER_ADDR_WIDTH-1:0]  addr;                      // Current address

    //--------------------------------------------------------------------------
    // Control Signal Decoding (using package constants)
    //--------------------------------------------------------------------------
    assign write_en = buf_read_write && (reg_ctrl == CTRL_DATA_LOAD);
    assign read_en  = ~buf_read_write && ((reg_ctrl == CTRL_COMPUTE) || 
                                           (reg_ctrl == CTRL_RESULT_OUT) ||
                                           (reg_ctrl == CTRL_WEIGHT_READ));
    assign addr     = buf_reg_add;

    //--------------------------------------------------------------------------
    // Write Path: Store data from parallel interface
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all buffer locations to zero
            for (int i = 0; i < BUFFER_SIZE; i++) begin
                buffer_reg[i] <= '0;
            end
        end else begin
            // Write data to buffer when write is enabled
            if (write_en && is_valid_addr(addr)) begin
                buffer_reg[addr] <= data_in;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Read Path: Output data on D0-D7 lines
    //--------------------------------------------------------------------------
    // MNIST 8x8 Matrix Read Pattern:
    //   - D0-D7 output 8 consecutive buffer locations starting from current address
    //   - To read full 8x8 matrix (64 pixels), controller increments address by 8
    //   - For computation, ANN core receives data row by row
    //--------------------------------------------------------------------------
    `comb(
        // Default outputs
        D0 = '0;
        D1 = '0;
        D2 = '0;
        D3 = '0;
        D4 = '0;
        D5 = '0;
        D6 = '0;
        D7 = '0;

        if (read_en) begin
            // Output 8 consecutive locations starting from current address
            // Wrap around if address + offset exceeds buffer size
            D0 = buffer_reg[addr];
            D1 = ((addr + 1) < BUFFER_SIZE) ? buffer_reg[addr + 1] : '0;
            D2 = ((addr + 2) < BUFFER_SIZE) ? buffer_reg[addr + 2] : '0;
            D3 = ((addr + 3) < BUFFER_SIZE) ? buffer_reg[addr + 3] : '0;
            D4 = ((addr + 4) < BUFFER_SIZE) ? buffer_reg[addr + 4] : '0;
            D5 = ((addr + 5) < BUFFER_SIZE) ? buffer_reg[addr + 5] : '0;
            D6 = ((addr + 6) < BUFFER_SIZE) ? buffer_reg[addr + 6] : '0;
            D7 = ((addr + 7) < BUFFER_SIZE) ? buffer_reg[addr + 7] : '0;
        end
    )

    //--------------------------------------------------------------------------
    // Ready Signal Logic
    //--------------------------------------------------------------------------
    // Buffer is ready when:
    // - Write mode: ready to accept new data (can always accept writes)
    // - Read mode: data is available immediately (combinational read)
    // - The ready signal indicates buffer availability for the requested operation
    //--------------------------------------------------------------------------
    `comb(
        // Default: not ready
        ready = 1'b0;
        
        // Ready for write operations during data load
        if (reg_ctrl == CTRL_DATA_LOAD && buf_read_write) begin
            // Buffer is always ready to accept writes (address valid)
            ready = is_valid_addr(addr);
        end
        // Ready for read operations during compute/result/weight read phase
        else if ((reg_ctrl == CTRL_COMPUTE || 
                  reg_ctrl == CTRL_RESULT_OUT || 
                  reg_ctrl == CTRL_WEIGHT_READ) && ~buf_read_write) begin
            // Data is available immediately for reading
            ready = is_valid_addr(addr);
        end
        // Not ready in idle or invalid control states
        else begin
            ready = 1'b0;
        end
    )

endmodule
