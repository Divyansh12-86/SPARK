# ============================================================================
# File:        run_icache.do
# Project:     SPARK
# Description: Questa simulation script for L1 Instruction Cache unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/core/icache.sv \
    ../tb/unit/tb_icache.sv

vsim -t 1ns -voptargs="+acc" work.tb_icache

run -all

if {[batch_mode]} {
    quit -f
}
