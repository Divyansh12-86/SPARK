# ============================================================================
# File:        run_reg_file.do
# Project:     SPARK
# Description: Questa simulation script for the Register File unit test.
#
# Usage:
#   cd sim && vsim -c -do run_reg_file.do
#   cd sim && vsim -gui -do run_reg_file.do
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/core/reg_file.sv \
    ../tb/unit/tb_reg_file.sv

vsim -t 1ns -voptargs="+acc" work.tb_reg_file

if {[batch_mode] == 0} {
    add wave -divider "Clock/Reset"
    add wave /tb_reg_file/clk
    add wave /tb_reg_file/rst_n

    add wave -divider "Write Port"
    add wave /tb_reg_file/wr_en
    add wave -unsigned /tb_reg_file/rd_addr
    add wave -hex /tb_reg_file/rd_data

    add wave -divider "Read Port 1"
    add wave -unsigned /tb_reg_file/rs1_addr
    add wave -hex /tb_reg_file/rs1_data

    add wave -divider "Read Port 2"
    add wave -unsigned /tb_reg_file/rs2_addr
    add wave -hex /tb_reg_file/rs2_data

    wave zoom full
}

run -all

if {[batch_mode]} {
    quit -f
}
