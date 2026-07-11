//------------------------------------------------------------------------------
// Input Buffer - SystemVerilog Implementation
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
    input  logic [7:0]   data_in,         // Incoming data 

    //======================================================================
    // Connection to Controller
    //======================================================================
    output logic         ready,           // Buffer is ready to accept new data
    input  logic [2:0]   reg_ctrl,        // Register control 
    input  logic         buf_read_write,  // 1 = write, 0 = read
    input  logic [5:0]   buf_reg_add,     // 6-bit address
    input  logic [2:0]   bit_sel,         // Bit index (0-7) for bit-serial output; LSB-first per cycle

    //======================================================================
    // Output to Controller (full byte at current address, for weight read/verify)
    //======================================================================
    output logic [7:0]   buf_data,

    //======================================================================
    // Output data lines to ANN Core (1 bit per channel per cycle)
    //======================================================================
    // D0-D7: one bit each, from locations [addr..addr+7] at bit position bit_sel (LSB-first)
    //======================================================================
    output logic         D0,
    output logic         D1,
    output logic         D2,
    output logic         D3,
    output logic         D4,
    output logic         D5,
    output logic         D6,
    output logic         D7
);

    //--------------------------------------------------------------------------
    // Internal Storage 
    //--------------------------------------------------------------------------
    logic [BUFFER_DATA_WIDTH-1:0] buffer_reg [0:BUFFER_SIZE-1];

    // Internal control signals derived from reg_ctrl / buf_read_write
    logic                           write_en;  // Asserted for CTRL_DATA_LOAD writes
    logic                           read_en;   // Asserted for COMPUTE / RESULT_OUT / WEIGHT_READ reads
    logic [BUFFER_ADDR_WIDTH-1:0]  addr;      // Current buffer address (= buf_reg_add)

    //--------------------------------------------------------------------------
    // Control Signal Decoding 
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
    // Read Path: buf_data = full byte at addr (for controller weight read/verify)
    //--------------------------------------------------------------------------
    `comb(
        buf_data = '0;
        if (read_en && is_valid_addr(addr))
            buf_data = buffer_reg[addr];
    )

    //--------------------------------------------------------------------------
    // Read Path: D0-D7 = 1 bit per channel per cycle (bit-serial, LSB-first)
    //--------------------------------------------------------------------------
    // For computation (CTRL_COMPUTE), controller drives bit_sel 0..7 each cycle.
    // D0 = buffer_reg[addr][bit_sel], D1 = buffer_reg[addr+1][bit_sel], ...
    //--------------------------------------------------------------------------
    `comb(
        D0 = 1'b0;
        D1 = 1'b0;
        D2 = 1'b0;
        D3 = 1'b0;
        D4 = 1'b0;
        D5 = 1'b0;
        D6 = 1'b0;
        D7 = 1'b0;

        if (read_en) begin
            if (is_valid_addr(addr))
                D0 = buffer_reg[addr][bit_sel];
            if ((addr + 1) < BUFFER_SIZE)
                D1 = buffer_reg[addr + 1][bit_sel];
            if ((addr + 2) < BUFFER_SIZE)
                D2 = buffer_reg[addr + 2][bit_sel];
            if ((addr + 3) < BUFFER_SIZE)
                D3 = buffer_reg[addr + 3][bit_sel];
            if ((addr + 4) < BUFFER_SIZE)
                D4 = buffer_reg[addr + 4][bit_sel];
            if ((addr + 5) < BUFFER_SIZE)
                D5 = buffer_reg[addr + 5][bit_sel];
            if ((addr + 6) < BUFFER_SIZE)
                D6 = buffer_reg[addr + 6][bit_sel];
            if ((addr + 7) < BUFFER_SIZE)
                D7 = buffer_reg[addr + 7][bit_sel];
        end
    )

    //--------------------------------------------------------------------------
    // Ready Signal Logic
    //--------------------------------------------------------------------------

    `comb(
      
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
