# ============================================================================
# File:        run_imm_gen.do
# Project:     SPARK
# Description: Questa simulation script for the Immediate Generator unit test.
#
# Usage:
#   cd sim && vsim -c -do run_imm_gen.do
#   cd sim && vsim -gui -do run_imm_gen.do
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/imm_gen.sv \
    ../tb/unit/tb_imm_gen.sv

vsim -t 1ns -voptargs="+acc" work.tb_imm_gen

if {[batch_mode] == 0} {
    add wave -divider "Input"
    add wave -hex /tb_imm_gen/dut/instr
    add wave -hex /tb_imm_gen/dut/opcode

    add wave -divider "Output"
    add wave -hex /tb_imm_gen/dut/imm

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
