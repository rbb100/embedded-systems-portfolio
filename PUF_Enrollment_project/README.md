# PUF-Based Edge Device Attestation System

**Rutgers Hardware & System Security — Rahul Biju — Spring 2026**

---

## Overview

This project implements a **Physical Unclonable Function (PUF)** based device attestation system using a Ring Oscillator (RO-PUF) architecture. A **Zybo Z7 FPGA** acts as the Prover, generating a unique hardware fingerprint from silicon process variation. A **Raspberry Pi 3** acts as the Verifier, enrolling and authenticating the device over UART. A **HIL (Hardware-in-the-Loop) simulation** allows full protocol testing on a PC without any physical hardware.

The system also includes a **hardware Trojan simulation** that injects a fault into the PUF array and demonstrates detection via BER spike.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Zybo Z7 FPGA                     │
│                                                     │
│   ┌─────────────┐     ┌──────────────────────────┐  │
│   │  UART RX/TX │────▶│      command_fsm.v       │  │
│   │  (115200)   │     │  (FSM: PING/ENROLL/AUTH/ │  │
│   └─────────────┘     │   CHAL/TROJAN:ON/OFF)    │  │
│                       └──────────┬───────────────┘  │
│                                  │                  │
│                       ┌──────────▼───────────────┐  │
│                       │     majority_vote.v       │  │
│                       │  (9-vote stabilizer)      │  │
│                       └──────────┬───────────────┘  │
│                                  │                  │
│                       ┌──────────▼───────────────┐  │
│                       │     ro_puf_array.v        │  │
│                       │  (16 ROs, counter-based,  │  │
│                       │   Trojan-injectable)       │  │
│                       └──────────────────────────┘  │
└─────────────────────────────────────────────────────┘
         │ UART (PmodUSBUART)
         ▼
┌────────────────────┐
│   Raspberry Pi 3   │
│   pi_verifier.py   │
│  (enroll + auth)   │
└────────────────────┘
```

---

## Repository Structure

```
PUF_Enrollment_project/
│
├── src/                        # RTL source files (Vivado project)
│   ├── puf_top.v               # Top-level wrapper (Zybo Z7, 125 MHz)
│   ├── ro_puf_array.v          # Ring Oscillator PUF array (16 ROs)
│   ├── command_fsm.v           # UART command FSM (enroll/auth/trojan)
│   ├── majority_vote.v         # 9-vote majority vote stabilizer
│   ├── uart_trx.v              # 8N1 UART transceiver (115200 baud)
│   ├── tb_puf_top.v            # Behavioural testbench
│   └── puf_top.xdc             # Zybo Z7 pin constraints
│
├── virtual_puf.py              # Software RO-PUF model (silicon + noise)
├── hil_simulation.py           # Full HIL simulation runner
├── hil_uart_bridge.py          # TCP bridge (virtual Zybo ↔ pi_verifier)
├── pi_verifier.py              # Raspberry Pi verifier script
├── plot_results.py             # Plot generator from CSV logs
└── README.md
```

---

## RTL Design (src/)

| Module | Description |
|---|---|
| `puf_top.v` | Top-level. 125 MHz clock, active-low reset sync, wires up FSM + LEDs |
| `ro_puf_array.v` | 16 virtual Ring Oscillators. Counter-based measurement over a configurable window. Trojan flag freezes the lower-half ROs to simulate fault injection |
| `command_fsm.v` | UART FSM. Accepts `PING`, `ENROLL`, `AUTH`, `CHAL:N`, `TROJAN:ON`, `TROJAN:OFF` commands. Returns `READY`, `ACK`, `RESP:0/1`, or `ERR` |
| `majority_vote.v` | Collects N_VOTES (default 9, must be odd) measurements and returns the majority bit to reduce noise-induced BER |
| `uart_trx.v` | 8N1 UART at 115200 baud. 2-FF synchronizer on RX input. Mid-bit sampling on receive |
| `tb_puf_top.v` | Behavioural testbench for Vivado xsim |

### Key Parameters

| Parameter | Default | Description |
|---|---|---|
| `CLK_FREQ` | 125_000_000 | System clock (Zybo on-board oscillator) |
| `BAUD_RATE` | 115_200 | UART baud rate |
| `N_RO` | 16 | Number of Ring Oscillators |
| `N_VOTES` | 9 | Majority vote count (must be odd) |
| `WINDOW_SIZE` | 5000 | RO measurement window (cycles) |

### UART Command Protocol

| Command | Response | Description |
|---|---|---|
| `PING\n` | `READY\n` | Connectivity check |
| `ENROLL\n` | `READY\n` | Begin enrollment session |
| `AUTH\n` | `READY\n` | Begin authentication session |
| `CHAL:N\n` | `RESP:0\n` or `RESP:1\n` | Measure RO pair N, return majority-voted bit |
| `TROJAN:ON\n` | `ACK\n` | Inject hardware Trojan (freezes lower-half ROs) |
| `TROJAN:OFF\n` | `ACK\n` | Remove hardware Trojan |

### LED Indicators (Zybo Z7)

| LED | Pin | Meaning |
|---|---|---|
| LED0 | M14 | Last `CHAL` response bit |
| LED1 | M15 | Trojan mode active |

---

## Software

### Dependencies

Install on PC (WSL/Ubuntu) and Raspberry Pi:

```bash
pip install numpy matplotlib pandas pyserial --break-system-packages
```

---

## Option A — HIL Simulation (no hardware needed)

### 1. Full simulation

```bash
cd ~/puf_project
python3 hil_simulation.py
```

Enrolls 64 challenges, runs normal auth, stress test, Trojan demo, and Hamming Distance analysis. All output saved to `./hil_output/`.

**Expected output:**
```
[Verifier] Enrollment complete — 64 CRPs stored.
[Normal]  Match Rate: 98.4%  BER: 1.56%  ✅ PASS
Pass rate: 20/20  Avg BER: 7.2%
[Trojan]  Match Rate: 79.7%  BER: 20.3%  ❌ FAIL  ⚠️ TROJAN DETECTED
```

### 2. Noise sweep

```bash
python3 hil_simulation.py --sweep
```

### 3. Generate plots

```bash
python3 plot_results.py
```

Outputs 4 PNGs to `./hil_output/plots/`:
- `1_auth_log.png` — match rate and BER per run
- `2_noise_sweep.png` — BER vs noise level
- `3_intra_hd.png` — intra-device Hamming Distance (reliability)
- `4_inter_hd.png` — inter-device Hamming Distance (uniqueness)

### 4. HIL bridge mode (simulates Pi ↔ Zybo over TCP)

```bash
# Terminal 1 — virtual Zybo
python3 hil_uart_bridge.py

