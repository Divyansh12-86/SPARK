# SPARK: SystemVerilog Processor Architecture for RISC-V Kernel-boot

SPARK is an open-source, 32-bit RISC-V (RV32I) processor core and System-on-Chip (SoC) architecture implemented from scratch in synthesizable SystemVerilog.

The project is architected with a staged development trajectory: transitioning from a pedagogical single-cycle implementation to an out-of-order-ready 5-stage pipeline, integrating privileged modes and memory-mapped peripherals to boot MIT's xv6 operating system, and culminating in a custom Processing-In-Memory (PIM) ISA extension for hardware-accelerated memory-bound operations.

---

## Architecture Overview

### Core Specifications
- **Instruction Set Architecture (ISA):** RV32I Base Integer Instruction Set (32-bit registers, 32-bit address space).
- **Register File:** 32 standard general-purpose registers (x0-x31), with x0 hardwired to constant zero.
- **Pipeline Structure:** Classical 5-stage pipeline (Fetch, Decode, Execute, Memory, Writeback).
- **Hazard Handling:** Full data forwarding unit (EX-to-EX, MEM-to-EX) and load-use hazard stall unit.
- **Control Hazards:** Speculative branch execution with pipeline flush on branch misprediction.
- **Privilege Levels:** Machine Mode (M-mode) and Supervisor Mode (S-mode) with trap handling logic.
- **Custom Extensions:** Custom-1 reserved opcode (`0b0101011`) implementing vector Processing-In-Memory (PIM) instructions.

### Memory Map

| Address Range | Size | Destination / Device | Description |
| :--- | :--- | :--- | :--- |
| `0x0000_0000 - 0x0FFF_FFFF` | 256 MB | Instruction ROM | Initial boot code and firmware |
| `0x1000_0000 - 0x1000_00FF` | 256 B | UART | 16550-compatible serial communication |
| `0x2000_0000 - 0x2000_FFFF` | 64 KB | CLINT | Core Local Interruptor (mtime, mtimecmp) |
| `0x8000_0000 - 0x87FF_FFFF` | 128 MB | Main Memory (RAM) | Execution memory (Kernel + User space) |
| `0xC000_0000 - 0xC000_FFFF` | 64 KB | PLIC | Platform-Level Interrupt Controller |
| `0xF000_0000 - 0xF001_2BFF` | 75 KB | Framebuffer | 320x240 8-bit software-rendered display |

---

## Processing-In-Memory (PIM) Extension

Traditional von Neumann architectures encounter the memory wall: transferring data between off-chip DRAM and the processor consumes an overwhelming fraction of execution time and energy.

SPARK integrates dedicated compute units directly adjacent to the memory array to execute data-parallel vector kernels without saturating the system bus:

```
+----------------+                +-------------------------+
|                |  Instruction   |   PIM Memory Subsystem  |
|   SPARK Core   |--------------->|  +-------------------+  |
|                |  (Custom-1)    |  | Vector Execution  |  |
|  Pipeline EX   |                |  | Logic (ALU/MAC)   |  |
|                |<---------------|  +-------------------+  |
+----------------+  Done / Result |  | Memory Array Rows |  |
                                  |  +-------------------+  |
                                  +-------------------------+
```

### Supported Custom PIM Instructions
All PIM instructions utilize the standard RISC-V `custom-1` opcode (`0b0101011`):
- `pim.vadd rd, rs1, rs2`: Parallel vector addition across designated memory rows.
- `pim.vmac rd, rs1, rs2`: Vector multiply-accumulate (matrix/dot product kernel).
- `pim.vand rd, rs1, rs2`: Bitwise parallel AND across memory regions.
- `pim.vsum rd, rs1`: Row/matrix reduction sum.
- `pim.cfg rs1, imm`: Configure array base address, vector stride, and operation length.
- `pim.vfill rs1, imm, len`: Bulk-fill memory ranges (high-speed framebuffer clears and memory initialization).

---

## Verification Methodology

SPARK employs a dual-simulator verification strategy balancing granular waveform inspection with high-throughput full-system simulation:

1. **Unit Verification (Siemens QuestaSim):**
   - Pure SystemVerilog self-checking testbenches.
   - Comprehensive edge-case coverage and assert-based verification (SVA).
   - Automated regression scripts using Tcl (`run.do`) with preserved full-signal visibility (`-voptargs="+acc"`).

2. **Linting and Static Analysis (Verilator):**
   - Strict compiler warnings enabled (`-Wall -Wno-DECLFILENAME --timing`).
   - Early detection of inferred latches, incomplete case expressions, and bus width mismatches.

