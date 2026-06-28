# golden_ref.py
# Optional Python golden reference for the same FIR math as the Verilog DUT.
# Generates a small example sequence and prints outputs.
#
# Usage:
#   python3 golden_ref.py

from typing import List
import random

# Match Verilog params
C = [3, 8, 13, 13, 8, 3]   # signed 8-bit coefficients
SHIFT = 5

def sat8(v: int) -> int:
    if v > 127: return 127
    if v < -128: return -128
    return v

def fir_step(x_hist: List[int], x_in: int) -> int:
    # x_hist holds previous samples [x[n-1], x[n-2], ... x[n-5]]
    acc = x_in*C[0]
    for k in range(1, 6):
        acc += x_hist[k-1]*C[k]
    y = sat8(acc >> SHIFT)  # arithmetic shift for Python ints
    # update history
    x_hist[:] = [x_in] + x_hist[:-1]
    return y

def main():
    x_hist = [0]*5
    seq = [1] + [0]*10 + [random.randint(-128,127) for _ in range(20)]
    ys = []
    for x in seq:
        ys.append(fir_step(x_hist, x))
    print("x:", seq)
    print("y:", ys)

if __name__ == "__main__":
    main()
