//------------------------------------------------------------------------------
// Input Buffer - SystemVerilog Implementation
//------------------------------------------------------------------------------


`include "../common/macros.svh"

import input_buffer_pkg::*;

module input_buffer(
  
    input  logic         clk,
    input  logic         rst_n,

    
    input  logic [7:0]   data_in,         // Incoming data byte (8 bits)

   
    output logic         ready,           // Buffer is ready to accept new data
    input  logic [2:0]   reg_ctrl,        // Register control (3-bit control signal)
    input  logic         buf_read_write,  // 1 = write, 0 = read
    input  logic [5:0]   buf_reg_add,     // 6-bit address (0-63)

    
    output logic [7:0]   D0,              
    output logic [7:0]   D1,              
    output logic [7:0]   D2,             
    output logic [7:0]   D3,              
    output logic [7:0]   D4,              
    output logic [7:0]   D5,              
    output logic [7:0]   D6,              
    output logic [7:0]   D7               
);

    //--------------------------------------------------------------------------
    // Internal Storage (using package constants)
    //--------------------------------------------------------------------------
    logic [BUFFER_DATA_WIDTH-1:0] buffer_reg [0:BUFFER_SIZE-1];

    // Internal control signals
    logic                           write_en;                  
    logic                           read_en;                 
    logic [BUFFER_ADDR_WIDTH-1:0]  addr;                      // Current address

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
    // Read Path: Output data on D0-D7 lines
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
