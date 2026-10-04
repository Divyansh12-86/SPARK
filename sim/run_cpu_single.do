# ============================================================================
# File:        run_cpu_single.do
# Project:     SPARK
# Description: Questa simulation script for Single-Cycle RV32I CPU system test.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/pkg/riscv_pkg.sv \
    ../rtl/core/alu.sv \
    ../rtl/core/reg_file.sv \
    ../rtl/core/imm_gen.sv \
    ../rtl/core/ctrl_unit.sv \
    ../rtl/core/alu_ctrl.sv \
    ../rtl/core/branch_unit.sv \
    ../rtl/core/pc_reg.sv \
    ../rtl/core/instr_mem.sv \
    ../rtl/core/data_mem.sv \
    ../rtl/core/cpu_single.sv \
    ../tb/system/tb_cpu_single.sv

vsim -t 1ns -voptargs="+acc" work.tb_cpu_single

if {[batch_mode] == 0} {
    add wave -divider "Clock & Reset"
    add wave /tb_cpu_single/clk
    add wave /tb_cpu_single/rst_n

    add wave -divider "Program Counter & Instruction"
    add wave -hex /tb_cpu_single/dut/pc
    add wave -hex /tb_cpu_single/dut/instr

    add wave -divider "Control Signals"
    add wave /tb_cpu_single/dut/reg_write
    add wave /tb_cpu_single/dut/branch_taken
    add wave /tb_cpu_single/dut/jump

    add wave -divider "ALU Execution"
    add wave /tb_cpu_single/dut/alu_op
    add wave -hex /tb_cpu_single/dut/alu_in_a
    add wave -hex /tb_cpu_single/dut/alu_in_b
    add wave -hex /tb_cpu_single/dut/alu_result

    add wave -divider "Writeback"
    add wave -hex /tb_cpu_single/dut/wb_data
    add wave -unsigned /tb_cpu_single/dut/rd

    add wave -divider "Register File (x1 - x11)"
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[1]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[2]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[3]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[4]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[5]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[6]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[7]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[8]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[9]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[10]
    add wave -hex /tb_cpu_single/dut/u_reg_file/registers[11]

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
