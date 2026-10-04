# ============================================================================
# File:        run_cpu_pipe.do
# Project:     SPARK
# Description: Questa simulation script for 5-Stage Pipelined RV32I CPU system test.
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
    ../tb/system/tb_cpu_pipe.sv

vsim -t 1ns -voptargs="+acc" work.tb_cpu_pipe

if {[batch_mode] == 0} {
    add wave -divider "Clock & Reset"
    add wave /tb_cpu_pipe/clk
    add wave /tb_cpu_pipe/rst_n

    add wave -divider "Hazard Control"
    add wave /tb_cpu_pipe/dut/stall_pc
    add wave /tb_cpu_pipe/dut/stall_if_id
    add wave /tb_cpu_pipe/dut/flush_if_id
    add wave /tb_cpu_pipe/dut/flush_id_ex

    add wave -divider "Fetch Stage"
    add wave -hex /tb_cpu_pipe/dut/pc_if
    add wave -hex /tb_cpu_pipe/dut/instr_if

    add wave -divider "Decode Stage"
    add wave -hex /tb_cpu_pipe/dut/pc_id
    add wave -hex /tb_cpu_pipe/dut/instr_id

    add wave -divider "Execute Stage"
    add wave -hex /tb_cpu_pipe/dut/pc_ex
    add wave -hex /tb_cpu_pipe/dut/alu_result_ex
    add wave -binary /tb_cpu_pipe/dut/forward_a
    add wave -binary /tb_cpu_pipe/dut/forward_b
    add wave /tb_cpu_pipe/dut/branch_taken_ex

    add wave -divider "Memory Stage"
    add wave -hex /tb_cpu_pipe/dut/alu_result_mem
    add wave /tb_cpu_pipe/dut/mem_read_mem
    add wave /tb_cpu_pipe/dut/mem_write_mem

    add wave -divider "Writeback Stage"
    add wave -hex /tb_cpu_pipe/dut/wb_data
    add wave -unsigned /tb_cpu_pipe/dut/rd_addr_wb
    add wave /tb_cpu_pipe/dut/reg_write_wb

    add wave -divider "Registers (x1 - x11)"
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[1]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[2]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[3]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[4]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[5]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[6]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[7]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[8]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[9]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[10]
    add wave -hex /tb_cpu_pipe/dut/u_reg_file/registers[11]

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
