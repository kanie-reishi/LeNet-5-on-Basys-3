#!/usr/bin/env python3
"""
LeNet-5 Basys-3 FPGA UART Host
Loads quantized Q8.8 weights, biases, and input image over UART,
starts inference, and reads back classification predictions.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from dataclasses import dataclass
from typing import Callable, Optional

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    serial = None  # type: ignore[assignment]
    list_ports = None  # type: ignore[assignment]

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_PARAM_DIR = os.path.join(PROJECT_ROOT, "tb", "fixed_q16_params")
DEFAULT_INPUT = os.path.join(DEFAULT_PARAM_DIR, "input_q16.txt")
MNIST_ROWS_FILE = os.path.join(DEFAULT_PARAM_DIR, "mnist_test_inputs_q16_rows.txt")
MNIST_LABELS_FILE = os.path.join(DEFAULT_PARAM_DIR, "mnist_test_labels.txt")

# Command constants
CMD_WRITE_MEM = 0x01
CMD_READ_MEM = 0x02
CMD_START_INFERENCE = 0x03
CMD_CHECK_STATUS = 0x04
CMD_BURST_WRITE = 0x05

MAX_BURST_WORDS = 30
DEFAULT_BAUD_RATE = 921600

# Burst writes require FPGA bitstream with CMD 0x05 (enabled by default).
_burst_writes_enabled = True


def set_burst_writes(enabled: bool) -> None:
    global _burst_writes_enabled
    _burst_writes_enabled = enabled


def burst_writes_enabled() -> bool:
    return _burst_writes_enabled

# Region IDs
W_LOAD_CTRL = 0
W_START = 1
W_DONE_CLR = 2
W_PING_FM = 3
W_PONG_FM = 4
W_WEIGHT = 5
W_BIAS = 6

# Base offsets (matching verilog)
CONV1_W_BASE = 0
CONV2_W_BASE = 200
FC1_W_BASE = 4200
FC2_W_BASE = 55400
FC3_W_BASE = 68840

CONV1_B_BASE = 0
CONV2_B_BASE = 8
FC1_B_BASE = 28
FC2_B_BASE = 156
FC3_B_BASE = 240

NBANKS = 5

LogCallback = Callable[[str], None]
ProgressCallback = Callable[[str, float], None]
CancelCallback = Callable[[], bool]


@dataclass
class InferenceResult:
    success: bool
    prediction: int = -1
    elapsed_s: float = 0.0
    expected_label: Optional[int] = None
    message: str = ""


@dataclass
class SerialPortInfo:
    device: str
    description: str
    hwid: str = ""

    @property
    def label(self) -> str:
        return f"{self.device} — {self.description}"


def list_serial_ports_detailed() -> list[SerialPortInfo]:
    if list_ports is None:
        return []

    ports: list[SerialPortInfo] = []
    for port in list_ports.comports():
        ports.append(
            SerialPortInfo(
                device=port.device,
                description=port.description or "Unknown device",
                hwid=port.hwid or "",
            )
        )
    return ports


def list_serial_ports() -> list[str]:
    return [port.device for port in list_serial_ports_detailed()]


def pick_basys_serial_port(ports: list[SerialPortInfo]) -> Optional[SerialPortInfo]:
    for info in ports:
        haystack = f"{info.description} {info.hwid}".lower()
        if "digilent" in haystack or "0403:6010" in haystack:
            return info

    for info in ports:
        if "usb serial" in info.description.lower():
            return info

    return ports[0] if ports else None


def format_serial_open_error(port: str, exc: BaseException) -> str:
    message = str(exc).strip() or repr(exc)
    lowered = message.lower()

    if (
        isinstance(exc, PermissionError)
        or "access is denied" in lowered
        or "permission" in lowered
        or "being used by another" in lowered
    ):
        return (
            f"Cannot open {port}: access denied.\n\n"
            "Another program is probably using this COM port. Close:\n"
            "  - Vivado Hardware Manager\n"
            "  - PuTTY, Tera Term, or Arduino IDE\n"
            "  - Another copy of this UART host\n\n"
            "Unplug/replug the Basys-3 USB cable if needed, click Refresh,\n"
            "then connect again."
        )

    if isinstance(exc, FileNotFoundError) or "could not open port" in lowered and "no such file" in lowered:
        return (
            f"Port {port} was not found.\n\n"
            "Click Refresh after plugging in the Basys-3 and select the\n"
            "Digilent / USB Serial COM port."
        )

    return f"Cannot open {port}:\n{message}"


def open_serial_port(port: str, baud: int = DEFAULT_BAUD_RATE, timeout: float = 2.0) -> serial.Serial:
    if serial is None:
        raise RuntimeError("pyserial is not installed. Run: pip install pyserial")

    try:
        handle = serial.Serial()
        handle.port = port
        handle.baudrate = baud
        handle.timeout = timeout
        handle.inter_byte_timeout = 0.05
        handle.open()
        return handle
    except Exception as exc:
        raise RuntimeError(format_serial_open_error(port, exc)) from exc


def create_uart_packet(cmd: int, payload: list[int]) -> bytes:
    """Forms a framed packet: STX + CMD + LEN(2B) + PAYLOAD + CHECKSUM + ETX."""
    length = len(payload)
    len_h = (length >> 8) & 0xFF
    len_l = length & 0xFF

    chk = cmd ^ len_h ^ len_l
    for byte in payload:
        chk ^= byte

    return bytes([0x02, cmd, len_h, len_l, *payload, chk, 0x03])


def drain_serial_input(ser: serial.Serial) -> None:
    old_timeout = ser.timeout
    ser.timeout = 0.05
    try:
        while ser.read(512):
            pass
    finally:
        ser.timeout = old_timeout


def _packet_checksum(cmd: int, payload: bytes) -> int:
    length = len(payload)
    chk = cmd ^ ((length >> 8) & 0xFF) ^ (length & 0xFF)
    for byte in payload:
        chk ^= byte
    return chk & 0xFF


def read_uart_response_packet(
    ser: serial.Serial,
    expected_cmd: Optional[int] = None,
    timeout: float = 0.5,
    prefix: bytes = b"",
) -> Optional[bytes]:
    """Read one framed host response packet, resynchronizing on STX."""
    deadline = time.time() + timeout
    buffer = bytearray(prefix)

    while time.time() < deadline:
        if len(buffer) < 4 or len(buffer) < 4 + ((buffer[2] << 8) | buffer[3]) + 2:
            chunk = ser.read(1)
            if chunk:
                buffer.extend(chunk)

        while buffer and buffer[0] != 0x02:
            buffer.pop(0)

        if len(buffer) < 4:
            continue

        payload_len = (buffer[2] << 8) | buffer[3]
        frame_len = 4 + payload_len + 2
        if len(buffer) < frame_len:
            continue

        frame = bytes(buffer[:frame_len])
        del buffer[:frame_len]

        if frame[-1] != 0x03:
            continue

        cmd = frame[1]
        payload = frame[4:-2]
        if _packet_checksum(cmd, payload) != frame[-2]:
            continue
        if expected_cmd is not None and cmd != expected_cmd:
            continue

        return frame

    return None


def read_uart_ack(ser: serial.Serial, timeout: float = 0.5) -> Optional[bool]:
    """Return True for ACK, False for NACK, None on timeout."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        byte = ser.read(1)
        if not byte:
            continue

        value = byte[0]
        if value == 0x06:
            return True
        if value == 0x15:
            return False
        if value == 0x02:
            read_uart_response_packet(
                ser,
                timeout=max(0.0, deadline - time.time()),
                prefix=byte,
            )

    return None


