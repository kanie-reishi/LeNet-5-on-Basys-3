#!/usr/bin/env python3
"""
LeNet-5 Basys-3 FPGA UART Host Script
Loads quantized Q8.8 weights, biases, and input image over UART,
starts inference, and reads back classification predictions.
"""

import os
import sys
import time
import argparse

try:
    import serial
except ImportError:
    print("[ERROR] pyserial is required. Install via: pip install pyserial")
    sys.exit(1)

# Command Constants
CMD_WRITE_MEM       = 0x01
CMD_READ_MEM        = 0x02
CMD_START_INFERENCE = 0x03
CMD_CHECK_STATUS    = 0x04

# Region IDs
W_LOAD_CTRL = 0
W_START     = 1
W_DONE_CLR  = 2
W_PING_FM   = 3
W_PONG_FM   = 4
W_WEIGHT    = 5
W_BIAS      = 6

# Base Offsets (matching verilog)
CONV1_W_BASE = 0
CONV2_W_BASE = 200
FC1_W_BASE   = 4200
FC2_W_BASE   = 55400
FC3_W_BASE   = 68840

CONV1_B_BASE = 0
CONV2_B_BASE = 8
FC1_B_BASE   = 28
FC2_B_BASE   = 156
FC3_B_BASE   = 240

NBANKS = 5

def create_uart_packet(cmd: int, payload: list[int]) -> bytes:
    """Forms a framed packet: STX + CMD + LEN(2B) + PAYLOAD + CHECKSUM + ETX"""
    length = len(payload)
    len_h = (length >> 8) & 0xFF
    len_l = length & 0xFF
    
    # Calculate checksum
    chk = cmd ^ len_h ^ len_l
    for b in payload:
        chk ^= b
        
    packet = bytearray([0x02, cmd, len_h, len_l]) + bytearray(payload) + bytearray([chk, 0x03])
    return bytes(packet)

def send_packet_and_wait_ack(ser: serial.Serial, cmd: int, payload: list[int], max_retries=3) -> bool:
    packet = create_uart_packet(cmd, payload)
    
    for retry in range(max_retries):
        ser.write(packet)
        ser.flush()
        
        # Wait for response (expecting 1 byte ACK 0x06 or NACK 0x15)
        resp = ser.read(1)
        if len(resp) == 1:
            if resp[0] == 0x06:
                return True
            elif resp[0] == 0x15:
                print(f"[WARN] NACK received on attempt {retry+1}. Retrying...")
            else:
                print(f"[WARN] Unexpected response {hex(resp[0])} received.")
        else:
            print(f"[WARN] UART Timeout on attempt {retry+1}. Retrying...")
            
    return False

def write_mem_word(ser: serial.Serial, region: int, offset: int, data: int) -> bool:
    """Writes a 16-bit word to region at offset"""
    # Address is 24-bit big endian: {region[2:0], offset[16:0]}
    addr_24 = (region << 17) | (offset & 0x1FFFF)
    
    payload = [
        (addr_24 >> 16) & 0xFF,
        (addr_24 >> 8) & 0xFF,
        addr_24 & 0xFF,
        (data >> 8) & 0xFF,
        data & 0xFF
    ]
    return send_packet_and_wait_ack(ser, CMD_WRITE_MEM, payload)

def load_bias_file(ser: serial.Serial, file_path: str, base_addr: int):
    print(f"[HOST] Loading bias file: {os.path.basename(file_path)}...")
    with open(file_path, 'r') as f:
        lines = f.readlines()
        
    addr = base_addr
    for line in lines:
        val = line.strip()
        if val:
            word = int(val, 16) & 0xFFFF
            if not write_mem_word(ser, W_BIAS, addr, word):
                raise RuntimeError(f"Failed to write bias at addr {addr}")
            addr += 1
    print(f"[HOST] Loaded {addr - base_addr} bias values.")

def load_conv_weight_file(ser: serial.Serial, file_path: str, base_addr: int, out_ch: int, in_ch: int, kernel: int):
    print(f"[HOST] Loading conv weight file: {os.path.basename(file_path)}...")
    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
        
    idx = 0
    for oc in range(out_ch):
        for ic in range(in_ch):
            for ky in range(kernel):
                for kx in range(kernel):
                    word = int(lines[idx], 16) & 0xFFFF
                    weight_addr = base_addr + (((oc * in_ch + ic) * kernel * kernel) + (ky * kernel) + kx)
                    if not write_mem_word(ser, W_WEIGHT, weight_addr, word):
                        raise RuntimeError(f"Failed to write weight at addr {weight_addr}")
                    idx += 1
    print(f"[HOST] Loaded {idx} conv weights.")

