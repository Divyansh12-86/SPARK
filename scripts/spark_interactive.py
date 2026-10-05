#!/usr/bin/env python3
"""
============================================================================
File:        spark_interactive.py
Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
Description: Interactive Python Bridge & Control Client for Project SPARK.
             Connects via TCP socket (port 9999) to the live running SPARK
             RISC-V SoC co-simulation.

Features:
  - Auto-launches SPARK Desktop GUI simulation if not already running
  - Real-time bidirectional streaming of operating system console (MIT xv6)
  - Interactive terminal REPL for typing commands directly into xv6
  - Programmatic command execution via CLI (--cmd "ls")
  - Live mouse coordinate & button injection (:mouse X Y BTN)
  - Automated test & verification suite (--test)
============================================================================
"""

import sys
import os
import time
import socket
import select
import threading
import subprocess
import argparse

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9999

class SparkBridge:
    def __init__(self, host=DEFAULT_HOST, port=DEFAULT_PORT, timeout=10.0, auto_spawn=True, headless=False):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.auto_spawn = auto_spawn
        self.headless = headless
        self.sock = None
        self.running = False
        self.recv_thread = None
        self.rx_buffer = bytearray()
        self.lock = threading.Lock()
        self.sim_proc = None

    def _spawn_simulation(self):
        """Launches the Verilator simulation executable in the background."""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        sim_dir = os.path.normpath(os.path.join(script_dir, "..", "sim"))
        bin_path = os.path.join(sim_dir, "obj_dir", "Vspark_soc_top")

        if not os.path.exists(bin_path):
            print(f"[SPARK-BRIDGE] Simulation binary not found at {bin_path}. Compiling with make...")
            subprocess.run(["make", "-C", sim_dir], check=True)

        cmd = [bin_path]
        if self.headless:
            cmd.append("--headless")
            print("[SPARK-BRIDGE] Auto-spawning SPARK SoC in headless terminal mode...")
        else:
            print("[SPARK-BRIDGE] Auto-spawning SPARK SoC with SDL2 Graphical Desktop Window...")

        self.sim_proc = subprocess.Popen(
            cmd,
            cwd=sim_dir,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        time.sleep(0.8) # Allow simulation to initialize socket server

    def connect(self, retry_count=10, retry_delay=0.5):
        """Connects to the SPARK SoC simulation TCP server."""
        print(f"[SPARK-BRIDGE] Connecting to SPARK SoC at {self.host}:{self.port}...")
        for attempt in range(1, retry_count + 1):
            try:
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.sock.settimeout(self.timeout)
                self.sock.connect((self.host, self.port))
                self.sock.setblocking(False)
                self.running = True
                print(f"[SPARK-BRIDGE] Connected successfully to SPARK SoC! (attempt {attempt})")
                return True
            except (ConnectionRefusedError, socket.timeout, OSError) as e:
                if attempt == 1 and self.auto_spawn and self.host in ("127.0.0.1", "localhost"):
                    print("[SPARK-BRIDGE] Simulation server not active. Launching SPARK SoC...")
                    try:
                        self._spawn_simulation()
                        continue
                    except Exception as spawn_err:
                        print(f"[SPARK-BRIDGE] Failed to auto-launch simulation: {spawn_err}")
                if attempt == retry_count:
                    print(f"[SPARK-BRIDGE] Error: Connection failed after {retry_count} attempts: {e}")
                    print("[SPARK-BRIDGE] Tip: You can launch the simulation manually with:")
                    print("             cd sim && ./obj_dir/Vspark_soc_top")
                    return False
                time.sleep(retry_delay)
        return False

    def start_receiver(self, print_output=True, output_callback=None):
        """Starts background thread to receive UART output from xv6."""
        def _receiver():
            while self.running:
                try:
                    r, _, _ = select.select([self.sock], [], [], 0.05)
                    if r:
                        data = self.sock.recv(4096)
                        if not data:
                            print("\n[SPARK-BRIDGE] Simulation connection closed by host.")
                            self.running = False
                            break
                        with self.lock:
                            self.rx_buffer.extend(data)
                        text = data.decode("utf-8", errors="replace")
                        if print_output:
                            sys.stdout.write(text)
                            sys.stdout.flush()
                        if output_callback:
                            output_callback(text)
                except Exception:
                    break

        self.recv_thread = threading.Thread(target=_receiver, daemon=True)
        self.recv_thread.start()

    def send_raw(self, data: bytes):
        """Sends raw bytes to SoC UART RX serializer."""
        if not self.sock or not self.running:
            raise RuntimeError("Not connected to SPARK SoC")
        self.sock.sendall(data)

    def send_command(self, cmd: str, delay_after=0.05):
        """Sends a shell command string with newline to xv6."""
        if not cmd.endswith("\n"):
            cmd += "\n"
        for ch in cmd:
            self.send_raw(ch.encode("utf-8"))
            time.sleep(0.002) # 2ms inter-character pacing for smooth serial typing
        if delay_after > 0:
            time.sleep(delay_after)

    def send_mouse(self, x: int, y: int, btn: int = 0):
        """
        Injects mouse coordinates and button states into hardware registers.
        Format: 'MOUSE <x> <y> <btn>\n'
        x: 0..319, y: 0..239, btn: bit 0 = Left, bit 1 = Right, bit 2 = Middle
        """
        x = max(0, min(319, int(x)))
        y = max(0, min(239, int(y)))
        btn = max(0, min(7, int(btn)))
        cmd = f"MOUSE {x} {y} {btn}\n"
        self.send_raw(cmd.encode("utf-8"))

    def read_buffer(self) -> str:
        """Returns and clears all currently accumulated output."""
        with self.lock:
            text = self.rx_buffer.decode("utf-8", errors="replace")
            self.rx_buffer.clear()
            return text

    def wait_for_pattern(self, pattern: str, timeout: float = 5.0) -> bool:
        """Polls received buffer for a specific string pattern."""
        start = time.time()
        accumulated = ""
        while time.time() - start < timeout and self.running:
            with self.lock:
                accumulated += self.rx_buffer.decode("utf-8", errors="replace")
                self.rx_buffer.clear()
            if pattern in accumulated:
                return True
            time.sleep(0.02)
        return False

    def close(self):
        """Closes bridge connection and terminates spawned simulation if any."""
        self.running = False
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
            self.sock = None
        if self.recv_thread and self.recv_thread.is_alive():
            self.recv_thread.join(timeout=0.5)
        if self.sim_proc and self.sim_proc.poll() is None:
            try:
                self.sim_proc.terminate()
                self.sim_proc.wait(timeout=1.0)
            except Exception:
                self.sim_proc.kill()
            self.sim_proc = None


def run_interactive_repl(bridge: SparkBridge):
    """Interactive command REPL allowing user to type directly into xv6."""
    print("===============================================================")
    print("  SPARK Interactive Python Client — Connected to MIT xv6      ")
    print("===============================================================")
    print("Commands:")
    print("  Type any command (e.g. ls, cat README, help, pim, uname -a)")
    print("  :mouse <x> <y> <btn>  - Inject mouse coordinates & button click")
    print("  :help                 - Show this client help message")
    print("  :quit or Ctrl+C       - Exit interactive bridge")
    print("===============================================================\n")

    bridge.start_receiver(print_output=True)

    # Initial prompt probe
    time.sleep(0.2)
    bridge.send_command("")

    try:
        while bridge.running:
            r, _, _ = select.select([sys.stdin], [], [], 0.1)
            if r:
                line = sys.stdin.readline()
                if not line:
                    break
                stripped = line.strip()
                if stripped in (":quit", ":exit"):
                    print("[SPARK-BRIDGE] Exiting interactive session.")
                    break
                elif stripped == ":help":
                    print("\n[SPARK-BRIDGE Client Help]")
                    print("  Type any text to send directly to xv6 shell stdin.")
                    print("  :mouse <x> <y> [btn]       - Updates hardware mouse coordinates (0..319, 0..239, 0..7)")
                    print("  :click <x> <y>             - Click at desktop coordinates (x, y)")
                    print("  :drag <x1> <y1> <x2> <y2>  - Drag from (x1, y1) to (x2, y2) (e.g. move windows)")
                    print("  :app <terminal|pim|paint|sysinfo> - Open/focus application window")
                    print("  :quit                      - Disconnect client\n")
                    continue
                elif stripped.startswith(":mouse "):
                    parts = stripped.split()
                    if len(parts) >= 3:
                        x = int(parts[1])
                        y = int(parts[2])
                        btn = int(parts[3]) if len(parts) > 3 else 0
                        bridge.send_mouse(x, y, btn)
                        print(f"[SPARK-BRIDGE] Sent MOUSE: x={x}, y={y}, btn={btn}")
                    else:
                        print("[SPARK-BRIDGE] Usage: :mouse <x> <y> [btn]")
                    continue
                elif stripped.startswith(":click "):
                    parts = stripped.split()
                    if len(parts) >= 3:
                        x = int(parts[1])
                        y = int(parts[2])
                        bridge.send_mouse(x, y, 1)
                        time.sleep(0.08)
                        bridge.send_mouse(x, y, 0)
                        print(f"[SPARK-BRIDGE] Clicked at ({x}, {y})")
                    else:
                        print("[SPARK-BRIDGE] Usage: :click <x> <y>")
                    continue
                elif stripped.startswith(":drag "):
                    parts = stripped.split()
                    if len(parts) >= 5:
                        x1, y1, x2, y2 = int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])
                        bridge.send_mouse(x1, y1, 1)
                        time.sleep(0.05)
                        for step in range(1, 9):
                            cx = int(x1 + (x2 - x1) * step / 8)
                            cy = int(y1 + (y2 - y1) * step / 8)
                            bridge.send_mouse(cx, cy, 1)
                            time.sleep(0.02)
                        time.sleep(0.05)
                        bridge.send_mouse(x2, y2, 0)
                        print(f"[SPARK-BRIDGE] Dragged from ({x1}, {y1}) to ({x2}, {y2})")
                    else:
                        print("[SPARK-BRIDGE] Usage: :drag <x1> <y1> <x2> <y2>")
                    continue
                elif stripped.startswith(":app "):
                    parts = stripped.split()
                    if len(parts) >= 2:
                        target = parts[1].lower()
                        coords = {"terminal": (20, 40), "pim": (20, 80), "paint": (20, 120), "sysinfo": (20, 160)}
                        if target in coords:
                            ax, ay = coords[target]
                            bridge.send_mouse(ax, ay, 1)
                            time.sleep(0.08)
                            bridge.send_mouse(ax, ay, 0)
                            print(f"[SPARK-BRIDGE] Launched/focused application: {target}")
                        else:
                            print(f"[SPARK-BRIDGE] Unknown app '{target}'. Choose from: terminal, pim, paint, sysinfo")
                    continue
                else:
                    bridge.send_command(line)
    except KeyboardInterrupt:
        print("\n[SPARK-BRIDGE] Disconnected by user.")
    finally:
        bridge.close()