3. **System Simulation (Verilator + cocotb / Python):**
   - High-performance C++ compilation for multi-million-cycle simulations required to boot xv6.
   - Asynchronous Python test harness via VPI (Verilog Procedural Interface) to observe UART traffic and render the simulated framebuffer window.

---

## Project Structure

```
SPARK/
├── .vscode/             # Editor exclusions and TerosHDL configuration
├── docs/                # Architecture specifications and memory maps
├── rtl/                 # Synthesizable SystemVerilog RTL
│   ├── core/            # ALU, Register File, Pipeline Registers, Control Unit
│   ├── periph/          # UART, CLINT, PLIC, Display Controller
│   ├── pim/             # PIM Controller, ALU, and specialized memory arrays
│   └── top/             # CPU top and SoC top integration
├── tb/                  # Self-checking SystemVerilog testbenches
│   ├── unit/            # Module-level unit tests
│   └── system/          # Top-level integration testbenches
├── sim/                 # Simulation automation scripts (Tcl / DO files)
├── sw/                  # Assembly micro-tests, xv6 port, and bare-metal benchmarks
└── scripts/             # Build and regression automation
```

---

## Roadmap

### Phase 1: Single-Cycle RV32I Processor
- [ ] RV32I Arithmetic Logic Unit (`alu.sv`) and self-checking testbench
- [ ] 32x32-bit Register File with hardwired x0 zero register (`reg_file.sv`)
- [ ] Immediate Generation Unit covering R, I, S, B, U, J formats (`imm_gen.sv`)
- [ ] Main Control and ALU Control decoders (`ctrl_unit.sv`, `alu_ctrl.sv`)
- [ ] Program Counter and Memory interface integration (`cpu_single.sv`)
- [ ] Validation against standard RISC-V assembly compliance suites

### Phase 2: 5-Stage Pipelined Processor
- [ ] Inter-stage Pipeline Registers (`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`)
- [ ] Forwarding Unit for Data Hazards (RAW hazard resolution)
- [ ] Hazard Detection Unit for Load-Use Stalls
- [ ] Branch Misprediction Recovery and Pipeline Flush logic

### Phase 3: Privileged Architecture and CSR Support
- [ ] Control and Status Register File (`csr_file.sv`)
- [ ] Machine and Supervisor mode trap delegation and status registers
- [ ] Custom instruction decoding pipeline hook

### Phase 4: SoC Infrastructure and Bus Interconnect
- [ ] Address decoder and crossbar interconnect
- [ ] 16550-compatible UART transmitter
- [ ] Core Local Interruptor (CLINT) timer implementation
- [ ] Platform-Level Interrupt Controller (PLIC)

### Phase 5: Operating System Boot
- [ ] Port and configure MIT xv6-riscv for RV32 execution
- [ ] High-speed Verilator SoC simulation harness
- [ ] Interactive terminal boot via simulated UART

### Phase 6: PIM Extension Implementation and Benchmarking
- [ ] PIM Memory Controller FSM and compute array
- [ ] Vector addition, reduction, and matrix-vector benchmarks
- [ ] Cycle count and bus transaction comparative analysis (CPU vs PIM)

### Phase 7: Software-Rendered Display Controller
- [ ] Minimal memory-mapped display controller (`vga_ctrl.sv`)
- [ ] Framebuffer rendering integration with Python GUI harness
- [ ] Hardware-accelerated memory fill demonstration

---

## Getting Started

### Prerequisites
- Siemens QuestaSim / ModelSim (`vlog`, `vsim`)
- Verilator (version 5.0 or later)
- GTKWave
- Python 3.10+ (for cocotb test harnesses)
- GNU Make

### Running Unit Simulations (QuestaSim)
Simulations are executed via Questa batch or GUI mode. Navigate to the simulation directory and execute the target test script:

```bash
cd sim
vsim -c -do run_alu.do
```

To open QuestaSim with GUI and waveform inspection:
```bash
vsim -gui -do run_alu.do
```

### Static Linting (Verilator)
Run static analysis across all RTL sources:
```bash
verilator --lint-only -Wall -Wno-DECLFILENAME rtl/core/*.sv
```

---

## References and Standards
- The RISC-V Instruction Set Manual, Volume I: User-Level ISA (Document Version 20191213)
- The RISC-V Instruction Set Manual, Volume II: Privileged Architecture (Document Version 20211203)
- IEEE Standard for SystemVerilog (IEEE Std 1800-2017)
- MIT xv6-riscv Operating System
