# ============================================================================
# File:        run_branch_unit.do
# Project:     SPARK
# Description: Questa simulation script for Branch Decision Unit.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/core/branch_unit.sv \
    ../tb/unit/tb_branch_unit.sv

vsim -t 1ns -voptargs="+acc" work.tb_branch_unit

run -all

if {[batch_mode]} {
    quit -f
}
