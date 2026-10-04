# ============================================================================
# File:        run_data_mem.do
# Project:     SPARK
# Description: Questa simulation script for Data Memory unit test.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/core/data_mem.sv \
    ../tb/unit/tb_data_mem.sv

vsim -t 1ns -voptargs="+acc" work.tb_data_mem

run -all

if {[batch_mode]} {
    quit -f
}