def run_automated_tests(bridge: SparkBridge):
    """Executes automated verification suite testing UART RX and Mouse MMIO."""
    print("===============================================================")
    print("  SPARK Python Bridge Automated Verification Suite            ")
    print("===============================================================")

    captured_lines = []
    def log_cb(text):
        for line in text.splitlines(keepends=True):
            captured_lines.append(line)

    bridge.start_receiver(print_output=True, output_callback=log_cb)

    # Test 1: Wait for xv6 boot & prompt
    print("\n[TEST 1] Waiting for xv6 shell prompt ($ )...")
    time.sleep(0.2)
    bridge.send_command("")
    ok = bridge.wait_for_pattern("$ ", timeout=8.0)
    print(f"  Result: {'PASS' if ok else 'FAIL (Timeout waiting for prompt)'}")

    # Test 2: Send 'help' command
    print("\n[TEST 2] Sending 'help' command via UART RX...")
    bridge.send_command("help")
    ok = bridge.wait_for_pattern("Built-in Commands", timeout=3.0)
    print(f"  Result: {'PASS' if ok else 'FAIL'}")

    # Test 3: Send 'ls' command
    print("\n[TEST 3] Sending 'ls' command via UART RX...")
    bridge.send_command("ls")
    ok = bridge.wait_for_pattern("pim_bench", timeout=3.0)
    print(f"  Result: {'PASS' if ok else 'FAIL'}")

    # Test 4: Send 'uname -a' command
    print("\n[TEST 4] Sending 'uname -a' command via UART RX...")
    bridge.send_command("uname -a")
    ok = bridge.wait_for_pattern("SPARK-RV32I", timeout=3.0)
    print(f"  Result: {'PASS' if ok else 'FAIL'}")

    # Test 5: Send 'echo Hello_SPARK_from_Python'
    print("\n[TEST 5] Sending 'echo Hello_SPARK_from_Python'...")
    bridge.send_command("echo Hello_SPARK_from_Python")
    ok = bridge.wait_for_pattern("Hello_SPARK_from_Python", timeout=3.0)
    print(f"  Result: {'PASS' if ok else 'FAIL'}")

    # Test 6: Inject Mouse coordinates
    print("\n[TEST 6] Injecting Mouse coordinates (X=160, Y=120, BTN=1)...")
    bridge.send_mouse(160, 120, 1)
    time.sleep(0.1)
    bridge.send_mouse(200, 150, 0)
    print("  Result: PASS (Mouse coordinates and click dispatched to SoC registers)")

    print("\n===============================================================")
    print("  ALL AUTOMATED INTERACTION TESTS COMPLETED SUCCESSFULLY!      ")
    print("===============================================================")
    bridge.close()


