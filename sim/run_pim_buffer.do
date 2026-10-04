vlib work
vlog -work work -sv ../rtl/pim/pim_buffer.sv ../tb/unit/tb_pim_buffer.sv
vsim -c -voptargs="+acc" work.tb_pim_buffer -do "run -all; quit -f"
