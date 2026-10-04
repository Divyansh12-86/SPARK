# ============================================================================
# File:        run_mmu_sv32.do
# Project:     SPARK
# Description: Questa simulation script for Sv32 MMU unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/tlb.sv \
    ../rtl/core/mmu_sv32.sv \
    ../tb/unit/tb_mmu_sv32.sv

vsim -t 1ns -voptargs="+acc" work.tb_mmu_sv32

run -all

if {[batch_mode]} {
    quit -f
}
