# Trusted Multi-Sensor Validation Console

A two-layer hardware trust system implemented entirely in VHDL on the Zybo Zynq-7000 FPGA. A ring-oscillator PUF authenticates the physical silicon before sensor validation is permitted — no soft-core processor used.

**Course:** Embedded Systems I/III — Rutgers ECE, Spring 2026

---

## Overview

The system enforces a strict trust hierarchy:

1. **PUF layer** — authenticates the physical FPGA board using manufacturing variation. Only the enrolled board passes.
2. **Sensor layer** — validates communication integrity and measurement plausibility of a connected PMOD sensor (ALS or TMP3). Unreachable until PUF passes.

All coordination is handled by a central 9-state VHDL FSM. A Pmod OLED displays live status; LEDs reflect FSM state.

---

## System Architecture

```
                        ┌─────────────────────────────────┐
                        │       Zybo Zynq-7000 (125 MHz)  │
                        │                                 │
  JA ── Pmod KYPD ─────▶│  pmod_kypd.vhd                 │
  JD ── Pmod OLED ◀─────│  oled_status_display.vhd        │
  JB ── Pmod ALS/TMP3──▶│  sensor_port_validation_core.vhd│
                        │                                 │
                        │  ┌──────────────────────────┐   │
                        │  │ validation_control_fsm   │   │
                        │  │ IDLE→AUTH→PUF_PASS→      │   │
                        │  │ READY→SENSOR→PASS/FAIL   │   │
                        │  └────────────┬─────────────┘   │
                        │               │                  │
                        │  ┌────────────▼─────────────┐   │
                        │  │  puf_top_real_ro.vhd     │   │
                        │  │  64 ROs, 32 pairs        │   │
                        │  │  Hamming(response,enroll)│   │
                        │  │  threshold = 8           │   │
                        │  └──────────────────────────┘   │
                        └─────────────────────────────────┘
```

---

## Hardware

| Component | Connector | Function |
|---|---|---|
| Zybo Zynq-7000 Rev B | — | FPGA host (125 MHz, 7z010) |
| Pmod KYPD | JA | Key 1 = trigger, Key 2 = retry |
| Pmod OLED | JD | 128×32 SPI status display |
| Pmod ALS | JB | Ambient light sensor (SPI) |
| Pmod TMP3 | JB | Temperature sensor (I2C) |

---

## VHDL Module Hierarchy

| File | Function | Key Signals |
|---|---|---|
| `trusted_sensor_console_pmod_hw.vhd` | Top-level integration | All PMOD ports, clk, rst_btn, led |
| `validation_control_fsm.vhd` | Central 9-state FSM | `display_code`, `validation_enable` |
| `puf_top_real_ro.vhd` | PUF authentication wrapper | `start_auth`, `auth_done`, `auth_valid` |
| `real_ro_puf_array.vhd` | 64 RO counter array + Hamming compare | `puf_response[31:0]` |
| `real_ro_osc.vhd` | Single 5-stage ring oscillator cell | `ro_out` (free-running) |
| `sensor_port_validation_core.vhd` | Shared JB port handler (ALS/TMP3) | `sensor_pass`, `sensor_done` |
| `pmod_als_reader.vhd` | SPI ALS driver | `light_value[7:0]` |
| `tmp3_i2c_reader.vhd` | I2C TMP3 driver | `temp_value[10:0]` |
| `oled_status_display.vhd` | Non-blocking SPI OLED controller | `oled_cs/sclk/sdin/dc/res` |
| `pmod_kypd.vhd` | 4×4 keypad matrix scanner | `key_valid`, `key_code[3:0]` |
| `button_pulse.vhd` | Single-cycle pulse generator | `pulse_out` |
| `tb_trusted_sensor_top.vhd` | FSM behavioural testbench | — |

---

## PUF Design

- **64 ring oscillators**, each a 5-stage LUT inverter chain
- Organized as **32 comparison pairs** — faster oscillator → `'1'`, slower → `'0'`
- Measurement window: **50,000 clock cycles** @ 125 MHz = 0.4 ms per authentication
- All 64 instances pinned with **LOC constraints** (SLICE_X10–SLICE_X17) and `DONT_TOUCH` attributes — critical for exposing chip-level silicon differences
- Enrolled response: `0x30911128`
- **Hamming distance threshold: 8 / 32 bits**

