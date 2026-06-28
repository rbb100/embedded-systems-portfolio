# Verilog Digital Design Projects

RTL design and functional verification of digital logic modules using Verilog HDL. Each module has a self-checking testbench and was simulated with Icarus Verilog / Vivado xsim.

---

## Modules

### 1. 32-bit Signed ALU (`src/alu/`)

A combinational 32-bit signed ALU supporting five operations, matching a MIPS-style ALUOp encoding.

| ALUOp | Operation | Description |
|---|---|---|
| `000` | AND | Bitwise AND |
| `001` | OR | Bitwise OR |
| `010` | ADD | Signed addition |
| `110` | SUB | Signed subtraction |
| `111` | SLT | Set-on-less-than (signed) |

Undefined opcodes drive the output to `x` to make testbench bugs visible. Testbench covers all five operations including a negative-number SLT case.

---

### 2. 6-Tap FIR Filter — 8-bit Fixed-Point (`src/fir_filter/`)

A clocked 6-tap FIR filter with 8-bit signed input/output, parameterised coefficients, arithmetic right-shift scaling, and signed 8-bit output saturation.

**Design details:**
- Coefficients: `[3, 8, 13, 13, 8, 3]` (symmetric low-pass, parameterised)
- Internal accumulator width: 24-bit (prevents overflow before scaling)
- Scaling: arithmetic right-shift by `SHIFT` (default 5)
- Saturation: clamps to `[-128, 127]` before output register

**Testbench:**
- Directed impulse-response test (verifies all 6 filter taps)
- 500-sample random test with a Verilog golden model
- Self-checking: reports `PASS` / `FAIL` with mismatch details
- VCD dump for waveform inspection

**Python golden reference** (`golden_ref.py`) replicates the exact fixed-point math for cross-validation.

```bash
# Run with Icarus Verilog
./run_iverilog.sh
# View waveform
gtkwave fir.vcd
```

---

### 3. Moore FSM — Mod-3 Bit Counter (`src/fsm/`)

A synchronous Moore FSM that outputs `1` whenever the running count of `1`s in the input stream is divisible by 3.

**States:**

| State | Count mod 3 | Output |
|---|---|---|
| S0 | 0 | `1` |
| S1 | 1 | `0` |
| S2 | 2 | `0` |

Active-low reset initialises to S0. Internal state is exposed on `state_out[1:0]` for testbench monitoring. Testbench drives a 28-bit sequence and prints a cycle-by-cycle trace of `in`, `out`, and `state`.

---

### 4. 8-bit Carry-Lookahead Adder (`src/carry_lookahead_adder/`)

An 8-bit CLA adder built from 8 full-adder instances using `generate`. Carry propagate (P) and generate (G) signals are computed by each full adder; carries C[1]–C[8] are resolved in parallel using fully-expanded lookahead logic for bits 0–3, then ripple-resolved for bits 4–7.

**Design points:**
- Fully expanded CLA equations for C[1]–C[4] (no ripple dependency)
- `generate` block for clean, scalable instantiation
- Testbench covers corner cases: `0+0`, `0xFF+0xFF`, carry propagation patterns

---

## Tools

| Tool | Use |
|---|---|
| Icarus Verilog (`iverilog` / `vvp`) | Simulation |
| GTKWave | Waveform inspection |
| Vivado xsim | Synthesis-targeted simulation |

---

## Key Concepts Demonstrated

- Combinational vs sequential RTL coding style
- Parameterised modules and `generate` blocks
- Self-checking testbenches with `$display` pass/fail reporting
- Fixed-point arithmetic: accumulator width, arithmetic shift, saturation
- FSM design: state encoding, Moore output logic, reset strategy
- Carry-lookahead adder arithmetic and P/G signal derivation
