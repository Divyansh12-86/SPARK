# ============================================================================
# File:        run_pc_reg.do
# Project:     SPARK
# Description: Questa simulation script for Program Counter Register unit test.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/core/pc_reg.sv \
    ../tb/unit/tb_pc_reg.sv

vsim -t 1ns -voptargs="+acc" work.tb_pc_reg

if {[batch_mode] == 0} {
    add wave -divider "Clock & Reset"
    add wave /tb_pc_reg/clk
    add wave /tb_pc_reg/rst_n

    add wave -divider "Control"
    add wave /tb_pc_reg/en

    add wave -divider "PC Values"
    add wave -hex /tb_pc_reg/pc_next
    add wave -hex /tb_pc_reg/pc

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
