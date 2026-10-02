// ============================================================================
// File:        riscv_pkg.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Shared type and constant definitions used across all RTL modules.
//              This package is the single source of truth for operation encodings,
//              bus widths, and other architectural constants. It produces zero
//              hardware — all values are resolved at compile time by the
//              synthesizer/simulator before any gates are inferred.
// ============================================================================

package riscv_pkg;

    // ========================================================================
    // ALU Operation Codes
    // ========================================================================
    //
    // These 4-bit codes are produced by the ALU Control unit (alu_ctrl.sv,
    // built in a later step) and consumed by the ALU (alu.sv) to select which
    // computation to perform on its two 32-bit inputs.
    //
    // Why 4 bits?
    //   RV32I requires 10 distinct ALU operations. To uniquely encode 10
    //   operations, we need ceil(log2(10)) = 4 bits (4 bits can represent
    //   0..15, giving us room for 10 operations with 6 unused codes).
    //
    // Why a typedef enum instead of `localparam`?
    //   - `localparam` defines a bare numeric constant. The simulator and
    //     waveform viewer show the raw number (e.g., 4'b0110), which is
    //     meaningless to a human debugging a waveform at 2 AM.
    //   - `typedef enum` gives each value a symbolic name. QuestaSim and
    //     GTKWave will display "ALU_XOR" instead of "0110" on the waveform,
    //     making the operation instantly readable during waveform inspection.
    //   - The `logic [3:0]` base type explicitly tells the synthesizer that
    //     the underlying hardware representation is a 4-bit bus. Without it,
    //     SystemVerilog defaults to `int` (32 bits), which wastes 28 bits of
    //     wire in synthesis and creates unnecessarily wide muxes.
    //
    // The specific bit patterns (0000, 0001, ...) are arbitrary — the ALU
    // Control unit is responsible for mapping RISC-V instruction fields
    // (funct3, funct7) to these codes. We chose sequential numbering for
    // simplicity; some designs use funct3-aligned encodings to minimize
    // decode logic, but that is a microarchitectural optimization, not a
    // correctness concern.
    // ========================================================================

    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,  // Addition:              result = a + b
        ALU_SUB  = 4'b0001,  // Subtraction:           result = a - b
        ALU_AND  = 4'b0010,  // Bitwise AND:           result = a & b
        ALU_OR   = 4'b0011,  // Bitwise OR:            result = a | b
        ALU_XOR  = 4'b0100,  // Bitwise XOR:           result = a ^ b
        ALU_SLL  = 4'b0101,  // Shift Left Logical:    result = a << b[4:0]
        ALU_SRL  = 4'b0110,  // Shift Right Logical:   result = a >> b[4:0]
        ALU_SRA  = 4'b0111,  // Shift Right Arithmetic:result = a >>> b[4:0]
        ALU_SLT  = 4'b1000,  // Set Less Than (Signed):   result = ($signed(a) < $signed(b)) ? 1 : 0
        ALU_SLTU = 4'b1001   // Set Less Than (Unsigned): result = (a < b) ? 1 : 0
    } alu_op_t;

    // ========================================================================
    // RV32I Opcode Constants (instr[6:0])
    // ========================================================================
    //
    // These 7-bit values identify the instruction format and general category.
    // Used by the Immediate Generator, Control Unit, and ALU Control to
    // decode instructions. Defined as localparam (compile-time constants)
    // rather than enum because opcodes are compared against raw instruction
    // bits, not passed as typed signals between modules.
    // ========================================================================

    localparam logic [6:0] OP_R_TYPE  = 7'b0110011;  // R-type ALU (add, sub, and, or, xor, sll, srl, sra, slt, sltu)
    localparam logic [6:0] OP_I_ALU   = 7'b0010011;  // I-type ALU (addi, andi, ori, xori, slli, srli, srai, slti, sltiu)
    localparam logic [6:0] OP_LOAD    = 7'b0000011;  // I-type Load (lb, lh, lw, lbu, lhu)
    localparam logic [6:0] OP_STORE   = 7'b0100011;  // S-type Store (sb, sh, sw)
    localparam logic [6:0] OP_BRANCH  = 7'b1100011;  // B-type Branch (beq, bne, blt, bge, bltu, bgeu)
    localparam logic [6:0] OP_JAL     = 7'b1101111;  // J-type Jump and Link
    localparam logic [6:0] OP_JALR    = 7'b1100111;  // I-type Jump and Link Register
    localparam logic [6:0] OP_LUI     = 7'b0110111;  // U-type Load Upper Immediate
    localparam logic [6:0] OP_AUIPC   = 7'b0010111;  // U-type Add Upper Immediate to PC
    localparam logic [6:0] OP_SYSTEM  = 7'b1110011;  // System (ecall, ebreak, CSR instructions)
    localparam logic [6:0] OP_CUSTOM1 = 7'b0101011;  // Custom-1 (PIM extension, Phase 6)

    // ========================================================================
    // Control Unit Output Types
    // ========================================================================
    //
    // Typed enums for the two mux selects driven by the Control Unit.
    // Using enums (instead of bare 1-bit/2-bit logic) makes the signal
    // intent self-documenting in waveforms and port declarations.
    // ========================================================================

    // ALU source B mux: selects between register rs2 data and the
    // sign-extended immediate as operand B into the ALU.
    typedef enum logic {
        ALU_SRC_REG = 1'b0,  // Operand B = register rs2 data   (R-type)
        ALU_SRC_IMM = 1'b1   // Operand B = sign-extended imm   (I/S/B/U/J-type)
    } alu_src_t;

    // Writeback source mux: selects what is written back to the register file.
    typedef enum logic [1:0] {
        WB_SRC_ALU  = 2'b00,  // Write ALU result        (R-type, I-ALU, LUI, AUIPC)
        WB_SRC_MEM  = 2'b01,  // Write memory read data  (Load instructions)
        WB_SRC_PC4  = 2'b10,  // Write PC+4 (return addr)(JAL, JALR)
        WB_SRC_CSR  = 2'b11   // Write CSR read data     (CSR instructions)
    } wb_src_t;

    // ========================================================================
    // Privilege Levels
    // ========================================================================
    localparam logic [1:0] PRIV_U = 2'b00;  // User mode
    localparam logic [1:0] PRIV_S = 2'b01;  // Supervisor mode (xv6 kernel)
    localparam logic [1:0] PRIV_M = 2'b11;  // Machine mode (boot / physical hardware)

    // ========================================================================
    // CSR Addresses (12-bit)
    // ========================================================================
    // Machine Mode CSRs
    localparam logic [11:0] CSR_MSTATUS   = 12'h300; // Machine status register
    localparam logic [11:0] CSR_MISA      = 12'h301; // Machine ISA features
    localparam logic [11:0] CSR_MEDELEG   = 12'h302; // Machine exception delegation
    localparam logic [11:0] CSR_MIDELEG   = 12'h303; // Machine interrupt delegation
    localparam logic [11:0] CSR_MIE       = 12'h304; // Machine interrupt enable
    localparam logic [11:0] CSR_MTVEC     = 12'h305; // Machine trap-handler base address
    localparam logic [11:0] CSR_MSCRATCH  = 12'h340; // Machine scratch register
    localparam logic [11:0] CSR_MEPC      = 12'h341; // Machine exception PC
    localparam logic [11:0] CSR_MCAUSE    = 12'h342; // Machine trap cause
    localparam logic [11:0] CSR_MTVAL     = 12'h343; // Machine bad address or instruction
    localparam logic [11:0] CSR_MIP       = 12'h344; // Machine interrupt pending
    localparam logic [11:0] CSR_MCYCLE    = 12'hB00; // Machine cycle counter low
    localparam logic [11:0] CSR_MCYCLEH   = 12'hB80; // Machine cycle counter high

    // Supervisor Mode CSRs (for xv6 virtual memory and trap handling)
    localparam logic [11:0] CSR_SSTATUS   = 12'h100; // Supervisor status
    localparam logic [11:0] CSR_SIE       = 12'h104; // Supervisor interrupt enable
    localparam logic [11:0] CSR_STVEC     = 12'h105; // Supervisor trap-handler base
    localparam logic [11:0] CSR_SSCRATCH  = 12'h140; // Supervisor scratch register
    localparam logic [11:0] CSR_SEPC      = 12'h141; // Supervisor exception PC
    localparam logic [11:0] CSR_SCAUSE    = 12'h142; // Supervisor trap cause
    localparam logic [11:0] CSR_STVAL     = 12'h143; // Supervisor trap value
    localparam logic [11:0] CSR_SIP       = 12'h144; // Supervisor interrupt pending
    localparam logic [11:0] CSR_SATP      = 12'h180; // Supervisor address translation & protection

    // ========================================================================
    // CSR Operation Codes (funct3 for SYSTEM instructions)
    // ========================================================================
    localparam logic [2:0] CSR_OP_NONE    = 3'b000;  // ECALL / EBREAK / MRET / SRET
    localparam logic [2:0] CSR_OP_RW      = 3'b001;  // CSRRW:  Atomic Read/Write
    localparam logic [2:0] CSR_OP_RS      = 3'b010;  // CSRRS:  Atomic Read and Set Bits
    localparam logic [2:0] CSR_OP_RC      = 3'b011;  // CSRRC:  Atomic Read and Clear Bits
    localparam logic [2:0] CSR_OP_RWI     = 3'b101;  // CSRRWI: Atomic Read/Write Immediate
    localparam logic [2:0] CSR_OP_RSI     = 3'b110;  // CSRRSI: Atomic Read and Set Bits Immediate
    localparam logic [2:0] CSR_OP_RCI     = 3'b111;  // CSRRCI: Atomic Read and Clear Bits Immediate

    // ========================================================================
    // Trap Causes (mcause / scause)
    // ========================================================================
    localparam logic [30:0] INT_M_TIMER    = 31'd7;   // Machine timer interrupt (from CLINT)
    localparam logic [30:0] INT_M_EXTERNAL = 31'd11;  // Machine external interrupt (from PLIC)
    localparam logic [30:0] EXC_ILLEGAL_OP = 31'd2;   // Illegal instruction
    localparam logic [30:0] EXC_BREAKPOINT = 31'd3;   // EBREAK
    localparam logic [30:0] EXC_ECALL_U    = 31'd8;   // ECALL from User mode
    localparam logic [30:0] EXC_ECALL_S    = 31'd9;   // ECALL from Supervisor mode
    localparam logic [30:0] EXC_ECALL_M    = 31'd11;  // ECALL from Machine mode

    // ========================================================================
    // PIM Custom-1 Instructions (Phase 6 preparatory)
    // ========================================================================
    typedef enum logic [2:0] {
        PIM_VADD  = 3'b000,  // Vector addition
        PIM_VMAC  = 3'b001,  // Vector multiply-accumulate
        PIM_VAND  = 3'b010,  // Vector bitwise AND
        PIM_VSUM  = 3'b011,  // Vector reduction sum
        PIM_CFG   = 3'b100,  // Configuration
        PIM_VFILL = 3'b101   // Bulk memory fill
    } pim_op_t;

endpackage
