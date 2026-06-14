#!/usr/bin/env python3
"""
instruction_compiler.py - Software Register Map and Instruction Compiler for LeNet-5 on Basys-3

Defines the virtual register map address offsets and packs layer configurations
into 64-bit hexadecimal words to load into the FPGA Instruction Memory.
"""

import sys

# ==============================================================================
# 1. REGISTER MAP DEFINITIONS
# ==============================================================================
# Virtual region addresses parsed by the Global Arbiter (13-bit virtual address)
# Each region is allocated 1024 addresses (10-bit address bus per bank)
REGION_LOAD   = 0x0000  # Region 0: Trigger LOAD state (write 1 to offset 0)
REGION_START  = 0x0400  # Region 1: Trigger START state (write 1 to offset 0)
REGION_DONE   = 0x0800  # Region 2: Trigger DONE state (write 1 to offset 0)
REGION_PING   = 0x0C00  # Region 3: Ping feature map bank memory (0x0C00 - 0x0FFF)
REGION_PONG   = 0x1000  # Region 4: Pong feature map bank memory (0x1000 - 0x13FF)
REGION_WEIGHT = 0x1400  # Region 5: Weight bank memory (0x1400 - 0x17FF)
REGION_BIAS   = 0x1800  # Region 6: Bias bank memory (0x1800 - 0x1BFF)
REGION_INST   = 0x1C00  # Region 7: Instruction memory (0x1C00 - 0x1FFF)

# ==============================================================================
# 2. INSTRUCTION COMPILER HELPER
# ==============================================================================
def compile_instruction(layer_type, input_dim, in_channels, out_channels, kernel_dim, stride, padding, activation):
    """
    Packs layer parameters into a 64-bit integer following the FPGA ISA layout:
      [63:60] : layer_type (0: None, 1: Conv, 2: Pool, 3: Fully Connected)
      [59:44] : input_dim
      [43:32] : in_channels
      [31:20] : out_channels
      [19:16] : kernel_dim
      [15:12] : stride
      [11:8]  : padding
      [7:0]   : activation (0: None, 1: ReLU)
    """
    lt  = int(layer_type)  & 0xF
    idm = int(input_dim)   & 0xFFFF
    ic  = int(in_channels) & 0xFFF
    oc  = int(out_channels) & 0xFFF
    kd  = int(kernel_dim)  & 0xF
    sd  = int(stride)      & 0xF
    pd  = int(padding)     & 0xF
    act = int(activation)  & 0xFF
    
    instr = (lt << 60) | (idm << 44) | (ic << 32) | (oc << 20) | (kd << 16) | (sd << 12) | (pd << 8) | act
    return instr

# ==============================================================================
# 3. LENET-5 COMPILED INSTRUCTION SEQUENCE
# ==============================================================================
def get_lenet5_instructions():
    """
    Returns the compiled 64-bit instruction sequence representing all 7 layers of LeNet-5.
    """
    layers = [
        # Layer 1: C1 (Conv 2D, Input 32x32x1, Output 28x28x6, Kernel 5x5, ReLU)
        {"name": "C1",     "args": (1, 32, 1, 6, 5, 1, 0, 1)},
        # Layer 2: S2 (MaxPool, Input 28x28x6, Output 14x14x6, Kernel 2x2, Stride 2)
        {"name": "S2",     "args": (2, 28, 6, 6, 2, 2, 0, 0)},
        # Layer 3: C3 (Conv 2D, Input 14x14x6, Output 10x10x16, Kernel 5x5, ReLU)
        {"name": "C3",     "args": (1, 14, 6, 16, 5, 1, 0, 1)},
        # Layer 4: S4 (MaxPool, Input 10x10x16, Output 5x5x16, Kernel 2x2, Stride 2)
        {"name": "S4",     "args": (2, 10, 16, 16, 2, 2, 0, 0)},
        # Layer 5: C5 (Conv 2D / FC, Input 5x5x16, Output 1x1x120, Kernel 5x5, ReLU)
        {"name": "C5",     "args": (1, 5, 16, 120, 5, 1, 0, 1)},
        # Layer 6: F6 (Fully Connected, Input 1x1x120, Output 1x1x84, Kernel 1x1, ReLU)
        {"name": "F6",     "args": (3, 1, 120, 84, 1, 1, 0, 1)},
        # Layer 7: Output (Fully Connected, Input 1x1x84, Output 1x1x10, Kernel 1x1)
        {"name": "Output", "args": (3, 1, 84, 10, 1, 1, 0, 0)}
    ]
    
    compiled = []
    for l in layers:
        word = compile_instruction(*l["args"])
        compiled.append((l["name"], word))
    return compiled

# ==============================================================================
# MAIN TEST DIAGNOSTIC
# ==============================================================================
if __name__ == "__main__":
    print("=== LeNet-5 Instruction Compiler ===")
    print(f"Register Map Regions:")
    print(f"  REGION_LOAD   : {REGION_LOAD:#06x}")
    print(f"  REGION_START  : {REGION_START:#06x}")
    print(f"  REGION_DONE   : {REGION_DONE:#06x}")
    print(f"  REGION_PING   : {REGION_PING:#06x}")
    print(f"  REGION_PONG   : {REGION_PONG:#06x}")
    print(f"  REGION_WEIGHT : {REGION_WEIGHT:#06x}")
    print(f"  REGION_BIAS   : {REGION_BIAS:#06x}")
    print(f"  REGION_INST   : {REGION_INST:#06x}")
    print()
    
    print("Compiled Instruction Sequence (64-bit hex):")
    lenet_sequence = get_lenet5_instructions()
    for idx, (name, word) in enumerate(lenet_sequence):
        print(f"  Inst {idx} ({name:<6}): {word:016x}")
