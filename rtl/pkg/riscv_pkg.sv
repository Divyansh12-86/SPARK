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
        WB_SRC_PC4  = 2'b10   // Write PC+4 (return addr)(JAL, JALR)
    } wb_src_t;

endpackage
