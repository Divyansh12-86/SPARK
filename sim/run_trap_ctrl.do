# ============================================================================
# File:        run_trap_ctrl.do
# Project:     SPARK
# Description: Questa simulation script for Trap Controller unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/trap_ctrl.sv \
    ../tb/unit/tb_trap_ctrl.sv

vsim -t 1ns -voptargs="+acc" work.tb_trap_ctrl

run -all

if {[batch_mode]} {
    quit -f
}