def send_packet_and_wait_ack(
    ser: serial.Serial,
    cmd: int,
    payload: list[int],
    max_retries: int = 3,
    on_log: Optional[LogCallback] = None,
) -> bool:
    packet = create_uart_packet(cmd, payload)

    for retry in range(max_retries):
        ser.write(packet)
        ack = read_uart_ack(ser, timeout=0.75)
        if ack is True:
            return True
        if ack is False:
            if on_log:
                on_log(f"[WARN] NACK received on attempt {retry + 1}. Retrying...")
        elif on_log:
            on_log(f"[WARN] UART timeout on attempt {retry + 1}. Retrying...")

    return False


def reset_fpga_inference_state(
    ser: serial.Serial,
    on_log: Optional[LogCallback] = None,
) -> None:
    """Return controller to IDLE so the next UART run can start cleanly."""
    if on_log:
        on_log("[HOST] Resetting FPGA inference state...")
    drain_serial_input(ser)
    write_mem_word(ser, W_DONE_CLR, 0, 1, on_log=on_log)
    time.sleep(0.05)
    drain_serial_input(ser)


def poll_inference_status(
    ser: serial.Serial,
    on_log: Optional[LogCallback] = None,
) -> Optional[tuple[bool, int]]:
    packet = create_uart_packet(CMD_CHECK_STATUS, [])
    ser.write(packet)

    frame = read_uart_response_packet(ser, CMD_CHECK_STATUS, timeout=0.5)
    if frame is None:
        return None

    status_word = (frame[4] << 8) | frame[5]
    valid = bool(status_word & 0x01)
    prediction = (status_word >> 1) & 0x0F
    return valid, prediction


