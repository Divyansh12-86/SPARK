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

endpackage
