# ============================================================================
# Makefile:    SPARK Verilator High-Speed Simulation & Co-Simulation
# Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
# ============================================================================

VERILATOR = verilator
CXX = g++
CXXFLAGS = -O3 -std=c++17 -Wall

# Source directories
RTL_DIR = ../rtl
SIM_DIR = .
OBJ_DIR = $(SIM_DIR)/obj_dir

SDL_CFLAGS = $(shell sdl2-config --cflags 2>/dev/null)
SDL_LDFLAGS = $(shell sdl2-config --libs 2>/dev/null)

# Verilator lint and compilation flags
VFLAGS = --cc --exe --timing -Wall \
         -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-MULTITOP -Wno-WIDTHEXPAND \
         -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL \
         -I$(RTL_DIR)/pkg \
         -CFLAGS "-std=c++17 -O3 $(SDL_CFLAGS)" \
         -LDFLAGS "$(SDL_LDFLAGS)" \
         --Mdir $(OBJ_DIR) \
         --top-module spark_soc_top

# RTL sources
SRCS = $(RTL_DIR)/pkg/riscv_pkg.sv \
       $(RTL_DIR)/core/alu.sv \
       $(RTL_DIR)/core/reg_file.sv \
       $(RTL_DIR)/core/imm_gen.sv \
       $(RTL_DIR)/core/ctrl_unit.sv \
       $(RTL_DIR)/core/alu_ctrl.sv \
       $(RTL_DIR)/core/branch_unit.sv \
       $(RTL_DIR)/core/pc_reg.sv \
       $(RTL_DIR)/core/instr_mem.sv \
       $(RTL_DIR)/core/data_mem.sv \
       $(RTL_DIR)/core/if_id_reg.sv \
       $(RTL_DIR)/core/id_ex_reg.sv \
       $(RTL_DIR)/core/ex_mem_reg.sv \
       $(RTL_DIR)/core/mem_wb_reg.sv \
       $(RTL_DIR)/core/forwarding_unit.sv \
       $(RTL_DIR)/core/hazard_unit.sv \
       $(RTL_DIR)/core/csr_file.sv \
       $(RTL_DIR)/core/trap_ctrl.sv \
       $(RTL_DIR)/core/cpu_pipe.sv \
       $(RTL_DIR)/core/custom_decoder.sv \
       $(RTL_DIR)/periph/uart.sv \
       $(RTL_DIR)/periph/clint.sv \
       $(RTL_DIR)/periph/plic.sv \
       $(RTL_DIR)/periph/ramdisk.sv \
       $(RTL_DIR)/periph/vga_ctrl.sv \
       $(RTL_DIR)/periph/bus_interconnect.sv \
       $(RTL_DIR)/mem/main_ram.sv \
       $(RTL_DIR)/pim/pim_buffer.sv \
       $(RTL_DIR)/pim/pim_simd_alu.sv \
       $(RTL_DIR)/pim/pim_ctrl.sv \
       $(RTL_DIR)/pim/pim_top.sv \
       $(RTL_DIR)/top/spark_soc_top.sv

all: $(OBJ_DIR)/Vspark_soc_top

$(OBJ_DIR)/Vspark_soc_top: $(SRCS) verilator_main.cpp
	$(VERILATOR) $(VFLAGS) $(SRCS) verilator_main.cpp
	$(MAKE) -C $(OBJ_DIR) -f Vspark_soc_top.mk Vspark_soc_top

run: $(OBJ_DIR)/Vspark_soc_top
	./$(OBJ_DIR)/Vspark_soc_top

clean:
	rm -rf $(OBJ_DIR)