def write_mem_word(
    ser: serial.Serial,
    region: int,
    offset: int,
    data: int,
    on_log: Optional[LogCallback] = None,
) -> bool:
    return write_mem_burst(ser, region, offset, [data], on_log=on_log)


def write_mem_burst(
    ser: serial.Serial,
    region: int,
    offset: int,
    words: list[int],
    on_log: Optional[LogCallback] = None,
) -> bool:
    if not 1 <= len(words) <= MAX_BURST_WORDS:
        raise ValueError(f"Burst write supports 1-{MAX_BURST_WORDS} words, got {len(words)}")

    addr_24 = (region << 17) | (offset & 0x1FFFF)
    addr_bytes = [
        (addr_24 >> 16) & 0xFF,
        (addr_24 >> 8) & 0xFF,
        addr_24 & 0xFF,
    ]

    if len(words) == 1:
        word = words[0]
        payload = addr_bytes + [(word >> 8) & 0xFF, word & 0xFF]
        return send_packet_and_wait_ack(ser, CMD_WRITE_MEM, payload, on_log=on_log)

    if not _burst_writes_enabled:
        for index, word in enumerate(words):
            word_addr = (region << 17) | ((offset + index) & 0x1FFFF)
            single_payload = [
                (word_addr >> 16) & 0xFF,
                (word_addr >> 8) & 0xFF,
                word_addr & 0xFF,
                (word >> 8) & 0xFF,
                word & 0xFF,
            ]
            if not send_packet_and_wait_ack(ser, CMD_WRITE_MEM, single_payload, on_log=on_log):
                return False
        return True

    payload = addr_bytes + [len(words)]
    for word in words:
        payload.append((word >> 8) & 0xFF)
        payload.append(word & 0xFF)

    if send_packet_and_wait_ack(ser, CMD_BURST_WRITE, payload, on_log=on_log):
        return True

    if on_log:
        on_log("[WARN] Burst write not supported by FPGA; falling back to single-word writes.")

    for index, word in enumerate(words):
        word_addr = (region << 17) | ((offset + index) & 0x1FFFF)
        single_payload = [
            (word_addr >> 16) & 0xFF,
            (word_addr >> 8) & 0xFF,
            word_addr & 0xFF,
            (word >> 8) & 0xFF,
            word & 0xFF,
        ]
        if not send_packet_and_wait_ack(ser, CMD_WRITE_MEM, single_payload, on_log=on_log):
            return False

    return True


