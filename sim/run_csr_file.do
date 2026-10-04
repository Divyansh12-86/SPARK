# ============================================================================
# File:        run_csr_file.do
# Project:     SPARK
# Description: Questa simulation script for CSR File unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/csr_file.sv \
    ../tb/unit/tb_csr_file.sv

vsim -t 1ns -voptargs="+acc" work.tb_csr_file

run -all

if {[batch_mode]} {
    quit -f
}
