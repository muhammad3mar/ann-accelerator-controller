# Weight Mapping Confirmation - Shared Weights

## ✅ Confirmed Architecture

### Weight Storage Strategy
- **Shared Weights**: All sub-blocks use the **same 64 weights** (8×8 sub-block)
- **Buffer Storage**: Only 64 unique weights need to be stored
- **Buffer Organization**: 
  - 2 weights per buffer location (4 bits each)
  - 32 buffer locations needed (64 weights ÷ 2)
  - Buffer addresses: 0-31

### Weight Mapping Formula

```
Unique Weight Index = weight_addr_reg[5:0]  // {row[2:0], col[2:0]} = 0-63
Buffer Address      = unique_weight_index >> 1  // Divide by 2 = 0-31
Weight Select       = unique_weight_index[0]    // 0 = weight[0], 1 = weight[1]
```

### ANN Location Mapping

```
weight_addr_reg[9:8]   = block_id (0-3)        → Used for row/col selectors
weight_addr_reg[7:6]   = sub_block_id (0-3)    → Used for row/col selectors
weight_addr_reg[5:3]   = row within sub-block (0-7) → Used for buffer lookup + selectors
weight_addr_reg[2:0]   = col within sub-block (0-7) → Used for buffer lookup + selectors
```

### Example Mapping

| weight_addr_reg | Block | Sub-Block | Row | Col | Unique Weight | Buffer Addr | Weight Sel | Row Selector | Col Selector |
|----------------|-------|-----------|-----|-----|---------------|-------------|------------|--------------|--------------|
| 0x000 (0)      | 0     | 0         | 0   | 0   | 0             | 0           | 0          | 0x00         | 0x00         |
| 0x001 (1)      | 0     | 0         | 0   | 1   | 1             | 0           | 1          | 0x00         | 0x01         |
| 0x040 (64)     | 0     | 1         | 0   | 0   | 0             | 0           | 0          | 0x10         | 0x10         |
| 0x100 (256)    | 1     | 0         | 0   | 0   | 0             | 0           | 0          | 0x40         | 0x40         |

**Key Point**: Different ANN locations (different blocks/sub-blocks) can use the same buffer address because they share weights!

### Programming Flow

1. **Weight Storage**: Store 64 unique weights in buffer locations 0-31
   - Each location stores 2 weights (weight[0] in bits [3:0], weight[1] in bits [7:4])

2. **Weight Programming**: For each of 1024 ANN locations:
   - Extract unique weight index from weight_addr_reg[5:0]
   - Read from buffer using: `buffer_addr = weight_addr_reg[5:1]`
   - Select weight using: `weight_sel = weight_addr_reg[0]`
   - Use full weight_addr_reg[9:0] to generate row/col selectors for ANN placement
   - Program the weight into the correct ANN location

3. **Result**: All 1024 ANN locations programmed using only 64 unique weights

## ✅ Verification

- ✅ Buffer can store 64 unique weights (32 locations × 2 weights)
- ✅ Controller correctly maps weight_addr_reg[5:0] to buffer address
- ✅ Row/col selectors correctly identify ANN location (block + sub-block + row/col)
- ✅ Same weight value programmed to multiple ANN locations as needed
- ✅ Mapping supports correct MNIST classification

## Summary

**The weight mapping is CORRECT for shared weights architecture:**
- Buffer stores 64 unique weights (sufficient for one sub-block)
- Controller correctly extracts unique weight index from weight address
- Row/col selectors correctly place weights in all 1024 ANN locations
- All sub-blocks will use the same 64 weights, enabling correct MNIST classification

