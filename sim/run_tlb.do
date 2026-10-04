# ============================================================================
# File:        run_tlb.do
# Project:     SPARK
# Description: Questa simulation script for TLB unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/core/tlb.sv \
    ../tb/unit/tb_tlb.sv

vsim -t 1ns -voptargs="+acc" work.tb_tlb

run -all

if {[batch_mode]} {
    quit -f
}
