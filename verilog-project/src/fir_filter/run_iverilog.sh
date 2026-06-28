#!/usr/bin/env bash
set -euo pipefail

iverilog -g2005-sv -o sim fir6_8bit.v tb_fir6_8bit.v
vvp sim
echo "VCD generated: fir.vcd"
