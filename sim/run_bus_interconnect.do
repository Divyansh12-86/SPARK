# ============================================================================
# File:        run_bus_interconnect.do
# Project:     SPARK
# Description: Questa simulation script for Bus Interconnect unit tests.
# ============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -sv17compat -timescale 1ns/1ps -suppress 2902 \
    ../rtl/periph/bus_interconnect.sv \
    ../tb/unit/tb_bus_interconnect.sv

vsim -t 1ns -voptargs="+acc" work.tb_bus_interconnect

run -all

if {[batch_mode]} {
    quit -f
}
