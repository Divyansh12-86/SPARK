vlib work
vlog -work work -sv +incdir+../rtl/pkg ../rtl/pkg/riscv_pkg.sv ../rtl/pim/pim_simd_alu.sv ../tb/unit/tb_pim_simd_alu.sv
vsim -c -voptargs="+acc" work.tb_pim_simd_alu -do "run -all; quit -f"
