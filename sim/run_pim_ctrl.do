vlib work
vlog -work work -sv +incdir+../rtl/pkg ../rtl/pkg/riscv_pkg.sv ../rtl/pim/pim_buffer.sv ../rtl/pim/pim_simd_alu.sv ../rtl/pim/pim_ctrl.sv ../tb/unit/tb_pim_ctrl.sv
vsim -c -voptargs="+acc" work.tb_pim_ctrl -do "run -all; quit -f"
