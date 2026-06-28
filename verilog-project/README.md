# Verilog Digital Design Project

RTL design and functional verification of digital logic modules using Verilog HDL, simulated with Vivado xsim.

---

## Overview

This project covers the fundamentals of RTL design: writing synthesisable Verilog, building self-checking testbenches, and analysing waveforms to confirm functional correctness before targeting an FPGA.

---

## Tools & Technologies

| Tool | Purpose |
|---|---|
| Verilog HDL | RTL design and testbench authoring |
| Vivado xsim | Behavioural simulation |
| Waveform viewer | Signal inspection and debug |
| Xilinx Vivado | Synthesis and implementation (Zybo Z7 target) |

---

## Design & Verification Approach

1. **RTL module** — written in synthesisable Verilog with parameterised interfaces
2. **Testbench** — applies stimulus, checks outputs against expected values, and reports pass/fail
3. **Simulation** — waveform analysis to verify timing and state transitions
4. **Synthesis check** — confirm no latches, clean timing, resource utilisation report

---

## Key Learnings

- RTL coding style: combinational vs sequential logic, avoiding latches
- Writing self-checking testbenches with `$display` and `$finish`
- Interpreting simulation waveforms to isolate functional bugs
- Understanding the gap between simulation and synthesis behaviour

---

> RTL source files and testbenches coming soon.
