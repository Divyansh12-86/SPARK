vlib work
vlog -work work -sv +incdir+../rtl/pkg ../rtl/pkg/riscv_pkg.sv \
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
    ../rtl/core/custom_decoder.sv \
    ../rtl/periph/uart.sv \
    ../rtl/periph/clint.sv \
    ../rtl/periph/plic.sv \
    ../rtl/periph/ramdisk.sv \
    ../rtl/periph/vga_ctrl.sv \
    ../rtl/periph/bus_interconnect.sv \
    ../rtl/mem/main_ram.sv \
    ../rtl/pim/pim_buffer.sv \
    ../rtl/pim/pim_simd_alu.sv \
    ../rtl/pim/pim_ctrl.sv \
    ../rtl/pim/pim_top.sv \
    ../rtl/top/spark_soc_top.sv \
    ../tb/system/tb_spark_soc_top.sv

vsim -c -voptargs="+acc" work.tb_spark_soc_top -do "run -all; quit -f"