def write_mem_block(
    ser: serial.Serial,
    region: int,
    offset: int,
    words: list[int],
    on_log: Optional[LogCallback] = None,
) -> None:
    idx = 0
    while idx < len(words):
        chunk = words[idx : idx + MAX_BURST_WORDS]
        if not write_mem_burst(ser, region, offset + idx, chunk, on_log=on_log):
            raise RuntimeError(f"Failed burst write at offset {offset + idx}")
        idx += len(chunk)


def load_bias_file(
    ser: serial.Serial,
    file_path: str,
    base_addr: int,
    on_log: Optional[LogCallback] = None,
) -> None:
    if on_log:
        on_log(f"[HOST] Loading bias file: {os.path.basename(file_path)}...")

    with open(file_path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()

    words: list[int] = []
    for line in lines:
        val = line.strip()
        if val:
            words.append(int(val, 16) & 0xFFFF)

    write_mem_block(ser, W_BIAS, base_addr, words, on_log=on_log)

    if on_log:
        on_log(f"[HOST] Loaded {len(words)} bias values.")


def load_conv_weight_file(
    ser: serial.Serial,
    file_path: str,
    base_addr: int,
    out_ch: int,
    in_ch: int,
    kernel: int,
    on_log: Optional[LogCallback] = None,
) -> None:
    if on_log:
        on_log(f"[HOST] Loading conv weight file: {os.path.basename(file_path)}...")

    with open(file_path, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]

    words = [int(line, 16) & 0xFFFF for line in lines]
    write_mem_block(ser, W_WEIGHT, base_addr, words, on_log=on_log)

    if on_log:
        on_log(f"[HOST] Loaded {len(words)} conv weights.")


def load_fc1_weight_file(
    ser: serial.Serial,
    file_path: str,
    base_addr: int,
    out_len: int,
    in_len: int,
    on_log: Optional[LogCallback] = None,
) -> None:
    if on_log:
        on_log(f"[HOST] Loading FC1 weight file: {os.path.basename(file_path)}...")

    with open(file_path, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]

    fc_weight_mem = [int(val, 16) & 0xFFFF for val in lines]
    chunk_count = (in_len + 3) // 4

    for o in range(out_len):
        for chunk in range(chunk_count):
            packed_addr = (base_addr // NBANKS) + (o * chunk_count) + chunk
            block_base = (chunk // 4) * 16
            local_col = chunk % 4
            burst_words: list[int] = []

            for bank in range(4):
                ii = block_base + (bank * 4) + local_col
                if ii < in_len and ((o * in_len) + ii) < len(fc_weight_mem):
                    burst_words.append(fc_weight_mem[(o * in_len) + ii])
                else:
                    burst_words.append(0)

            burst_words.append(0)
            if not write_mem_burst(ser, W_WEIGHT, packed_addr * NBANKS, burst_words, on_log=on_log):
                raise RuntimeError(f"Failed to write FC1 burst at addr {packed_addr * NBANKS}")


def load_fc_linear_weight_file(
    ser: serial.Serial,
    file_path: str,
    base_addr: int,
    out_len: int,
    in_len: int,
    on_log: Optional[LogCallback] = None,
) -> None:
    if on_log:
        on_log(f"[HOST] Loading FC linear weight file: {os.path.basename(file_path)}...")

    with open(file_path, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]

    fc_weight_mem = [int(val, 16) & 0xFFFF for val in lines]
    chunk_count = (in_len + 3) // 4

    for o in range(out_len):
        for chunk in range(chunk_count):
            packed_addr = (base_addr // NBANKS) + (o * chunk_count) + chunk
            burst_words: list[int] = []

            for bank in range(4):
                ii = (chunk * 4) + bank
                if ii < in_len and ((o * in_len) + ii) < len(fc_weight_mem):
                    burst_words.append(fc_weight_mem[(o * in_len) + ii])
                else:
                    burst_words.append(0)

            burst_words.append(0)
            if not write_mem_burst(ser, W_WEIGHT, packed_addr * NBANKS, burst_words, on_log=on_log):
                raise RuntimeError(f"Failed to write FC burst at addr {packed_addr * NBANKS}")


def load_input_words(
    ser: serial.Serial,
    input_mem: list[int],
    height: int,
    width: int,
    on_log: Optional[LogCallback] = None,
) -> None:
    bank_depth = ((height + NBANKS - 1) // NBANKS) * width

    for addr in range(bank_depth):
        row_block_idx = addr // width
        col_idx = addr % width
        burst_words: list[int] = []

        for bank_idx in range(NBANKS):
            row_idx = (row_block_idx * NBANKS) + bank_idx
            pixel_idx = (row_idx * width) + col_idx

            if row_idx < height:
                burst_words.append(input_mem[pixel_idx])
            else:
                burst_words.append(0)

        if not write_mem_burst(ser, W_PING_FM, addr * NBANKS, burst_words, on_log=on_log):
            raise RuntimeError(f"Failed to write input burst at addr {addr * NBANKS}")


def load_input_file(
    ser: serial.Serial,
    file_path: str,
    height: int,
    width: int,
    on_log: Optional[LogCallback] = None,
) -> None:
    if on_log:
        on_log(f"[HOST] Loading input image file: {os.path.basename(file_path)}...")

    with open(file_path, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]

    input_mem = [int(val, 16) & 0xFFFF for val in lines]
    load_input_words(ser, input_mem, height, width, on_log=on_log)


def read_input_hex_file(file_path: str) -> list[int]:
    with open(file_path, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]
    return [int(val, 16) & 0xFFFF for val in lines]


def read_mnist_sample(index: int) -> tuple[list[int], Optional[int]]:
    with open(MNIST_ROWS_FILE, "r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle):
            if line_no == index:
                pixels = [int(val, 16) & 0xFFFF for val in line.split()]
                break
        else:
            raise IndexError(f"MNIST sample index {index} out of range")

    expected_label = None
    if os.path.isfile(MNIST_LABELS_FILE):
        with open(MNIST_LABELS_FILE, "r", encoding="utf-8") as handle:
            for line_no, line in enumerate(handle):
                if line_no == index:
                    expected_label = int(line.strip())
                    break

    return pixels, expected_label


def mnist_pixels_to_bytes(pixels: list[int]) -> list[int]:
    return [(word >> 8) & 0xFF for word in pixels]


def gray_byte_to_q16(value: int) -> int:
    return (int(value) & 0xFF) << 8


def gray_bytes_to_q16_pixels(gray: list[int]) -> list[int]:
    if len(gray) != 784:
        raise ValueError(f"Expected 784 grayscale pixels, got {len(gray)}")
    return [gray_byte_to_q16(value) for value in gray]


def load_all_weights(
    ser: serial.Serial,
    param_dir: str,
    on_log: Optional[LogCallback] = None,
    on_progress: Optional[ProgressCallback] = None,
    should_cancel: Optional[CancelCallback] = None,
) -> None:
    def log(message: str) -> None:
        if on_log:
            on_log(message)

    def progress(stage: str, fraction: float) -> None:
        if on_progress:
            on_progress(stage, fraction)

    def cancelled() -> bool:
        return bool(should_cancel and should_cancel())

    progress("Loading biases and weights", 0.0)
    load_bias_file(ser, os.path.join(param_dir, "conv1_bias_q16.txt"), CONV1_B_BASE, on_log=on_log)
    if cancelled():
        raise RuntimeError("Cancelled.")

    progress("Loading conv1 weights", 0.05)
    load_conv_weight_file(
        ser,
        os.path.join(param_dir, "conv1_weight_q16.txt"),
        CONV1_W_BASE,
        8,
        1,
        5,
        on_log=on_log,
    )
    if cancelled():
        raise RuntimeError("Cancelled.")

    progress("Loading conv2 weights", 0.12)
    load_bias_file(ser, os.path.join(param_dir, "conv2_bias_q16.txt"), CONV2_B_BASE, on_log=on_log)
    load_conv_weight_file(
        ser,
        os.path.join(param_dir, "conv2_weight_q16.txt"),
        CONV2_W_BASE,
        20,
        8,
        5,
        on_log=on_log,
    )
    if cancelled():
        raise RuntimeError("Cancelled.")

    progress("Loading FC1 weights", 0.25)
    load_bias_file(ser, os.path.join(param_dir, "fc1_bias_q16.txt"), FC1_B_BASE, on_log=on_log)
    load_fc1_weight_file(
        ser,
        os.path.join(param_dir, "fc1_weight_q16.txt"),
        FC1_W_BASE,
        128,
        320,
        on_log=on_log,
    )
    if cancelled():
        raise RuntimeError("Cancelled.")

    progress("Loading FC2/FC3 weights", 0.75)
    load_bias_file(ser, os.path.join(param_dir, "fc2_bias_q16.txt"), FC2_B_BASE, on_log=on_log)
    load_fc_linear_weight_file(
        ser,
        os.path.join(param_dir, "fc2_weight_q16.txt"),
        FC2_W_BASE,
        84,
        128,
        on_log=on_log,
    )

    load_bias_file(ser, os.path.join(param_dir, "fc3_bias_q16.txt"), FC3_B_BASE, on_log=on_log)
    load_fc_linear_weight_file(
        ser,
        os.path.join(param_dir, "fc3_weight_q16.txt"),
        FC3_W_BASE,
        10,
        84,
        on_log=on_log,
    )

    progress("Weights loaded", 1.0)
    log("[HOST] All weights and biases loaded to FPGA memory.")


def run_inference(
    ser: serial.Serial,
    image_path: str,
    param_dir: str,
    on_log: Optional[LogCallback] = None,
    on_progress: Optional[ProgressCallback] = None,
    should_cancel: Optional[CancelCallback] = None,
    expected_label: Optional[int] = None,
    input_pixels: Optional[list[int]] = None,
    reload_weights: bool = True,
) -> InferenceResult:
    def log(message: str) -> None:
        if on_log:
            on_log(message)

    def progress(stage: str, fraction: float) -> None:
        if on_progress:
            on_progress(stage, fraction)

    def cancelled() -> bool:
        return bool(should_cancel and should_cancel())

    start_time = time.time()

    try:
        reset_fpga_inference_state(ser, on_log=on_log)

        progress("Preparing FPGA", 0.02)
        log("[HOST] Transitioning FSM to S_WAIT_LOAD...")
        if not write_mem_word(ser, W_LOAD_CTRL, 0, 1, on_log=on_log):
            return InferenceResult(False, message="Failed to send LOAD command.")

        if cancelled():
            return InferenceResult(False, message="Cancelled.")

        progress("Loading input image", 0.08)
        if input_pixels is not None:
            log("[HOST] Loading selected MNIST sample...")
            load_input_words(ser, input_pixels, 28, 28, on_log=on_log)
        else:
            load_input_file(ser, image_path, 28, 28, on_log=on_log)

        if cancelled():
            return InferenceResult(False, message="Cancelled.")

        if reload_weights:
            load_all_weights(
                ser,
                param_dir,
                on_log=log,
                on_progress=progress,
                should_cancel=should_cancel,
            )
        else:
            log("[HOST] Skipping weight reload (fast mode). Using weights already in FPGA memory.")
            progress("Using cached weights", 0.15)

        if cancelled():
            return InferenceResult(False, message="Cancelled.")

        progress("Starting inference", 0.85)
        log("[HOST] Starting inference...")
        drain_serial_input(ser)
        if not send_packet_and_wait_ack(ser, CMD_START_INFERENCE, [], on_log=on_log):
            return InferenceResult(False, message="Failed to start inference.")

        log("[HOST] Inference running, polling status...")
        progress("Waiting for result", 0.90)

        prediction = -1
        for poll in range(300):
            if cancelled():
                return InferenceResult(False, message="Cancelled.")

            status = poll_inference_status(ser, on_log=on_log)
            if status is None:
                if on_log and poll % 20 == 0:
                    log(f"[HOST] Waiting for FPGA result... (poll {poll + 1})")
                time.sleep(0.05)
                continue

            valid, pred_val = status
            if valid:
                prediction = pred_val
                break

            time.sleep(0.05)

        drain_serial_input(ser)
        if not write_mem_word(ser, W_DONE_CLR, 0, 1, on_log=on_log):
            log("[WARN] DONE_CLR failed; next run may require reconnect or board reset.")
        time.sleep(0.05)
        drain_serial_input(ser)

        elapsed = time.time() - start_time
        if prediction >= 0:
            progress("Done", 1.0)
            message = f"Inference completed in {elapsed:.2f} s. Predicted digit: {prediction}"
            if expected_label is not None:
                match = "match" if prediction == expected_label else "mismatch"
                message += f" (expected {expected_label}, {match})"
            log(f"[SUCCESS] {message}")
            return InferenceResult(
                True,
                prediction=prediction,
                elapsed_s=elapsed,
                expected_label=expected_label,
                message=message,
            )

        progress("Failed", 1.0)
        return InferenceResult(False, message="Timeout waiting for inference to complete.")

    except Exception as exc:
        return InferenceResult(False, message=str(exc))


def main() -> None:
    if serial is None:
        print("[ERROR] pyserial is required. Install via: pip install pyserial")
        sys.exit(1)

    parser = argparse.ArgumentParser(description="LeNet-5 Basys-3 FPGA UART Host Loader")
    parser.add_argument("port", help="Serial port name (e.g. COM3 or /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=DEFAULT_BAUD_RATE, help="UART baud rate (default: 921600)")
    parser.add_argument("--image", default=DEFAULT_INPUT, help="Path to MNIST input image hex text file")
    parser.add_argument("--param-dir", default=DEFAULT_PARAM_DIR, help="Path to weight/bias parameter directory")
    parser.add_argument("--mnist-index", type=int, default=None, help="Use MNIST test sample index instead of --image")
    parser.add_argument(
        "--skip-weights",
        action="store_true",
        help="Skip weight upload; use weights already loaded in FPGA BRAM (fast mode)",
    )
    parser.add_argument(
        "--load-weights-only",
        action="store_true",
        help="Only upload weights/biases to FPGA, do not run inference",
    )
    parser.add_argument(
        "--no-burst",
        action="store_true",
        help="Disable UART burst writes (CMD 0x05); use with old bitstreams",
    )
    args = parser.parse_args()

    if args.no_burst:
        set_burst_writes(False)

    print(f"[HOST] Opening serial port {args.port} at {args.baud} baud...")
    try:
        ser = open_serial_port(args.port, args.baud, timeout=2.0)
    except RuntimeError as exc:
        print(f"[ERROR] {exc}")
        return

    try:
        if args.load_weights_only:
            load_all_weights(ser, args.param_dir, on_log=print)
            print("[HOST] Weight load complete.")
            return

        input_pixels = None
        expected_label = None
        image_path = args.image

        if args.mnist_index is not None:
            input_pixels, expected_label = read_mnist_sample(args.mnist_index)
            image_path = f"mnist_test[{args.mnist_index}]"

        result = run_inference(
            ser,
            image_path=image_path,
            param_dir=args.param_dir,
            on_log=print,
            input_pixels=input_pixels,
            expected_label=expected_label,
            reload_weights=not args.skip_weights,
        )

        if result.success:
            print("\n" + "=" * 40)
            print(f"[RESULT] Predicted Digit: {result.prediction}")
            print("=" * 40 + "\n")
        else:
            print(f"[FAIL] {result.message}")
    finally:
        ser.close()
        print("[HOST] Serial port closed.")


if __name__ == "__main__":
    main()
