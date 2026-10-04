vlib work
vlog -work work -sv ../rtl/periph/vga_ctrl.sv ../tb/unit/tb_vga_ctrl.sv
vsim -c -voptargs="+acc" work.tb_vga_ctrl -do "run -all; quit -f"