def load_fc1_weight_file(ser: serial.Serial, file_path: str, base_addr: int, out_len: int, in_len: int):
    print(f"[HOST] Loading FC1 weight file: {os.path.basename(file_path)}...")
    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
        
    fc_weight_mem = [int(val, 16) & 0xFFFF for val in lines]
    chunk_count = (in_len + 3) // 4
    
    for o in range(out_len):
        for chunk in range(chunk_count):
            packed_addr = (base_addr // NBANKS) + (o * chunk_count) + chunk
            block_base = (chunk // 4) * 16
            local_col = chunk % 4
            
            for bank in range(4):
                ii = block_base + (bank * 4) + local_col
                weight_addr = (packed_addr * NBANKS) + bank
                
                if ii < in_len and ((o * in_len) + ii) < len(fc_weight_mem):
                    word = fc_weight_mem[(o * in_len) + ii]
                else:
                    word = 0
                    
                if not write_mem_word(ser, W_WEIGHT, weight_addr, word):
                    raise RuntimeError(f"Failed to write FC1 weight at addr {weight_addr}")
                    
            # Bank 4 zero pad
            weight_addr = (packed_addr * NBANKS) + 4
            if not write_mem_word(ser, W_WEIGHT, weight_addr, 0):
                raise RuntimeError(f"Failed to write FC1 padding at addr {weight_addr}")

def load_fc_linear_weight_file(ser: serial.Serial, file_path: str, base_addr: int, out_len: int, in_len: int):
    print(f"[HOST] Loading FC linear weight file: {os.path.basename(file_path)}...")
    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
        
    fc_weight_mem = [int(val, 16) & 0xFFFF for val in lines]
    chunk_count = (in_len + 3) // 4
    
    for o in range(out_len):
        for chunk in range(chunk_count):
            packed_addr = (base_addr // NBANKS) + (o * chunk_count) + chunk
            
            for bank in range(4):
                ii = (chunk * 4) + bank
                weight_addr = (packed_addr * NBANKS) + bank
                
                if ii < in_len and ((o * in_len) + ii) < len(fc_weight_mem):
                    word = fc_weight_mem[(o * in_len) + ii]
                else:
                    word = 0
                    
                if not write_mem_word(ser, W_WEIGHT, weight_addr, word):
                    raise RuntimeError(f"Failed to write FC weight at addr {weight_addr}")
                    
            # Bank 4 zero pad
            weight_addr = (packed_addr * NBANKS) + 4
            if not write_mem_word(ser, W_WEIGHT, weight_addr, 0):
                raise RuntimeError(f"Failed to write FC padding at addr {weight_addr}")

def load_input_file(ser: serial.Serial, file_path: str, height: int, width: int):
    print(f"[HOST] Loading input image file: {os.path.basename(file_path)}...")
    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
        
    input_mem = [int(val, 16) & 0xFFFF for val in lines]
    bank_depth = ((height + NBANKS - 1) // NBANKS) * width
    
    for addr in range(bank_depth):
        row_block_idx = addr // width
        col_idx = addr % width
        
        for bank_idx in range(NBANKS):
            row_idx = (row_block_idx * NBANKS) + bank_idx
            axi_addr = (addr * NBANKS) + bank_idx
            pixel_idx = (row_idx * width) + col_idx
            
            if row_idx < height:
                word = input_mem[pixel_idx]
            else:
                word = 0
                
            if not write_mem_word(ser, W_PING_FM, axi_addr, word):
                raise RuntimeError(f"Failed to write input pixel at addr {axi_addr}")

def main():
    parser = argparse.ArgumentParser(description="LeNet-5 Basys-3 FPGA UART Host Loader")
    parser.add_argument("port", help="Serial port name (e.g. COM3 or /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate (default: 115200)")
    parser.add_argument("--image", default="Fixed_AI_Accelerator/Explicit_Model/tb_vectors/sample0/input_q16.txt",
                        help="Path to MNIST input image hex text file")
    parser.add_argument("--param-dir", default="Fixed_AI_Accelerator/Low_Precision_Model/exports/fixed_q16/fixed_q16_params",
                        help="Path to weight/bias parameter directory")
    args = parser.parse_args()

    # Open serial port
    print(f"[HOST] Opening serial port {args.port} at {args.baud} baud...")
    try:
        ser = serial.Serial(args.port, args.baud, timeout=2.0)
    except Exception as e:
        print(f"[ERROR] Could not open serial port: {e}")
        return
        
    try:
        start_time = time.time()
        
        # 1. Pulse LOAD_CTRL
        print("[HOST] Transitioning FSM to S_WAIT_LOAD...")
        if not write_mem_word(ser, W_LOAD_CTRL, 0, 1):
            print("[ERROR] Failed to send LOAD command.")
            return
            
        # 2. Load Input Image
        load_input_file(ser, args.image, 28, 28)
        
        # 3. Load Biases & Weights
        load_bias_file(ser, f"{args.param-dir}/conv1_bias_q16.txt", CONV1_B_BASE)
        load_conv_weight_file(ser, f"{args.param-dir}/conv1_weight_q16.txt", CONV1_W_BASE, 8, 1, 5)
        
        load_bias_file(ser, f"{args.param-dir}/conv2_bias_q16.txt", CONV2_B_BASE)
        load_conv_weight_file(ser, f"{args.param-dir}/conv2_weight_q16.txt", CONV2_W_BASE, 20, 8, 5)
        
        load_bias_file(ser, f"{args.param-dir}/fc1_bias_q16.txt", FC1_B_BASE)
        load_fc1_weight_file(ser, f"{args.param-dir}/fc1_weight_q16.txt", FC1_W_BASE, 128, 320)
        
        load_bias_file(ser, f"{args.param-dir}/fc2_bias_q16.txt", FC2_B_BASE)
        load_fc_linear_weight_file(ser, f"{args.param-dir}/fc2_weight_q16.txt", FC2_W_BASE, 84, 128)
        
        load_bias_file(ser, f"{args.param-dir}/fc3_bias_q16.txt", FC3_B_BASE)
        load_fc_linear_weight_file(ser, f"{args.param-dir}/fc3_weight_q16.txt", FC3_W_BASE, 10, 84)
        
        # 4. Trigger START_INFERENCE
        print("[HOST] Starting Inference...")
        start_inf_packet = create_uart_packet(CMD_START_INFERENCE, [])
        ser.write(start_inf_packet)
        ser.flush()
        # Expect ACK
        resp = ser.read(1)
        if not resp or resp[0] != 0x06:
            print("[ERROR] Failed to start inference.")
            return
            
        print("[HOST] Inference running, polling status...")
        
        # 5. Poll Status
        chk_status_packet = create_uart_packet(CMD_CHECK_STATUS, [])
        done = False
        prediction = -1
        
        for poll in range(100):
            ser.write(chk_status_packet)
            ser.flush()
            
            # Response: STX + CMD_CHECK_STATUS (0x04) + LEN(2B: 0x00, 0x02) + DATA_H + DATA_L + CHECKSUM + ETX
            resp = ser.read(8)
            if len(resp) == 8 and resp[0] == 0x02 and resp[1] == CMD_CHECK_STATUS:
                status_word = (resp[4] << 8) | resp[5]
                valid = status_word & 0x01
                pred_val = (status_word >> 1) & 0x0F
                
                if valid:
                    done = True
                    prediction = pred_val
                    break
            else:
                print(f"[WARN] Invalid poll response: {resp.hex() if resp else 'None'}")
                
            time.sleep(0.05)
            
        if done:
            print("\n" + "="*40)
            print(f"[SUCCESS] Inference Completed in {time.time() - start_time:.2f} seconds!")
            print(f"[RESULT] Predicted Digit: {prediction}")
            print("="*40 + "\n")
        else:
            print("[FAIL] Timeout waiting for inference to complete.")
            
        # 6. Pulse DONE_CLR to go back to IDLE
        write_mem_word(ser, W_DONE_CLR, 0, 1)
        
    finally:
        ser.close()
        print("[HOST] Serial port closed.")

if __name__ == "__main__":
    main()
