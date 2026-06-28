//------------------------------------------------------------------------------
// Parallel Interface Package 
//------------------------------------------------------------------------------

package parallel_interface_pkg;

    //--------------------------------------------------------------------------
    // Command Signal Definitions (5 commands, 3 bits)
    //--------------------------------------------------------------------------
    localparam int CMD_WIDTH = 3;
    
    typedef enum logic [2:0] {
        CMD_HIZ   = 3'b000,  // High-Z (idle, no pulses)
        CMD_READ  = 3'b001,  // Read weight value from memristor (verification read)
        CMD_PROG  = 3'b010,  // Program weight at specified address
        CMD_ERASE = 3'b011,  // Erase weight at specified address
        CMD_INF   = 3'b100   // Inference/classification - apply input data for matrix multiplication
    } cmd_t;

    //--------------------------------------------------------------------------
    // Host data word = same layout as controller ann_core_word
    //--------------------------------------------------------------------------
    //   host_data[31:24] = data byte (weight / payload byte toward ANN core)
    //   host_data[23:0]  = {PE[3:0], SA[3:0], col one-hot[7:0], row one-hot[7:0]}
    //
    // Command is not inside the 32-bit word (would not fit with full ann format);
    // parallel_interface exposes an explicit host_cmd[2:0] port.
    //
    // Internal controller still receives decoded parallel-style address[15:0]:
    //   address[15:10]=0, address[9:8]=block, [7:6]=sub_block, [5:3]=col_id, [2:0]=row_id
    //--------------------------------------------------------------------------

    function automatic logic [1:0] pi_onehot4_to_idx(input logic [3:0] oh);
        unique case (oh)
            4'b0001: return 2'd0;
            4'b0010: return 2'd1;
            4'b0100: return 2'd2;
            4'b1000: return 2'd3;
            default: return 2'd0;
        endcase
    endfunction

    function automatic logic [2:0] pi_onehot8_to_idx(input logic [7:0] oh);
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

    function automatic logic pi_is_onehot4(input logic [3:0] oh);
        unique case (oh)
            4'b0001, 4'b0010, 4'b0100, 4'b1000: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function automatic logic pi_is_onehot8(input logic [7:0] oh);
        unique case (oh)
            8'b00000001, 8'b00000010, 8'b00000100, 8'b00001000,
            8'b00010000, 8'b00100000, 8'b01000000, 8'b10000000: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    // Host ann-tail validity: each field must be strictly one-hot.
    function automatic logic ann_tail_is_valid_onehot(input logic [23:0] tail);
        return pi_is_onehot4(tail[23:20]) &&
               pi_is_onehot4(tail[19:16]) &&
               pi_is_onehot8(tail[15:8])  &&
               pi_is_onehot8(tail[7:0]);
    endfunction

    // Decode ann_core_word-style tail → 16-bit address field (parse_ann_address layout)
    function automatic logic [15:0] ann_tail_to_parallel_addr(logic [23:0] tail);
        logic [1:0] blk, sb;
        logic [2:0] rid, cid;
        blk = pi_onehot4_to_idx(tail[23:20]);
        sb  = pi_onehot4_to_idx(tail[19:16]);
        cid = pi_onehot8_to_idx(tail[15:8]);
        rid = pi_onehot8_to_idx(tail[7:0]);
        return {6'b0, blk, sb, cid, rid};
    endfunction

    // Build host_data word from legacy 16-bit parallel address + 8-bit data byte (TB / software)
    function automatic logic [31:0] build_host_ann_word(
        input logic [7:0] data_byte,
        input logic [15:0] parallel_addr
    );
        logic [1:0] blk, sb;
        logic [2:0] rid, cid;
        logic [3:0] pe_oh, sa_oh;
        logic [7:0] col_oh, row_oh;
        blk = parallel_addr[9:8];
        sb  = parallel_addr[7:6];
        cid = parallel_addr[5:3];
        rid = parallel_addr[2:0];
        pe_oh  = 4'(1 << blk);
        sa_oh  = 4'(1 << sb);
        col_oh = 8'(1 << cid);
        row_oh = 8'(1 << rid);
        return {data_byte, pe_oh, sa_oh, col_oh, row_oh};
    endfunction

    // Legacy names used by older TB sources (map to ann layout)
    function automatic logic [7:0] extract_data(logic [31:0] host_data);
        return host_data[31:24];
    endfunction

    function automatic logic [15:0] extract_address(logic [31:0] host_data);
        return ann_tail_to_parallel_addr(host_data[23:0]);
    endfunction

    // extract_cmd(host_data) deprecated — cmd comes from host_cmd port; stub returns HIZ
    function automatic logic [2:0] extract_cmd(logic [31:0] host_data);
        return CMD_HIZ;
    endfunction

endpackage


