"""
pi_verifier.py
--------------
Raspberry Pi 4 Verifier script for PUF-Based Edge Device Attestation.

Auto-detects connection mode:
  - HIL mode  : Connects to PC-hosted virtual PUF over UART (or TCP socket fallback)
  - Hardware  : Connects to real Zybo Z7 FPGA over UART

Protocol (UART message format):
  Host → Prover : "CHAL:<index>\\n"
  Prover → Host : "RESP:<bit>\\n"
  Host → Prover : "ENROLL\\n"      (start enrollment session)
  Host → Prover : "AUTH\\n"        (start authentication session)
  Prover → Host : "READY\\n"       (prover is online and ready)
  Prover → Host : "ERR:<msg>\\n"   (error from prover)

Usage:
    # On Raspberry Pi (or PC in HIL mode):
    python3 pi_verifier.py                        # auto-detect port + mode
    python3 pi_verifier.py --port /dev/ttyUSB0    # force port
    python3 pi_verifier.py --hil                  # force HIL socket mode
    python3 pi_verifier.py --challenges 64 --vote 9

Dependencies:
    pip install pyserial
"""

import argparse
import csv
import glob
import json
import os
import socket
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Optional

try:
    import serial
    import serial.tools.list_ports
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False
    print("[Warning] pyserial not installed. UART mode unavailable. Install with: pip install pyserial")


# ─── Configuration ───────────────────────────────────────────────────────────

@dataclass
class VerifierConfig:
    n_challenges: int = 64
    majority_vote_n: int = 9
    auth_threshold: float = 0.90
    baud_rate: int = 115200
    timeout_s: float = 5.0
    hil_host: str = "localhost"
    hil_port: int = 9999
    output_dir: str = "./verifier_output"


# ─── UART / Socket Communication Layer ───────────────────────────────────────

class UARTComm:
    """Handles serial UART communication with the Prover (Zybo or HIL bridge)."""

    def __init__(self, port: str, baud: int = 115200, timeout: float = 5.0):
        if not SERIAL_AVAILABLE:
            raise RuntimeError("pyserial not installed. Run: pip install pyserial")
        self.port = port
        self.ser = serial.Serial(port, baudrate=baud, timeout=timeout)
        time.sleep(0.5)  # Let port settle
        self.ser.reset_input_buffer()
        print(f"[UART] Connected to {port} @ {baud} baud")

    def send(self, msg: str):
        self.ser.write((msg.strip() + "\n").encode("utf-8"))

    def recv(self) -> str:
        line = self.ser.readline().decode("utf-8", errors="replace").strip()
        return line

    def close(self):
        if self.ser.is_open:
            self.ser.close()


class SocketComm:
    """
    TCP socket fallback for HIL mode.
    Connects to a PC running hil_uart_bridge.py which wraps the virtual PUF.
    """

    def __init__(self, host: str = "localhost", port: int = 9999, timeout: float = 5.0):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect((host, port))
        self.fh = self.sock.makefile("rw", buffering=1)
        print(f"[Socket] Connected to HIL bridge at {host}:{port}")

    def send(self, msg: str):
        self.fh.write(msg.strip() + "\n")
        self.fh.flush()

    def recv(self) -> str:
        return self.fh.readline().strip()

    def close(self):
        self.sock.close()


# ─── Port Auto-Detection ─────────────────────────────────────────────────────

ZYBO_USB_IDS = [
    ("0403", "6010"),  # FTDI FT2232H (Digilent JTAG/UART)
    ("0403", "6001"),  # FTDI FT232R
    ("04b4", "0008"),  # Cypress USB-UART (some Digilent boards)
]

def detect_uart_port() -> Optional[str]:
    """
    Tries to find the Zybo UART port by USB VID/PID.
    Falls back to scanning common port patterns.
    """
    if not SERIAL_AVAILABLE:
        return None

    ports = list(serial.tools.list_ports.comports())

    # 1. Match known Zybo/Digilent USB-UART VID:PID
    for port in ports:
        vid = f"{port.vid:04x}" if port.vid else ""
        pid = f"{port.pid:04x}" if port.pid else ""
        if (vid, pid) in ZYBO_USB_IDS:
            print(f"[AutoDetect] Found Zybo-compatible device: {port.device} ({port.description})")
            return port.device

    # 2. Fallback: pick first ttyUSB or ttyACM
    for port in ports:
        if "ttyUSB" in port.device or "ttyACM" in port.device:
            print(f"[AutoDetect] Using first available USB-serial: {port.device}")
            return port.device

    # 3. macOS fallback
    mac_ports = glob.glob("/dev/tty.usbserial-*") + glob.glob("/dev/tty.usbmodem*")
    if mac_ports:
        print(f"[AutoDetect] macOS port: {mac_ports[0]}")
        return mac_ports[0]

    return None


