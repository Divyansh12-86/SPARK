# ============================================================================
# File:        run_uart.do
# Project:     SPARK
# Description: Questa simulation script for UART unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/periph/uart.sv \
    ../tb/unit/tb_uart.sv

vsim -t 1ns -voptargs="+acc" work.tb_uart

run -all

if {[batch_mode]} {
    quit -f
}
