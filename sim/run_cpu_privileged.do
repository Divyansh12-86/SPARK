# ============================================================================
# File:        run_cpu_privileged.do
# Project:     SPARK
# Description: Questa simulation script for Privileged Architecture & Trap verification.
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
    ../rtl/core/if_id_reg.sv \
    ../rtl/core/id_ex_reg.sv \
    ../rtl/core/ex_mem_reg.sv \
    ../rtl/core/mem_wb_reg.sv \
    ../rtl/core/forwarding_unit.sv \
    ../rtl/core/hazard_unit.sv \
    ../rtl/core/csr_file.sv \
    ../rtl/core/trap_ctrl.sv \
    ../rtl/core/cpu_pipe.sv \
    ../tb/system/tb_cpu_privileged.sv

vsim -t 1ns -voptargs="+acc" work.tb_cpu_privileged

if {[batch_mode] == 0} {
    add wave -divider "Clock & Reset"
    add wave /tb_cpu_privileged/clk
    add wave /tb_cpu_privileged/rst_n

    add wave -divider "Trap & Privileged Control"
    add wave /tb_cpu_privileged/dut/u_trap_ctrl/trap_redirect
    add wave -hex /tb_cpu_privileged/dut/u_trap_ctrl/trap_pc_target
    add wave /tb_cpu_privileged/dut/u_trap_ctrl/trap_enter
    add wave -hex /tb_cpu_privileged/dut/u_trap_ctrl/trap_cause
    add wave -hex /tb_cpu_privileged/dut/u_trap_ctrl/trap_pc
    add wave /tb_cpu_privileged/dut/u_trap_ctrl/trap_return_m
    add wave -binary /tb_cpu_privileged/priv_mode_out

    add wave -divider "CSR File State"
    add wave -hex /tb_cpu_privileged/dut/u_csr_file/mtvec
    add wave -hex /tb_cpu_privileged/dut/u_csr_file/mscratch
    add wave -hex /tb_cpu_privileged/dut/u_csr_file/mepc
    add wave -hex /tb_cpu_privileged/dut/u_csr_file/mcause

    add wave -divider "Pipeline Stages"
    add wave -hex /tb_cpu_privileged/dut/pc_if
    add wave -hex /tb_cpu_privileged/dut/instr_if
    add wave -hex /tb_cpu_privileged/dut/pc_ex
    add wave -hex /tb_cpu_privileged/dut/instr_ex
    add wave -hex /tb_cpu_privileged/dut/wb_data
    add wave /tb_cpu_privileged/dut/reg_write_wb
    add wave -unsigned /tb_cpu_privileged/dut/rd_addr_wb

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