def detect_mode(cfg: VerifierConfig) -> tuple[str, object]:
    """
    Returns ("uart", comm) or ("socket", comm) depending on what's available.
    Priority: UART (real hardware) > Socket (HIL bridge)
    """
    # Try UART first
    port = detect_uart_port()
    if port:
        try:
            comm = UARTComm(port, cfg.baud_rate, cfg.timeout_s)
            comm.send("PING")
            resp = comm.recv()
            if resp == "READY":
                print("[AutoDetect] Mode: HARDWARE (Zybo UART)")
                return "uart", comm
            comm.close()
        except Exception as e:
            print(f"[AutoDetect] UART found but handshake failed: {e}")

    # Try HIL socket bridge
    try:
        comm = SocketComm(cfg.hil_host, cfg.hil_port, cfg.timeout_s)
        comm.send("PING")
        resp = comm.recv()
        if resp == "READY":
            print("[AutoDetect] Mode: HIL (virtual PUF socket bridge)")
            return "socket", comm
        comm.close()
    except Exception as e:
        print(f"[AutoDetect] HIL socket not available: {e}")

    raise RuntimeError(
        "No Prover found.\n"
        "  - For hardware: connect Zybo via USB and check drivers\n"
        "  - For HIL: run hil_uart_bridge.py on your PC first"
    )


# ─── Verifier Logic ───────────────────────────────────────────────────────────

@dataclass
class CRPStore:
    challenges: list[int] = field(default_factory=list)
    golden_responses: list[int] = field(default_factory=list)
    enrolled_at: str = ""

    def save(self, path: Path):
        with open(path, "w") as f:
            json.dump({
                "challenges": self.challenges,
                "golden_responses": self.golden_responses,
                "enrolled_at": self.enrolled_at,
            }, f, indent=2)
        print(f"[CRPStore] Saved to {path}")

    @classmethod
    def load(cls, path: Path) -> "CRPStore":
        with open(path) as f:
            data = json.load(f)
        store = cls(**data)
        print(f"[CRPStore] Loaded {len(store.challenges)} CRPs from {path}")
        return store


class PiVerifier:
    """
    Raspberry Pi verifier — runs enrollment and authentication
    over UART (or socket in HIL mode).
    """

    def __init__(self, comm, cfg: VerifierConfig):
        self.comm = comm
        self.cfg = cfg
        self.crp_store: Optional[CRPStore] = None
        self.logger = DataLogger(cfg.output_dir)

    # ── Low-level challenge ───────────────────────────────────────────────────
    def _query_challenge(self, challenge: int) -> int:
        """Send a challenge, collect majority-voted response."""
        votes = []
        for _ in range(self.cfg.majority_vote_n):
            self.comm.send(f"CHAL:{challenge}")
            resp = self.comm.recv()
            if resp.startswith("RESP:"):
                bit = int(resp.split(":")[1])
                votes.append(bit)
            else:
                print(f"  [Warning] Unexpected response: {resp}")
                votes.append(0)
        result = 1 if sum(votes) > self.cfg.majority_vote_n // 2 else 0
        return result

    # ── Enrollment ────────────────────────────────────────────────────────────
    def enroll(self, crp_path: Optional[Path] = None) -> CRPStore:
        print("\n[Verifier] ── Enrollment Phase ──────────────────────────")
        self.comm.send("ENROLL")
        ack = self.comm.recv()
        if ack != "READY":
            print(f"  [Warning] Expected READY, got: {ack}")

        challenges = list(range(self.cfg.n_challenges))
        responses = []
        for i, c in enumerate(challenges):
            bit = self._query_challenge(c)
            responses.append(bit)
            if (i + 1) % 16 == 0:
                print(f"  Progress: {i+1}/{self.cfg.n_challenges} challenges collected")

        self.crp_store = CRPStore(
            challenges=challenges,
            golden_responses=responses,
            enrolled_at=datetime.now().isoformat(),
        )

        ones = sum(responses)
        print(f"  Done. 1s: {ones}  0s: {self.cfg.n_challenges - ones}  (ideal ~50/50)")

        if crp_path:
            self.crp_store.save(crp_path)

        return self.crp_store

    def load_enrollment(self, crp_path: Path):
        self.crp_store = CRPStore.load(crp_path)

    # ── Authentication ────────────────────────────────────────────────────────
    def authenticate(self, label: str = "auth") -> dict:
        if not self.crp_store:
            raise RuntimeError("Not enrolled. Run enroll() first.")

        print(f"\n[Verifier] ── Authentication ({label}) ──────────────────")
        self.comm.send("AUTH")
        ack = self.comm.recv()
        if ack != "READY":
            print(f"  [Warning] Expected READY, got: {ack}")

        live = []
        for c in self.crp_store.challenges:
            bit = self._query_challenge(c)
            live.append(bit)

        golden = self.crp_store.golden_responses
        mismatches = [g != l for g, l in zip(golden, live)]
        ber = sum(mismatches) / len(mismatches)
        match_rate = 1.0 - ber
        passed = match_rate >= self.cfg.auth_threshold
        trojan_detected = ber > (1 - self.cfg.auth_threshold)

        result = {
            "label": label,
            "timestamp": datetime.now().isoformat(),
            "n_challenges": len(golden),
            "match_rate": round(match_rate, 4),
            "ber": round(ber, 4),
            "mismatched_bits": int(sum(mismatches)),
            "passed": passed,
            "trojan_detected": trojan_detected,
        }

        status = "✅ PASS" if passed else "❌ FAIL"
        trojan = "  ⚠️  TROJAN DETECTED" if trojan_detected else ""
        print(f"  Match: {match_rate*100:.1f}%  BER: {ber*100:.2f}%  {status}{trojan}")

        self.logger.log_auth(result)
        return result

    # ── Stress Test ───────────────────────────────────────────────────────────
    def stress_test(self, n_trials: int = 20) -> dict:
        print(f"\n[Verifier] ── Stress Test ({n_trials} trials) ─────────────────")
        results = []
        for i in range(n_trials):
            r = self.authenticate(label=f"stress_{i}")
            results.append(r)

        bers = [r["ber"] for r in results]
        passes = sum(r["passed"] for r in results)
        import statistics
        summary = {
            "n_trials": n_trials,
            "pass_count": passes,
            "pass_rate": passes / n_trials,
            "avg_ber": round(sum(bers) / len(bers), 4),
            "min_ber": round(min(bers), 4),
            "max_ber": round(max(bers), 4),
            "std_ber": round(statistics.stdev(bers), 4),
        }
        print(f"  Pass rate: {passes}/{n_trials}  Avg BER: {summary['avg_ber']*100:.3f}%  "
              f"Max BER: {summary['max_ber']*100:.3f}%")
        self.logger.log_summary(summary)
        return summary

    def close(self):
        self.comm.close()


