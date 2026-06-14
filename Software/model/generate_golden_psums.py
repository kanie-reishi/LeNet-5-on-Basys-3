import os
from pathlib import Path
import numpy as np

def main():
    # Paths relative to workspace root (two levels up from Software/model)
    script_dir = Path(__file__).resolve().parent
    workspace_root = script_dir.parent.parent
    
    ifm_path = workspace_root / "tb" / "hex_conv1" / "ifm.hex"
    weight_path = workspace_root / "tb" / "hex_conv1" / "weight.hex"
    bias_path = workspace_root / "tb" / "hex_conv1" / "bias.hex"
    output_path = workspace_root / "tb" / "data" / "golden_psums.txt"
    
    # Ensure output directory exists
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    # 1. Parse IFM (1024 lines of 128-bit hex, cin=1 -> lower 8 bits is pixel value)
    ifm_pixels = []
    with open(ifm_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                # The pixel is in the LSB (last 2 hex characters)
                pixel = int(line[-2:], 16)
                ifm_pixels.append(pixel)
    
    # Reshape to (32, 32)
    ifm = np.array(ifm_pixels, dtype=np.uint8).reshape(32, 32)
    
    # 2. Parse Weights (400 lines of 128-bit hex)
    # 16 cout * 5 * 5 = 400 tiles
    # Tile index = y * 5 + x
    # Each tile has 16 lines (cin=0 to 15). Line 0 has valid weights for cin=0.
    # Weight values for cout 0 to 15 are stored in reversed byte order (cout=15 is MSB, cout=0 is LSB)
    weights = np.zeros((16, 5, 5), dtype=np.int8)
    with open(weight_path, 'r') as f:
        lines = f.read().splitlines()
        
    for y in range(5):
        for x in range(5):
            tile_idx = y * 5 + x
            line = lines[tile_idx * 16].strip()
            # 32 hex chars = 16 bytes
            for cout in range(16):
                byte_str = line[32 - 2 * (cout + 1) : 32 - 2 * cout]
                val = int(byte_str, 16)
                if val >= 128:
                    val -= 256
                weights[cout, y, x] = val
                
    # 3. Parse Biases (16 lines of 32-bit hex)
    biases = np.zeros(16, dtype=np.int32)
    with open(bias_path, 'r') as f:
        for cout in range(16):
            line = f.readline().strip()
            val = int(line, 16)
            if val >= 0x80000000:
                val -= 0x100000000
            biases[cout] = val
            
    # 4. Generate golden psums matching Verilog tb execution loops
    # Loop matches tb_pea_conv1.sv:
    #   pass (0..1)
    #   out_y (0..27)
    #   out_x_base (0..27, step 5)
    #     row (0..4)
    #     col (0..4)
    #       step (0..24) (ky = step//5, kx = step%5)
    
    with open(output_path, 'w') as out_f:
        for p in range(2):
            for out_y in range(28):
                for out_x_base in range(0, 28, 5):
                    for row in range(5):
                        for col in range(5):
                            oc = row if p == 0 else 5
                            out_x = out_x_base + col
                            
                            # Start value is bias
                            acc = int(biases[oc])
                            
                            for step in range(25):
                                ky = step // 5
                                kx = step % 5
                                
                                # Compute input pixel
                                actual_y = out_y + ky
                                actual_x = out_x + kx
                                
                                ifm_val = int(ifm[actual_y, actual_x]) if (actual_x < 32 and actual_y < 32) else 0
                                w_val = int(weights[oc, ky, kx])
                                
                                # Accumulate
                                acc += ifm_val * w_val
                                
                                # Write to log file
                                out_f.write(f"[PSUM] pass={p} y={out_y} x_base={out_x_base} row={row} col={col} step={step} | acc={acc}\n")
                                
    print(f"Generated golden psums successfully in: {output_path}")

if __name__ == "__main__":
    main()
