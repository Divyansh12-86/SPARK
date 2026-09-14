# ============================================================================
# File:        run_ctrl_unit.do
# Project:     SPARK
# Description: Questa simulation script for the Control Unit unit test.
#
# Usage:
#   cd sim && vsim -c -do run_ctrl_unit.do
#   cd sim && vsim -gui -do run_ctrl_unit.do
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/ctrl_unit.sv \
    ../tb/unit/tb_ctrl_unit.sv

vsim -t 1ns -voptargs="+acc" work.tb_ctrl_unit

if {[batch_mode] == 0} {
    add wave -divider "Input"
    add wave -binary /tb_ctrl_unit/dut/opcode

    add wave -divider "Control Outputs"
    add wave /tb_ctrl_unit/dut/reg_write
    add wave /tb_ctrl_unit/dut/alu_src
    add wave /tb_ctrl_unit/dut/mem_write
    add wave /tb_ctrl_unit/dut/mem_read
    add wave /tb_ctrl_unit/dut/wb_src
    add wave /tb_ctrl_unit/dut/branch
    add wave /tb_ctrl_unit/dut/jump
    add wave -binary /tb_ctrl_unit/dut/alu_op

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
