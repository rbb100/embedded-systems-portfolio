"""
hil_uart_bridge.py
------------------
PC-side HIL bridge — makes the virtual RO-PUF speak the same
UART protocol as the real Zybo Z7, over a TCP socket.

Run this on your PC. The Pi verifier (pi_verifier.py) connects
to it as if it were talking to real hardware.

Architecture:
    [Pi / pi_verifier.py]  ←─── TCP socket ───→  [hil_uart_bridge.py]
                                                          │
                                                   [VirtualROPUF]

Usage:
    # Terminal 1 (PC) — start the bridge:
    python3 hil_uart_bridge.py

    # Terminal 2 (Pi or same PC) — run verifier:
    python3 pi_verifier.py --hil

    # With Trojan mode enabled:
    python3 hil_uart_bridge.py --trojan

    # Custom noise level:
    python3 hil_uart_bridge.py --noise 0.2
"""

import argparse
import socket
import sys
import threading
from virtual_puf import VirtualROPUF, PUFConfig


BANNER = """
╔══════════════════════════════════════════════════════╗
║   HIL UART Bridge — Virtual PUF Socket Server       ║
║   Rutgers Hardware & System Security                ║
╚══════════════════════════════════════════════════════╝
"""

# ─── Protocol Handler ────────────────────────────────────────────────────────

class ProverBridge:
    """
    Handles one client connection (one Pi verifier session).
    Implements the same command protocol the Zybo RTL will use.

    Commands received:
        PING          → READY
        ENROLL        → READY  (resets session)
        AUTH          → READY  (begins auth queries)
        CHAL:<n>      → RESP:<bit>
        TROJAN:ON     → ACK
        TROJAN:OFF    → ACK
    """

    def __init__(self, conn: socket.socket, addr, puf: VirtualROPUF):
        self.conn = conn
        self.addr = addr
        self.puf = puf
        self.fh = conn.makefile("rw", buffering=1)

    def send(self, msg: str):
        self.fh.write(msg.strip() + "\n")
        self.fh.flush()

    def recv(self) -> str:
        return self.fh.readline().strip()

    def run(self):
        print(f"  [Bridge] Client connected: {self.addr}")
        try:
            while True:
                line = self.recv()
                if not line:
                    break

                if line == "PING":
                    self.send("READY")

                elif line == "ENROLL":
                    print(f"  [Bridge] Enrollment session started")
                    self.send("READY")

                elif line == "AUTH":
                    print(f"  [Bridge] Authentication session started")
                    self.send("READY")

                elif line.startswith("CHAL:"):
                    try:
                        challenge = int(line.split(":")[1])
                        bit = self.puf.get_response_bit(challenge)
                        self.send(f"RESP:{bit}")
                    except (ValueError, IndexError):
                        self.send("ERR:bad_challenge")

                elif line == "TROJAN:ON":
                    self.puf.enable_trojan()
                    print(f"  [Bridge] ⚠️  Trojan mode ENABLED")
                    self.send("ACK")

                elif line == "TROJAN:OFF":
                    self.puf.disable_trojan()
                    print(f"  [Bridge] Trojan mode disabled")
                    self.send("ACK")

                else:
                    print(f"  [Bridge] Unknown command: {line}")
                    self.send(f"ERR:unknown_command:{line}")

        except (ConnectionResetError, BrokenPipeError):
            pass
        finally:
            print(f"  [Bridge] Client disconnected: {self.addr}")
            self.conn.close()


# ─── Server ──────────────────────────────────────────────────────────────────

def run_server(host: str, port: int, puf: VirtualROPUF):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(5)
    print(f"  [Bridge] Listening on {host}:{port}")
    print(f"  [Bridge] Trojan mode: {'ON ⚠️' if puf.trojan_active else 'OFF'}")
    print(f"  [Bridge] Noise level: {puf.cfg.noise_std_pct}%")
    print(f"  [Bridge] Challenges:  {puf.cfg.n_challenges}")
    print(f"\n  Waiting for Pi verifier to connect... (Ctrl+C to stop)\n")

    try:
        while True:
            conn, addr = server.accept()
            bridge = ProverBridge(conn, addr, puf)
            thread = threading.Thread(target=bridge.run, daemon=True)
            thread.start()
    except KeyboardInterrupt:
        print("\n  [Bridge] Shutting down.")
    finally:
        server.close()


# ─── Entry Point ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="HIL UART Bridge")
    parser.add_argument("--host",       type=str,   default="0.0.0.0")
    parser.add_argument("--port",       type=int,   default=9999)
    parser.add_argument("--noise",      type=float, default=0.1,
                        help="Noise std dev as %% of base freq (default: 0.1)")
    parser.add_argument("--trojan",     action="store_true",
                        help="Start with Trojan mode enabled")
    parser.add_argument("--challenges", type=int,   default=64)
    parser.add_argument("--seed",       type=int,   default=42)
    args = parser.parse_args()

    print(BANNER)

    cfg = PUFConfig(
        n_challenges=args.challenges,
        noise_std_pct=args.noise,
        random_seed=args.seed,
    )
    puf = VirtualROPUF(cfg)
    if args.trojan:
        puf.enable_trojan()

    run_server(args.host, args.port, puf)


if __name__ == "__main__":
    main()
