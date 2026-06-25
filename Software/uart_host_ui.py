#!/usr/bin/env python3
"""Desktop UI for the LeNet-5 Basys-3 UART host."""

from __future__ import annotations

import queue
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

try:
    import serial
except ImportError:
    print("[ERROR] pyserial is required. Install via: pip install pyserial")
    sys.exit(1)

from uart_host import (
    DEFAULT_INPUT,
    DEFAULT_PARAM_DIR,
    InferenceResult,
    SerialPortInfo,
    gray_bytes_to_q16_pixels,
    list_serial_ports_detailed,
    load_all_weights,
    mnist_pixels_to_bytes,
    open_serial_port,
    pick_basys_serial_port,
    read_input_hex_file,
    read_mnist_sample,
    run_inference,
    set_burst_writes,
)


class UartHostApp:
    PREVIEW_SIZE = 280
    GRID = 28
    CELL = PREVIEW_SIZE // GRID
    PORT_POLL_MS = 2000

    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("LeNet-5 Basys-3 UART Host")
        self.root.minsize(820, 680)

        self.ui_queue: queue.Queue = queue.Queue()
        self.worker: threading.Thread | None = None
        self.serial_port: serial.Serial | None = None

        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="921600")
        self.param_dir_var = tk.StringVar(value=DEFAULT_PARAM_DIR)
        self.input_mode_var = tk.StringVar(value="draw")
        self.image_path_var = tk.StringVar(value=DEFAULT_INPUT)
        self.mnist_index_var = tk.StringVar(value="0")
        self.brush_var = tk.IntVar(value=2)
        self.eraser_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="Ready")
        self.result_var = tk.StringVar(value="—")
        self.expected_var = tk.StringVar(value="Draw a digit (0–9)")
        self.elapsed_var = tk.StringVar(value="")
        self.weights_status_var = tk.StringVar(value="Weights: not loaded this session")
        self.fast_mode_var = tk.BooleanVar(value=False)
        self.no_burst_var = tk.BooleanVar(value=False)

        self.draw_buffer = [0] * 784
        self.last_draw_cell: tuple[int, int] | None = None
        self.is_drawing = False
        self.port_infos: list[SerialPortInfo] = []

        self._build_ui()
        self.refresh_ports()
        self.on_input_mode_changed()
        self.render_canvas(self.draw_buffer)
        self.root.after(100, self._poll_ui_queue)
        self._schedule_port_poll()

    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=12)
        outer.pack(fill=tk.BOTH, expand=True)

        conn = ttk.LabelFrame(outer, text="Connection", padding=10)
        conn.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(conn, text="Port").grid(row=0, column=0, sticky=tk.W, padx=(0, 8))
        self.port_combo = ttk.Combobox(conn, textvariable=self.port_var, width=42, state="readonly")
        self.port_combo.grid(row=0, column=1, sticky=tk.W)

        ttk.Button(conn, text="Refresh", command=self.refresh_ports).grid(row=0, column=2, padx=8)
        ttk.Label(conn, text="Baud").grid(row=0, column=3, sticky=tk.W, padx=(8, 8))
        ttk.Entry(conn, textvariable=self.baud_var, width=10).grid(row=0, column=4, sticky=tk.W)

        self.connect_btn = ttk.Button(conn, text="Connect", command=self.toggle_connection)
        self.connect_btn.grid(row=0, column=5, padx=(16, 0))

        data = ttk.LabelFrame(outer, text="Data", padding=10)
        data.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(data, text="Parameter dir").grid(row=0, column=0, sticky=tk.W, padx=(0, 8))
        ttk.Entry(data, textvariable=self.param_dir_var).grid(row=0, column=1, sticky=tk.EW)
        ttk.Button(data, text="Browse", command=self.browse_param_dir).grid(row=0, column=2, padx=8)

        ttk.Label(data, text="Input source").grid(row=1, column=0, sticky=tk.W, pady=(8, 0))
        source_frame = ttk.Frame(data)
        source_frame.grid(row=1, column=1, columnspan=2, sticky=tk.W, pady=(8, 0))

        ttk.Radiobutton(
            source_frame,
            text="Draw",
            value="draw",
            variable=self.input_mode_var,
            command=self.on_input_mode_changed,
        ).pack(side=tk.LEFT)
        ttk.Radiobutton(
            source_frame,
            text="MNIST test index",
            value="mnist",
            variable=self.input_mode_var,
            command=self.on_input_mode_changed,
        ).pack(side=tk.LEFT, padx=(12, 0))
        ttk.Radiobutton(
            source_frame,
            text="Image file",
            value="file",
            variable=self.input_mode_var,
            command=self.on_input_mode_changed,
        ).pack(side=tk.LEFT, padx=(12, 0))

        self.draw_frame = ttk.Frame(data)
        self.draw_frame.grid(row=2, column=0, columnspan=3, sticky=tk.EW, pady=(8, 0))
        ttk.Button(self.draw_frame, text="Clear canvas", command=self.clear_draw_canvas).pack(side=tk.LEFT)
        ttk.Label(self.draw_frame, text="Brush").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Scale(
            self.draw_frame,
            from_=1,
            to=5,
            orient=tk.HORIZONTAL,
            variable=self.brush_var,
            length=100,
        ).pack(side=tk.LEFT)
        ttk.Checkbutton(self.draw_frame, text="Eraser", variable=self.eraser_var).pack(side=tk.LEFT, padx=(12, 0))

        self.mnist_frame = ttk.Frame(data)
        self.mnist_frame.grid(row=3, column=0, columnspan=3, sticky=tk.EW, pady=(8, 0))
        ttk.Label(self.mnist_frame, text="Index").pack(side=tk.LEFT)
        ttk.Spinbox(
            self.mnist_frame,
            from_=0,
            to=9999,
            textvariable=self.mnist_index_var,
            width=8,
            command=self.load_preview,
        ).pack(side=tk.LEFT, padx=8)
        ttk.Button(self.mnist_frame, text="Load preview", command=self.load_preview).pack(side=tk.LEFT)

        self.file_frame = ttk.Frame(data)
        self.file_frame.grid(row=4, column=0, columnspan=3, sticky=tk.EW, pady=(8, 0))
        ttk.Entry(self.file_frame, textvariable=self.image_path_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(self.file_frame, text="Browse", command=self.browse_image).pack(side=tk.LEFT, padx=8)
        ttk.Button(self.file_frame, text="Load preview", command=self.load_preview).pack(side=tk.LEFT)

        data.columnconfigure(1, weight=1)

        body = ttk.Frame(outer)
        body.pack(fill=tk.BOTH, expand=True)

        self.preview_frame = ttk.LabelFrame(body, text="Draw Digit (28x28)", padding=10)
        self.preview_frame.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 10))

        self.preview_canvas = tk.Canvas(
            self.preview_frame,
            width=self.PREVIEW_SIZE,
            height=self.PREVIEW_SIZE,
            bg="#000000",
            highlightthickness=1,
            highlightbackground="#444444",
            cursor="pencil",
        )
        self.preview_canvas.pack()
        ttk.Label(self.preview_frame, textvariable=self.expected_var).pack(pady=(8, 0))

        right = ttk.Frame(body)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        result_frame = ttk.LabelFrame(right, text="Prediction", padding=16)
        result_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(result_frame, textvariable=self.result_var, font=("Segoe UI", 48, "bold")).pack()
        ttk.Label(result_frame, textvariable=self.elapsed_var).pack(pady=(4, 0))

        action_frame = ttk.Frame(right)
        action_frame.pack(fill=tk.X, pady=(0, 6))

        self.load_weights_btn = ttk.Button(
            action_frame,
            text="Load Weights",
            command=self.start_weight_load,
        )
        self.load_weights_btn.pack(side=tk.LEFT)

        self.run_btn = ttk.Button(action_frame, text="Run Inference", command=self.start_inference)
        self.run_btn.pack(side=tk.LEFT, padx=(8, 0))

        self.progress = ttk.Progressbar(action_frame, mode="determinate", maximum=100)
        self.progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=12)

        options_frame = ttk.Frame(right)
        options_frame.pack(fill=tk.X, pady=(0, 6))

        ttk.Checkbutton(
            options_frame,
            text="Fast mode — skip weight reload (~1–2 s per run)",
            variable=self.fast_mode_var,
        ).pack(anchor=tk.W)
        ttk.Checkbutton(
            options_frame,
            text="Disable burst writes (slower, use if predictions look wrong)",
            variable=self.no_burst_var,
            command=self._on_burst_option_changed,
        ).pack(anchor=tk.W, pady=(2, 0))
        ttk.Label(
            options_frame,
            text="Load weights once after power-on, then enable fast mode for draw/test loops.",
            wraplength=520,
        ).pack(anchor=tk.W, pady=(2, 0))
        ttk.Label(options_frame, textvariable=self.weights_status_var).pack(anchor=tk.W, pady=(4, 0))

        ttk.Label(right, textvariable=self.status_var).pack(anchor=tk.W, pady=(0, 6))

        log_frame = ttk.LabelFrame(right, text="Log", padding=8)
        log_frame.pack(fill=tk.BOTH, expand=True)

        self.log_text = tk.Text(log_frame, height=16, wrap=tk.WORD, state=tk.DISABLED)
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        scrollbar = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.configure(yscrollcommand=scrollbar.set)

        self.preview_canvas.bind("<ButtonPress-1>", self.on_draw_press)
        self.preview_canvas.bind("<B1-Motion>", self.on_draw_motion)
        self.preview_canvas.bind("<ButtonRelease-1>", self.on_draw_release)
        self.preview_canvas.bind("<Leave>", self.on_draw_release)

    def on_input_mode_changed(self) -> None:
        mode = self.input_mode_var.get()
        use_draw = mode == "draw"
        use_mnist = mode == "mnist"
        use_file = mode == "file"

        for child in self.draw_frame.winfo_children():
            child.configure(state=tk.NORMAL if use_draw else tk.DISABLED)

        for child in self.mnist_frame.winfo_children():
            child.configure(state=tk.NORMAL if use_mnist else tk.DISABLED)

        for child in self.file_frame.winfo_children():
            child.configure(state=tk.DISABLED if not use_file else tk.NORMAL)

        if use_draw:
            self.preview_frame.configure(text="Draw Digit (28x28)")
            self.expected_var.set("Draw a digit (0–9), then Run Inference")
            self.preview_canvas.configure(cursor="pencil")
            self.render_canvas(self.draw_buffer)
        elif use_mnist:
            self.preview_frame.configure(text="28x28 Preview")
            self.preview_canvas.configure(cursor="arrow")
            self.load_preview()
        else:
            self.preview_frame.configure(text="28x28 Preview")
            self.preview_canvas.configure(cursor="arrow")
            self.load_preview()

    def _selected_port_device(self) -> str:
        selection = self.port_var.get().strip()
        if not selection:
            return ""

        if " — " in selection:
            return selection.split(" — ", 1)[0].strip()

        for info in self.port_infos:
            if selection == info.label:
                return info.device

        return selection

    def refresh_ports(self, silent: bool = False) -> None:
        previous = self._selected_port_device()
        self.port_infos = list_serial_ports_detailed()
        labels = [info.label for info in self.port_infos]
        self.port_combo["values"] = labels

        selected_info: SerialPortInfo | None = None
        devices = {info.device for info in self.port_infos}

        if previous and previous in devices:
            selected_info = next(info for info in self.port_infos if info.device == previous)
        elif self.port_infos:
            selected_info = pick_basys_serial_port(self.port_infos)

        if selected_info is not None:
            self.port_var.set(selected_info.label)
        else:
            self.port_var.set("")
            if not silent:
                self.append_log("[UI] No serial ports found. Connect Basys-3 USB, then click Refresh.")

    def _schedule_port_poll(self) -> None:
        self.root.after(self.PORT_POLL_MS, self._poll_ports)

    def _poll_ports(self) -> None:
        if not (self.serial_port and self.serial_port.is_open):
            self.refresh_ports(silent=True)
        self._schedule_port_poll()

    def browse_param_dir(self) -> None:
        path = filedialog.askdirectory(initialdir=self.param_dir_var.get())
        if path:
            self.param_dir_var.set(path)

    def browse_image(self) -> None:
        path = filedialog.askopenfilename(
            initialdir=DEFAULT_PARAM_DIR,
            filetypes=[("Hex text", "*.txt"), ("All files", "*.*")],
        )
        if path:
            self.image_path_var.set(path)
            self.load_preview()

    def append_log(self, message: str) -> None:
        self.log_text.configure(state=tk.NORMAL)
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.configure(state=tk.DISABLED)

    def set_busy(self, busy: bool) -> None:
        state = tk.DISABLED if busy else tk.NORMAL
        self.run_btn.configure(state=state)
        self.load_weights_btn.configure(state=state)
        self.connect_btn.configure(state=state)
        self.port_combo.configure(state="disabled" if busy else "readonly")
        canvas_state = tk.DISABLED if busy or self.input_mode_var.get() != "draw" else tk.NORMAL
        self.preview_canvas.configure(state=canvas_state)

    def _on_burst_option_changed(self) -> None:
        set_burst_writes(not self.no_burst_var.get())
        mode = "single-word" if self.no_burst_var.get() else "burst"
        self.append_log(f"[UI] UART writes: {mode} mode")

    def start_weight_load(self) -> None:
        if self.worker and self.worker.is_alive():
            return

        if not self.serial_port or not self.serial_port.is_open:
            messagebox.showerror("Not connected", "Connect to the Basys-3 UART port first.")
            return

        param_dir = self.param_dir_var.get().strip()
        if not param_dir:
            messagebox.showerror("Missing parameters", "Choose a parameter directory.")
            return

        self.set_busy(True)
        self.progress["value"] = 0
        self.status_var.set("Loading weights...")
        set_burst_writes(not self.no_burst_var.get())
        burst_note = "single-word" if self.no_burst_var.get() else "burst"
        self.append_log(f"[UI] Uploading weights/biases to FPGA ({burst_note} mode)...")

        ser = self.serial_port

        def worker() -> None:
            def on_log(message: str) -> None:
                self.ui_queue.put(("log", message))

            def on_progress(stage: str, fraction: float) -> None:
                self.ui_queue.put(("progress", stage, fraction))

            try:
                load_all_weights(ser, param_dir, on_log=on_log, on_progress=on_progress)
                self.ui_queue.put(("weights_done", True, ""))
            except Exception as exc:
                self.ui_queue.put(("weights_done", False, str(exc)))

        self.worker = threading.Thread(target=worker, daemon=True)
        self.worker.start()

    def toggle_connection(self) -> None:
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            self.serial_port = None
            self.connect_btn.configure(text="Connect")
            self.status_var.set("Disconnected")
            self.append_log("[UI] Serial port closed.")
            return

        port = self._selected_port_device()
        if not port:
            messagebox.showerror("No port", "Select a serial port first.")
            return

        try:
            baud = int(self.baud_var.get())
            self.serial_port = open_serial_port(port, baud, timeout=2.0)
        except (RuntimeError, ValueError) as exc:
            self.serial_port = None
            self.append_log(f"[UI] Connection failed on {port}: {exc}")
            messagebox.showerror("Connection failed", str(exc))
            return

        self.connect_btn.configure(text="Disconnect")
        self.status_var.set(f"Connected to {port}")
        self.append_log(f"[UI] Connected to {port} at {baud} baud.")

    def clear_draw_canvas(self) -> None:
        self.draw_buffer = [0] * 784
        self.render_canvas(self.draw_buffer)

    def event_to_cell(self, event: tk.Event) -> tuple[int, int]:
        col = min(self.GRID - 1, max(0, event.x // self.CELL))
        row = min(self.GRID - 1, max(0, event.y // self.CELL))
        return row, col

    def paint_brush(self, row: int, col: int) -> None:
        radius = max(0, int(self.brush_var.get()) - 1)
        erasing = self.eraser_var.get()

        for dr in range(-radius, radius + 1):
            for dc in range(-radius, radius + 1):
                if dr * dr + dc * dc > radius * radius + radius:
                    continue

                r = row + dr
                c = col + dc
                if 0 <= r < self.GRID and 0 <= c < self.GRID:
                    idx = (r * self.GRID) + c
                    if erasing:
                        self.draw_buffer[idx] = 0
                    else:
                        self.draw_buffer[idx] = 255

    def draw_line(self, start: tuple[int, int], end: tuple[int, int]) -> None:
        r0, c0 = start
        r1, c1 = end
        steps = max(abs(r1 - r0), abs(c1 - c0), 1)

        for step in range(steps + 1):
            t = step / steps
            row = int(round(r0 + ((r1 - r0) * t)))
            col = int(round(c0 + ((c1 - c0) * t)))
            self.paint_brush(row, col)

    def on_draw_press(self, event: tk.Event) -> None:
        if self.input_mode_var.get() != "draw":
            return

        self.is_drawing = True
        cell = self.event_to_cell(event)
        self.last_draw_cell = cell
        self.paint_brush(*cell)
        self.render_canvas(self.draw_buffer)

    def on_draw_motion(self, event: tk.Event) -> None:
        if not self.is_drawing or self.input_mode_var.get() != "draw":
            return

        cell = self.event_to_cell(event)
        if self.last_draw_cell is not None and cell != self.last_draw_cell:
            self.draw_line(self.last_draw_cell, cell)
        else:
            self.paint_brush(*cell)

        self.last_draw_cell = cell
        self.render_canvas(self.draw_buffer)

    def on_draw_release(self, _event: tk.Event | None = None) -> None:
        self.is_drawing = False
        self.last_draw_cell = None

    def render_canvas(self, gray_values: list[int]) -> None:
        self.preview_canvas.delete("all")
        for row in range(self.GRID):
            for col in range(self.GRID):
                value = gray_values[(row * self.GRID) + col]
                color = f"#{value:02x}{value:02x}{value:02x}"
                x0 = col * self.CELL
                y0 = row * self.CELL
                self.preview_canvas.create_rectangle(
                    x0,
                    y0,
                    x0 + self.CELL,
                    y0 + self.CELL,
                    fill=color,
                    outline="#222222",
                )

    def _get_preview_pixels(self) -> tuple[list[int], str]:
        if self.input_mode_var.get() == "mnist":
            index = int(self.mnist_index_var.get())
            pixels, expected = read_mnist_sample(index)
            label_text = f"Expected: {expected}" if expected is not None else "Expected: —"
            return pixels, label_text

        pixels = read_input_hex_file(self.image_path_var.get())
        return pixels, "Expected: —"

    def load_preview(self) -> None:
        if self.input_mode_var.get() == "draw":
            self.render_canvas(self.draw_buffer)
            return

        try:
            pixels, label_text = self._get_preview_pixels()
        except Exception as exc:
            self.expected_var.set("Expected: —")
            self.append_log(f"[UI] Preview load failed: {exc}")
            return

        self.expected_var.set(label_text)
        self.render_canvas(mnist_pixels_to_bytes(pixels))

    def _resolve_inference_input(self) -> tuple[str, list[int] | None, int | None]:
        mode = self.input_mode_var.get()

        if mode == "draw":
            if not any(self.draw_buffer):
                raise ValueError("Draw a digit on the canvas first.")
            return "drawn_digit", gray_bytes_to_q16_pixels(self.draw_buffer), None

        if mode == "mnist":
            index = int(self.mnist_index_var.get())
            input_pixels, expected_label = read_mnist_sample(index)
            return f"mnist_test[{index}]", input_pixels, expected_label

        image_path = self.image_path_var.get().strip()
        if not image_path:
            raise ValueError("Choose an input image file.")
        return image_path, None, None

    def start_inference(self) -> None:
        if self.worker and self.worker.is_alive():
            return

        if not self.serial_port or not self.serial_port.is_open:
            messagebox.showerror("Not connected", "Connect to the Basys-3 UART port first.")
            return

        param_dir = self.param_dir_var.get().strip()
        if not param_dir:
            messagebox.showerror("Missing parameters", "Choose a parameter directory.")
            return

        try:
            image_path, input_pixels, expected_label = self._resolve_inference_input()
        except Exception as exc:
            messagebox.showerror("Invalid input", str(exc))
            return

        reload_weights = not self.fast_mode_var.get()
        if not reload_weights and "not loaded" in self.weights_status_var.get():
            if not messagebox.askyesno(
                "Weights not loaded",
                "Fast mode is on but weights have not been loaded this session.\n\n"
                "Continue anyway (only if weights are already in FPGA memory)?",
            ):
                return

        self.set_busy(True)
        self.progress["value"] = 0
        self.status_var.set("Running...")
        self.result_var.set("…")
        self.elapsed_var.set("")
        set_burst_writes(not self.no_burst_var.get())
        if reload_weights:
            self.append_log("[UI] Starting full inference workflow (includes weight upload)...")
        else:
            self.append_log("[UI] Starting fast inference (input image only)...")

        ser = self.serial_port

        def worker() -> None:
            def on_log(message: str) -> None:
                self.ui_queue.put(("log", message))

            def on_progress(stage: str, fraction: float) -> None:
                self.ui_queue.put(("progress", stage, fraction))

            result = run_inference(
                ser,
                image_path=image_path,
                param_dir=param_dir,
                on_log=on_log,
                on_progress=on_progress,
                input_pixels=input_pixels,
                expected_label=expected_label,
                reload_weights=reload_weights,
            )
            self.ui_queue.put(("done", result))

        self.worker = threading.Thread(target=worker, daemon=True)
        self.worker.start()

    def _poll_ui_queue(self) -> None:
        try:
            while True:
                item = self.ui_queue.get_nowait()
                kind = item[0]

                if kind == "log":
                    self.append_log(item[1])
                elif kind == "progress":
                    _, stage, fraction = item
                    self.status_var.set(stage)
                    self.progress["value"] = max(0.0, min(100.0, fraction * 100.0))
                elif kind == "done":
                    result: InferenceResult = item[1]
                    self.set_busy(False)
                    if result.success:
                        self.result_var.set(str(result.prediction))
                        self.elapsed_var.set(f"{result.elapsed_s:.2f} s")
                        self.status_var.set("Inference complete")
                    else:
                        self.result_var.set("—")
                        self.elapsed_var.set("")
                        self.status_var.set("Failed")
                        messagebox.showerror("Inference failed", result.message)
                elif kind == "weights_done":
                    _, success, message = item
                    self.set_busy(False)
                    if success:
                        self.weights_status_var.set("Weights: loaded on FPGA (safe until power-off)")
                        self.fast_mode_var.set(True)
                        self.status_var.set("Weights loaded")
                        self.progress["value"] = 100
                        self.append_log("[UI] Weights loaded. Fast mode enabled for subsequent runs.")
                    else:
                        self.status_var.set("Weight load failed")
                        messagebox.showerror("Weight load failed", message)
        except queue.Empty:
            pass

        self.root.after(100, self._poll_ui_queue)


def main() -> None:
    root = tk.Tk()
    try:
        style = ttk.Style()
        if "vista" in style.theme_names():
            style.theme_use("vista")
    except tk.TclError:
        pass

    UartHostApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
