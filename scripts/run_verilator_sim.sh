#!/usr/bin/env bash
# ============================================================================
# Script:      run_verilator_sim.sh
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# Description: Automated build & regression script for SPARK Verilator simulation.
# ============================================================================

set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SPARK_ROOT="$SCRIPT_DIR/.."
SIM_DIR="$SPARK_ROOT/sim"

echo "=== Building SPARK Verilator Model ==="
make -C "$SIM_DIR" -f Makefile

echo ""
echo "=== Running High-Speed SoC Co-Simulation ==="
"$SIM_DIR/obj_dir/Vspark_soc_top" 50000

echo ""
echo "=== Verilator Simulation Completed Successfully ==="
