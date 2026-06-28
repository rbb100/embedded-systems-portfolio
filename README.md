# Embedded Systems Portfolio – Rahul Biju

**M.S. Electrical & Computer Engineering — Rutgers University**  
Prior industry experience in embedded ECU validation and system testing.  
Transitioning toward development-oriented roles in embedded systems, digital design, and hardware security.

---

## Projects

| Project | Domain | Languages | Hardware |
|---|---|---|---|
| [Trusted Multi-Sensor Validation Console](#trusted-multi-sensor-validation-console) | Hardware security, FPGA | VHDL | Zybo Z7, Pmod KYPD/OLED/ALS/TMP3 |
| [PUF Enrollment System](#puf-enrollment-system) | Hardware security, embedded Linux | Verilog, Python | Zybo Z7, Raspberry Pi 3 |
| [Eco-RIC: O-RAN Power Controller](#eco-ric-o-ran-inspired-power-controller) | Embedded Linux, distributed systems | Python | Raspberry Pi 4, ADC0832, DHT11, LEDs |
| [Verilog RTL Modules](#verilog-rtl-modules) | Digital design, RTL verification | Verilog | Simulation (Icarus / Vivado xsim) |

---

## Skills Matrix

| Skill | Projects |
|---|---|
| FPGA / RTL design (VHDL) | Trusted Sensor, PUF Enrollment |
| Verilog HDL | PUF Enrollment, Verilog Modules |
| Hardware security / PUF | Trusted Sensor, PUF Enrollment |
| Embedded Linux (Raspberry Pi) | Eco-RIC, PUF Enrollment |
| UART / SPI / I2C peripherals | Trusted Sensor, PUF Enrollment, Eco-RIC |
| Python (control logic, simulation) | PUF Enrollment, Eco-RIC |
| Distributed messaging (ZeroMQ) | Eco-RIC |
| Self-checking testbenches | Trusted Sensor, Verilog Modules |
| Fixed-point DSP | Verilog Modules (FIR filter) |
| FSM design | Trusted Sensor, Verilog Modules |

---

## Trusted Multi-Sensor Validation Console

**`trusted-sensor-project/`** — Spring 2026 Embedded Systems final project

A two-layer hardware trust system on the Zybo Zynq-7000 FPGA. A ring-oscillator PUF (64 ROs, 32-bit Hamming-distance authentication) authenticates the physical silicon before a sensor validation layer is unlocked. Implemented entirely in VHDL without a soft-core processor; all PMOD drivers are custom. Demonstrated cross-board PUF rejection.

**Key highlights:**
- 9-state central VHDL FSM coordinating PUF auth, KYPD input, OLED display, and sensor validation
- LOC-constrained RO placement as the critical fix for board-unique responses
- Validated with Pmod ALS (SPI) and Pmod TMP3 (I2C) on a shared JB port
- 1,121 LUTs (6.37%), 0.120 W total power

---

## PUF Enrollment System

**`PUF_Enrollment_project/`**

An end-to-end PUF enrollment and authentication protocol. The Zybo Z7 FPGA (Verilog RO-PUF with UART command FSM) acts as the Prover; a Raspberry Pi 3 Python script acts as the Verifier. Includes a full HIL simulation (no hardware required), noise characterisation, Trojan injection demo, and Hamming Distance analysis.

**Key highlights:**
- UART command protocol (`PING` / `ENROLL` / `AUTH` / `CHAL:N` / `TROJAN:ON/OFF`)
- 9-vote majority-vote stabiliser reducing PUF bit-error rate
- TCP socket bridge enabling HIL simulation on a single PC
- BER vs noise sweep with matplotlib plots

---

## Eco-RIC: O-RAN-Inspired Power Controller

**`raspberry-pi-project/`**

A Raspberry Pi 4 prototype that demonstrates autonomous, energy-aware control of a simulated 5G Radio Unit. Network telemetry arrives over ZeroMQ; a linear regression model predicts traffic surges and pre-emptively boosts power. A Flask dashboard shows live state.

**Key highlights:**
- Three power policies: Sleep (<30% load), Active (PWM-scaled), Predictive Boost (AI surge detection)
- ZeroMQ pub/sub decouples the traffic simulator from the controller
- Bit-banged SPI for ADC0832 LDR reads; DHT11 ambient sensor
- Physical validation through GPIO/PWM LED response

---

## Verilog RTL Modules

**`verilog-project/`**

Four standalone RTL modules, each with a self-checking testbench:

| Module | Description |
|---|---|
| 32-bit Signed ALU | Five operations (AND/OR/ADD/SUB/SLT), MIPS-style ALUOp encoding |
| 6-tap FIR Filter | Fixed-point, 8-bit I/O, saturation, 500-sample self-checking testbench + Python golden ref |
| Moore FSM (mod-3) | Detects when running count of 1s is divisible by 3; cycle-by-cycle trace |
| 8-bit CLA Adder | Fully-expanded lookahead logic for bits 0–3; `generate`-based full adder instantiation |

---

## Background

My industry experience was in embedded ECU validation — functional testing, test automation, and system-level debugging on automotive platforms. These projects represent deliberate hands-on work to build development skills alongside that validation foundation: writing RTL, implementing hardware security primitives, integrating real peripherals, and debugging timing-sensitive systems end-to-end.
