# ============================================================================
# File:        run_alu_ctrl.do
# Project:     SPARK
# Description: Questa simulation script for ALU Control unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/alu_ctrl.sv \
    ../tb/unit/tb_alu_ctrl.sv

vsim -t 1ns -voptargs="+acc" work.tb_alu_ctrl

if {[batch_mode] == 0} {
    add wave -divider "Inputs"
    add wave -binary /tb_alu_ctrl/dut/alu_op_hint
    add wave -binary /tb_alu_ctrl/dut/funct3
    add wave /tb_alu_ctrl/dut/funct7_5

    add wave -divider "Output"
    add wave /tb_alu_ctrl/dut/alu_op

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
