# ============================================================================
# File:        run_soc_top.do
# Project:     SPARK
# Description: Questa simulation script for SPARK SoC system test.
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
    ../rtl/core/cpu_pipe.sv \
    ../rtl/periph/uart.sv \
    ../rtl/periph/clint.sv \
    ../rtl/periph/plic.sv \
    ../rtl/periph/bus_interconnect.sv \
    ../rtl/top/soc_top.sv \
    ../tb/system/tb_soc_top.sv

vsim -t 1ns -voptargs="+acc" work.tb_soc_top

if {[batch_mode] == 0} {
    add wave -divider "Clock & Reset"
    add wave /tb_soc_top/clk
    add wave /tb_soc_top/rst_n

    add wave -divider "CPU Execution"
    add wave -hex /tb_soc_top/dut/u_cpu/pc_if
    add wave -hex /tb_soc_top/dut/u_cpu/instr_id
    add wave -hex /tb_soc_top/dut/cpu_mem_addr
    add wave /tb_soc_top/dut/cpu_mem_write
    add wave -hex /tb_soc_top/dut/cpu_mem_wdata

    add wave -divider "Bus Chip Selects"
    add wave /tb_soc_top/dut/cs_uart
    add wave /tb_soc_top/dut/cs_clint
    add wave /tb_soc_top/dut/cs_plic

    add wave -divider "UART Peripheral"
    add wave -hex /tb_soc_top/dut/u_uart/thr
    add wave /tb_soc_top/dut/uart_tx

    add wave -divider "CLINT Peripheral"
    add wave -hex /tb_soc_top/dut/u_clint/mtime
    add wave -hex /tb_soc_top/dut/u_clint/mtimecmp
    add wave /tb_soc_top/dut/u_clint/timer_irq

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
