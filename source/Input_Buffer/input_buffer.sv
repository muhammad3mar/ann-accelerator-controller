module input_buffer(
    // Clock & Reset
    input  logic         clk,
    input  logic         rst_n,

    // Connection to Parallel Interface
    input  logic  [7:0]  data_in,    // Incoming data byte
    // Connection to controller
    output logic         ready,      // Buffer is ready to accept new data
    input  logic  [2:0]  reg_ctrl,   // Read/Write control
    input logic         buf_read_write,   // 1 = write, 0 = read
    input logic [5:0]               buf_reg_add,      // REG_ADD[5:0]
    // Output data lines D0..D7
    output logic [7:0]   D0,
    output logic [7:0]   D1,
    output logic [7:0]   D2,
    output logic [7:0]   D3,
    output logic [7:0]   D4,
    output logic [7:0]   D5,
    output logic [7:0]   D6,
    output logic [7:0]   D7
);
    // Internal logic will be added here later
endmodule
