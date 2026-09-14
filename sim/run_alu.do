# ============================================================================
# File:        run_alu.do
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# Description: Questa / ModelSim Tcl simulation script for the RV32I ALU.
#
# Usage:
#   Batch mode (terminal only, quick test):
#     cd sim && vsim -c -do run_alu.do
#
#   GUI mode (interactive with waveforms):
#     cd sim && vsim -gui -do run_alu.do
# ============================================================================

# 1. Create and map the work library inside the sim directory
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# 2. Compile source files in correct dependency order:
#    - First:  Shared package (riscv_pkg.sv) so definitions are in the library
#    - Second: ALU module (alu.sv) which imports riscv_pkg
#    - Third:  Testbench (tb_alu.sv)
vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/alu.sv \
    ../tb/unit/tb_alu.sv

# 3. Optimize and load simulation with full signal visibility (+acc)
#    -voptargs="+acc" ensures all internal signals and registers can be viewed
#    in waveforms without being stripped out by simulator optimizations.
vsim -t 1ns -voptargs="+acc" work.tb_alu

# 4. Configure waveform view if running in GUI mode
if {[batch_mode] == 0} {
    add wave -divider "Inputs"
    add wave -hex /tb_alu/dut/a
    add wave -hex /tb_alu/dut/b
    add wave /tb_alu/dut/alu_op

    add wave -divider "Outputs"
    add wave -hex /tb_alu/dut/result
    add wave /tb_alu/dut/zero

    # Zoom to fit all signals across time
    wave zoom full
}

# 5. Run simulation
run -all

# 6. If batch mode, exit cleanly
if {[batch_mode]} {
    quit -f
}