# Terminal 2 — verifier
python3 pi_verifier.py --hil
```

---

## Option B — Real Hardware (Zybo Z7 + Raspberry Pi)

### Requirements
- Zybo Z7 programmed with `puf_top.bit` via Vivado Hardware Manager
- PmodUSBUART on Zybo JB header → USB cable to Raspberry Pi
- Pi on the same network as your laptop

### 1. SSH into Pi and verify UART

```bash
ssh pi@raspberrypi.local   # password: raspberry
ls /dev/ttyUSB*            # should show /dev/ttyUSB0
```

### 2. Enrollment and authentication

```bash
python3 pi_verifier.py --port /dev/ttyUSB0
```

### 3. Stress test (skip re-enrollment)

```bash
python3 pi_verifier.py --port /dev/ttyUSB0 --stress 20 --load-crps verifier_output/crps.json
```

### 4. Trojan demonstration

```bash
# Inject Trojan
python3 -c "import serial; s=serial.Serial('/dev/ttyUSB0',115200,timeout=3); s.write(b'TROJAN:ON\n'); print(s.readline())"

# Re-authenticate — watch match rate drop and LED1 turn ON
python3 pi_verifier.py --port /dev/ttyUSB0 --load-crps verifier_output/crps.json

# Remove Trojan
python3 -c "import serial; s=serial.Serial('/dev/ttyUSB0',115200,timeout=3); s.write(b'TROJAN:OFF\n'); print(s.readline())"
```

---

## CLI Reference

### hil_simulation.py

| Flag | Default | Description |
|---|---|---|
| `--sweep` | — | BER vs noise sweep (0–1.5%) |
| `--noise 0.3` | 0.1 | Set fixed noise level |

### hil_uart_bridge.py

| Flag | Default | Description |
|---|---|---|
| `--port 9999` | 9999 | TCP port |
| `--noise 0.2` | 0.1 | Noise level |
| `--trojan` | off | Start with Trojan active |
| `--challenges 64` | 64 | CRP count |

### pi_verifier.py

| Flag | Default | Description |
|---|---|---|
| `--port /dev/ttyUSB0` | auto | Force UART port |
| `--hil` | auto | Use HIL TCP socket |
| `--challenges 64` | 64 | Number of CRPs |
| `--vote 9` | 9 | Majority vote count |
| `--threshold 0.90` | 0.90 | Auth pass threshold |
| `--stress 20` | 0 | Run N stress trials |
| `--load-crps path` | re-enroll | Load saved CRPs |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `No Prover found` | Check USB cable, confirm `/dev/ttyUSB0` exists, check DONE LED on Zybo, press BTN0 to reset |
| `pyserial not installed` | `pip install pyserial --break-system-packages` |
| `noise_sweep_log.csv not found` | Run `python3 hil_simulation.py --sweep` first |
| Pi SSH "host identification changed" | `ssh-keygen -R raspberrypi.local` |
| Vivado can't find Zybo | Check USB to PROG/UART port, reinstall Digilent drivers |

---

## Quick Start (5 min, no hardware)

```bash
cd ~/puf_project
source ~/myenv/bin/activate
python3 hil_simulation.py
python3 hil_simulation.py --sweep
python3 plot_results.py
```