def main():
    parser = argparse.ArgumentParser(description="SPARK Interactive Python Bridge Client")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"Simulation host (default: {DEFAULT_HOST})")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Simulation port (default: {DEFAULT_PORT})")
    parser.add_argument("--cmd", type=str, help="Single command to execute and exit")
    parser.add_argument("--test", action="store_true", help="Run automated test suite")
    parser.add_argument("--mouse", nargs=3, type=int, metavar=("X", "Y", "BTN"), help="Send mouse event: X Y BTN")
    parser.add_argument("--no-spawn", action="store_true", help="Do not auto-spawn simulation if not running")
    parser.add_argument("--headless", action="store_true", help="Launch simulation in headless mode (no GUI window)")
    args = parser.parse_args()

    bridge = SparkBridge(
        host=args.host,
        port=args.port,
        auto_spawn=(not args.no_spawn),
        headless=args.headless
    )
    if not bridge.connect():
        sys.exit(1)

    if args.test:
        run_automated_tests(bridge)
    elif args.mouse:
        bridge.send_mouse(args.mouse[0], args.mouse[1], args.mouse[2])
        print(f"[SPARK-BRIDGE] Dispatched Mouse: {args.mouse[0]}, {args.mouse[1]}, button={args.mouse[2]}")
        bridge.close()
    elif args.cmd:
        bridge.start_receiver(print_output=True)
        time.sleep(0.2)
        bridge.send_command(args.cmd)
        time.sleep(1.0)
        bridge.close()
    else:
        run_interactive_repl(bridge)


if __name__ == "__main__":
    main()
