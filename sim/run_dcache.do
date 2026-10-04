# ============================================================================
# File:        run_dcache.do
# Project:     SPARK
# Description: Questa simulation script for L1 Data Cache unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/core/dcache.sv \
    ../tb/unit/tb_dcache.sv

vsim -t 1ns -voptargs="+acc" work.tb_dcache

run -all

if {[batch_mode]} {
    quit -f
}