Cross-board test: enrolled board → PUF PASS. Second Zybo → AUTH FAIL. LOC constraints were the key fix; without them Vivado placed both boards identically.

---

## FSM State Machine

```
IDLE → AUTH_START → AUTH_WAIT → AUTH_CHECK ─┬─ PUF_PASS → READY → SENSOR_CHECK ─┬─ SENSOR_PASS
                                             └─ AUTH_FAIL                         └─ SENSOR_FAIL
```

Key 1 triggers each stage. Key 2 retries or returns to IDLE. Sensor validation is **gated** — unreachable until PUF passes.

---

## LED State Reference

| LED[3:0] | FSM State | Meaning |
|---|---|---|
| `0000` | IDLE | Waiting after reset |
| `0001` | AUTH_START | PUF measurement triggered |
| `0010` | AUTH_WAIT | Counting ring oscillators |
| `0011` | AUTH_CHECK | Comparing Hamming distance |
| `1011` | PUF_PASS | Board authenticated |
| `0101` | AUTH_FAIL | PUF authentication failed |
| `0110` | READY | Awaiting sensor validation |
| `1001` | SENSOR_PASS | Sensor accepted |
| `1010` | SENSOR_FAIL | Sensor rejected |

---

## Resource Utilization (Zybo 7z010)

| Resource | Used | Available | % |
|---|---|---|---|
| LUT | 1,121 | 17,600 | 6.37% |
| FF | 1,859 | 35,200 | 5.28% |
| IO | 24 | 100 | 24.00% |
| BUFG | 1 | 32 | 3.13% |
| BRAM | 0 | 60 | 0% |

**Total power:** 0.120 W (static 0.093 W + dynamic 0.027 W)  
**End-to-end latency** (button → OLED result): ~15–20 ms

---

## Key Vivado Constraints (RO-PUF)

Standard Vivado DRC blocks bitstream generation for combinational loops. Four overrides were required:

```tcl
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets ro_out]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
set_property DONT_TOUCH TRUE [get_cells ro_inst_*]
# LOC constraints pinning all 64 ROs to SLICE_X10Y0 – SLICE_X17Y14
```

---

## Engineering Challenges

| Challenge | Solution |
|---|---|
| Vivado blocked bitstream for combinational loops | `ALLOW_COMBINATORIAL_LOOPS` + `LUTLP-1` severity override |
| Both Zybo boards gave identical PUF response | Added LOC constraints to pin each RO to a specific slice |
| OLED SPI writes stalling FSM | Decoupled OLED updates via `pending_code` register and separate pulse process |
| JB/JD pin mapping error for TMP3 | Re-verified Zybo Rev B package pin assignments in XDC |
| ALS has no device ID register | Used behavioral validation: light level range plausibility check |

---

## PUF Enrollment Procedure

The 32-bit enrolled response was captured using a temporary LED-debug mode on the primary board. Key 2 cycled through nibbles 0–7, which were read from LED[3:0] and assembled:

```
Nibble 7→0: 0011 0000 1001 0001 0001 0001 0010 1000
Response:   0x30911128
```

This is hardcoded as the `ENROLLED_RESPONSE` generic constant in `real_ro_puf_array.vhd`.

---

## Limitations & Future Work

- PUF characterized at a single temperature/voltage — a fuzzy extractor is needed for field operation
- Enrolled response is hardcoded (requires resynthesis for re-enrollment); BRAM storage is the next step
- JB supports ALS **or** TMP3, not simultaneously
- Active ALS challenge (cover → illuminate → validate delta) would provide stronger sensor identity verification
- Challenge-based RO pair selection instead of a fixed response would improve PUF security

---

## References

1. Vahid & Givargis, *Embedded System Design*, Ch. 7
2. Digilent Zybo Zynq-7000 Reference Manual
3. Digilent Pmod ALS, TMP3, OLED, KYPD Reference Manuals
4. AMD/Xilinx Vivado UG903 — Using Constraints