# ─── Data Logger ─────────────────────────────────────────────────────────────

class DataLogger:
    def __init__(self, output_dir: str):
        self.out = Path(output_dir)
        self.out.mkdir(parents=True, exist_ok=True)

    def log_auth(self, result: dict):
        path = self.out / "pi_auth_log.csv"
        write_header = not path.exists()
        with open(path, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=result.keys())
            if write_header:
                writer.writeheader()
            writer.writerow(result)

    def log_summary(self, summary: dict):
        path = self.out / "pi_stress_summary.csv"
        write_header = not path.exists()
        with open(path, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=summary.keys())
            if write_header:
                writer.writeheader()
            writer.writerow(summary)


# ─── CLI Entry Point ─────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Pi Verifier — PUF Attestation")
    parser.add_argument("--port",       type=str,   help="Force UART port (e.g. /dev/ttyUSB0)")
    parser.add_argument("--hil",        action="store_true", help="Force HIL socket mode")
    parser.add_argument("--hil-host",   type=str,   default="localhost")
    parser.add_argument("--hil-port",   type=int,   default=9999)
    parser.add_argument("--challenges", type=int,   default=64)
    parser.add_argument("--vote",       type=int,   default=9,  help="Majority vote N (odd)")
    parser.add_argument("--threshold",  type=float, default=0.90)
    parser.add_argument("--stress",     type=int,   default=0,  help="Run N stress trials after auth")
    parser.add_argument("--load-crps",  type=str,   help="Load existing CRPs instead of enrolling")
    parser.add_argument("--save-crps",  type=str,   default="./verifier_output/crps.json",
                        help="Where to save golden CRPs after enrollment")
    args = parser.parse_args()

    cfg = VerifierConfig(
        n_challenges=args.challenges,
        majority_vote_n=args.vote,
        auth_threshold=args.threshold,
        hil_host=args.hil_host,
        hil_port=args.hil_port,
    )

    print("\n╔══════════════════════════════════════════════════════╗")
    print("║   Pi Verifier — PUF Attestation System              ║")
    print("║   Rutgers Hardware & System Security                ║")
    print("╚══════════════════════════════════════════════════════╝\n")

    # ── Establish connection ──────────────────────────────────────────────────
    if args.hil:
        comm = SocketComm(args.hil_host, args.hil_port, cfg.timeout_s)
        mode = "socket"
    elif args.port:
        comm = UARTComm(args.port, cfg.baud_rate, cfg.timeout_s)
        mode = "uart"
    else:
        mode, comm = detect_mode(cfg)

    verifier = PiVerifier(comm, cfg)

    try:
        # ── Enrollment ────────────────────────────────────────────────────────
        if args.load_crps:
            verifier.load_enrollment(Path(args.load_crps))
        else:
            verifier.enroll(crp_path=Path(args.save_crps))

        # ── Authentication ────────────────────────────────────────────────────
        verifier.authenticate(label="normal")

        # ── Optional stress test ──────────────────────────────────────────────
        if args.stress > 0:
            verifier.stress_test(n_trials=args.stress)

        print(f"\n  📁 Logs saved to: ./verifier_output/\n")

    finally:
        verifier.close()


if __name__ == "__main__":
    main()
