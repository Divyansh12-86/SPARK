# ============================================================================
# File:        run_custom_decoder.do
# Project:     SPARK
# Description: Questa simulation script for Custom Decoder unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/custom_decoder.sv \
    ../tb/unit/tb_custom_decoder.sv

vsim -t 1ns -voptargs="+acc" work.tb_custom_decoder

run -all

if {[batch_mode]} {
    quit -f
}
