# Common Macros

This folder contains reusable SystemVerilog macros to reduce code duplication and improve readability.

## Usage

Include the macros file at the top of your module:

```systemverilog
`include "../common/macros.svh"
```

## Available Macros

### D Flip-Flop Macros

#### Basic D-FF
- **`d_ff_async_low(clk, rst_n, q, d)`** - Positive edge, async active-low reset
- **`d_ff_async_high(clk, rst, q, d)`** - Positive edge, async active-high reset
- **`d_ff_sync_low(clk, rst_n, q, d)`** - Positive edge, sync active-low reset
- **`d_ff_sync_high(clk, rst, q, d)`** - Positive edge, sync active-high reset
- **`d_ff_async_low_negedge(clk, rst_n, q, d)`** - Negative edge, async active-low reset

#### D-FF with Custom Reset Value
- **`d_ff_async_low_rstval(clk, rst_n, q, d, rst_val)`** - Async reset with custom value
- **`d_ff_sync_low_rstval(clk, rst_n, q, d, rst_val)`** - Sync reset with custom value

#### D-FF with Enable
- **`d_ff_en_async_low(clk, rst_n, en, q, d)`** - With enable signal
- **`d_ff_en_async_low_rstval(clk, rst_n, en, q, d, rst_val)`** - With enable and custom reset value

### Example Usage

```systemverilog
// Simple D-FF with async active-low reset
logic [7:0] data_reg;
`d_ff_async_low(clk, rst_n, data_reg, data_in)

// D-FF with enable
logic [15:0] counter;
`d_ff_en_async_low(clk, rst_n, count_en, counter, counter + 1)

// D-FF with custom reset value
logic [3:0] state;
`d_ff_async_low_rstval(clk, rst_n, state, next_state, 4'hF)
```

### State Machine Macros

- **`state_reg_async_low(clk, rst_n, state, next_state, init_state)`** - State register with async reset
- **`state_reg_sync_low(clk, rst_n, state, next_state, init_state)`** - State register with sync reset

### Counter Macros

- **`counter_up_async_low(clk, rst_n, cnt, max_val)`** - Up counter
- **`counter_up_en_async_low(clk, rst_n, en, cnt, max_val)`** - Up counter with enable
- **`counter_down_async_low(clk, rst_n, cnt, min_val)`** - Down counter

### Combinational Logic Macros

- **`comb(block)`** - Wrapper for `always_comb begin ... end`

Example:
```systemverilog
`comb(
    out = in1 & in2;
    valid = (in1 != '0);
)
```

### Multiplexer Macros

- **`mux2(sel, in0, in1, out)`** - 2-to-1 multiplexer
- **`mux4(sel, in0, in1, in2, in3, out)`** - 4-to-1 multiplexer

### Register File Macros

- **`init_regfile_zero(clk, rst_n, regfile, size)`** - Initialize register file to zero
- **`regfile_write(clk, rst_n, regfile, addr, data, we)`** - Write to register file

### Other Useful Macros

- **`sync2_async_low(clk, rst_n, d, q)`** - 2-stage synchronizer for CDC
- **`priority_encoder(input, output, width)`** - Priority encoder
- **`assert_no_xz(signal, name)`** - Assert no X or Z values
- **`assert_onehot(signal, name)`** - Assert one-hot encoding

## Benefits

1. **Reduced Code Duplication** - Common patterns written once
2. **Improved Readability** - Macros make intent clear
3. **Consistency** - Same patterns used throughout the design
4. **Easy Maintenance** - Update macro definition to change behavior everywhere
5. **Less Error-Prone** - Standardized implementations reduce bugs

## Notes

- Macros are expanded at compile time, so they don't add runtime overhead
- Use macros for common patterns, but don't overuse them for one-off cases
- Always verify macro expansion matches your intent
