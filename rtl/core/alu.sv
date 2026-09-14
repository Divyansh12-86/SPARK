// ============================================================================
// File:        alu.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: 32-bit Arithmetic Logic Unit (ALU) for the RV32I base integer
//              instruction set.
//
//              This is a pure combinational block — it contains no flip-flops,
//              no clock, and no state. Given two 32-bit inputs and an operation
//              selector, it produces a 32-bit result and a zero flag within the
//              same clock cycle (zero latency).
//
//              In the processor datapath, this module sits in the Execution (EX)
//              stage. Its inputs come from the Register File (operand A = rs1)
//              and either the Register File (operand B = rs2, for R-type
//              instructions) or the Immediate Generator (operand B = sign-
//              extended immediate, for I-type instructions). The mux selecting
//              between rs2 and the immediate is external to this module.
//
//              The zero flag output is used by the branch comparison logic:
//              BEQ branches when zero==1 (subtraction result is 0, meaning
//              the two operands are equal), BNE branches when zero==0.
// ============================================================================

// Import the shared definitions package so we can use the alu_op_t type.
// The wildcard import (::*) brings all names from riscv_pkg into this module's
// scope. Placing the import INSIDE the module (not at file scope) prevents
// polluting the global compilation namespace — Verilator's IMPORTSTAR warning
// catches this if you put it outside. This matters when dozens of modules are
// compiled together: a file-scope import in one file can silently shadow names
// in another file, causing hard-to-trace bugs.

module alu
    import riscv_pkg::*;
(
    // ---- Inputs ----
    input  logic [31:0] a,       // Operand A (from register rs1)
    input  logic [31:0] b,       // Operand B (from rs2 or sign-extended immediate)
    input  alu_op_t     alu_op,  // Operation selector (from ALU Control unit)

    // ---- Outputs ----
    output logic [31:0] result,  // Computation result (32 bits)
    output logic        zero     // Zero flag: HIGH when result == 0
);

    // ========================================================================
    // Combinational Operation Selection
    // ========================================================================
    //
    // always_comb vs always @(*):
    //   Both describe combinational logic (no clock). The critical difference:
    //   - always @(*) is legacy Verilog. If you forget a case in a case
    //     statement and omit a default, the simulator silently infers a
    //     transparent LATCH (a storage element) — your "combinational" block
    //     secretly becomes sequential, breaking timing analysis and producing
    //     hardware you never intended.
    //   - always_comb is SystemVerilog. It tells the compiler: "This block
    //     MUST be purely combinational. If any code path can leave 'result'
    //     unassigned, throw a compile-time error." Verilator will emit
    //     CASEINCOMPLETE or LATCHINFERRED warnings. Questa will produce a
    //     similar diagnostic. This is your first line of defense against one
    //     of the most common RTL bugs in the industry.
    //
    // Why case/inside instead of if-else:
    //   A case statement maps naturally to a hardware multiplexer — one
    //   parallel selector choosing among multiple data paths. An if-else
    //   chain implies priority logic (a cascaded chain of muxes), which is
    //   slower and uses more gates. For an ALU where all operations are
    //   mutually exclusive and equal priority, case is the correct construct.
    //
    //   The 'inside' keyword (SystemVerilog) allows set-membership matching
    //   and handles 'x'/'z' values more gracefully than plain 'case'. For
    //   enum-based selectors it also suppresses certain spurious warnings
    //   about comparison with don't-care values.
    // ========================================================================

    always_comb begin
        // Default assignment: if no case matches (should never happen with a
        // complete enum, but defensive coding prevents latch inference if the
        // enum is ever extended without updating this block).
        result = 32'b0;

        case (alu_op) inside
            // ----------------------------------------------------------------
            // Arithmetic Operations
            // ----------------------------------------------------------------

            ALU_ADD: result = a + b;
            // Hardware: a 32-bit ripple-carry or carry-lookahead adder.
            // This is the most heavily used ALU operation — it serves ADD,
            // ADDI, and is also reused for address calculation in loads,
            // stores, JAL, JALR, AUIPC, and branch target computation.

            ALU_SUB: result = a - b;
            // Hardware: subtraction is implemented as a + (~b) + 1 (two's
            // complement negation). In practice, the synthesizer shares the
            // same adder hardware between ADD and SUB by XOR-ing operand B
            // with a subtract-select signal and feeding a carry-in of 1.
            // This means ADD and SUB do NOT require two separate adders —
            // they share one adder with a conditional invert on the B input.

            // ----------------------------------------------------------------
            // Bitwise Logical Operations
            // ----------------------------------------------------------------

            ALU_AND: result = a & b;
            // Hardware: 32 independent 2-input AND gates (one per bit).
            // Each output bit depends only on the corresponding input bits —
            // no carry propagation, making this the fastest ALU operation
            // (shortest combinational delay).

            ALU_OR:  result = a | b;
            // Hardware: 32 independent 2-input OR gates.

            ALU_XOR: result = a ^ b;
            // Hardware: 32 independent 2-input XOR gates.
            // XOR has a useful property: a ^ b == 0 if and only if a == b.
            // Some CPU designs use XOR + OR-reduction instead of a subtractor
            // for equality comparison (BEQ/BNE), since XOR is faster than
            // subtraction (no carry chain). We use subtraction here for
            // generality, but this is a valid microarchitectural optimization.

            // ----------------------------------------------------------------
            // Shift Operations
            // ----------------------------------------------------------------
            //
            // All shifts use only b[4:0] (the lower 5 bits of operand B) as
            // the shift amount. Why 5 bits? Because the maximum meaningful
            // shift for a 32-bit value is 31 positions, and 2^5 = 32 covers
            // the range 0..31. The upper 27 bits of B are ignored by hardware.
            //
            // In real silicon, shifts are implemented using a BARREL SHIFTER:
            // a logarithmic network of multiplexers. A 32-bit barrel shifter
            // uses 5 stages of muxes (one per shift-amount bit), each stage
            // conditionally shifting by 1, 2, 4, 8, or 16 positions. Total
            // delay: 5 mux delays (much faster than shifting one position at
            // a time in a loop, which would take up to 31 cycles).
            // ----------------------------------------------------------------

            ALU_SLL: result = a << b[4:0];
            // Shift Left Logical: vacated positions on the right are filled
            // with zeros. Equivalent to multiplying by 2^(shift amount) for
            // unsigned numbers.

            ALU_SRL: result = a >> b[4:0];
            // Shift Right Logical: vacated positions on the left are filled
            // with zeros. Equivalent to unsigned integer division by
            // 2^(shift amount), discarding the remainder.

            ALU_SRA: result = $signed(a) >>> b[4:0];
            // Shift Right Arithmetic: vacated positions on the left are
            // filled with copies of the SIGN BIT (a[31]).
            //
            // CRITICAL SYSTEMVERILOG DETAIL:
            //   The >>> operator ONLY performs an arithmetic (sign-extending)
            //   shift when the left operand is a SIGNED type. If 'a' is
            //   declared as plain 'logic [31:0]' (which is unsigned by
            //   default), then >>> behaves IDENTICALLY to >> (logical shift).
            //   This is a silent, legal behavior — no warning, no error.
            //
            //   The $signed() system function casts 'a' to a signed
            //   interpretation for this expression only. It does NOT change
            //   the actual bits or the port declaration — it only tells the
            //   operator how to treat the MSB during the shift.
            //
            //   Example (8-bit for clarity):
            //     a = 8'b1000_0100 (unsigned: 132, signed: -124)
            //     Logical  shift right by 2: 8'b0010_0001 (33)  — zeros fill
            //     Arithmetic shift right by 2: 8'b1110_0001 (-31) — sign fills
            //
            //   Getting this wrong is a real, common RTL bug. It produces
            //   correct results for positive numbers (sign bit is 0, so
            //   zero-fill and sign-fill are identical) but silently breaks
            //   for negative numbers — the kind of bug that passes 90% of
            //   tests and fails in production.

            // ----------------------------------------------------------------
            // Comparison Operations (Set Less Than)
            // ----------------------------------------------------------------
            //
            // These produce a 1-bit result (0 or 1) zero-extended to 32 bits.
            // The RISC-V spec requires the result to be written to a full
            // 32-bit register (rd), with the comparison outcome in bit 0 and
            // bits [31:1] all zero.
            // ----------------------------------------------------------------

            ALU_SLT: result = {31'b0, $signed(a) < $signed(b)};
            // Signed comparison. $signed() casts both operands so the '<'
            // operator uses signed (two's complement) comparison logic.
            //
            // The concatenation {31'b0, <1-bit result>} zero-extends the
            // single comparison bit to fill the full 32-bit result bus.
            //
            // Hardware: the synthesizer implements signed comparison using
            // a subtractor and examining the Negative (N) and Overflow (V)
            // flags of the result. The rule is:
            //   signed_less_than = N XOR V
            // This correctly handles all four sign combinations (+/+, +/-,
            // -/+, -/-) including overflow cases.

            ALU_SLTU: result = {31'b0, a < b};
            // Unsigned comparison. Plain '<' on unsigned operands compares
            // magnitudes directly. 0xFFFFFFFF (4,294,967,295) is GREATER
            // than 0x00000001 (1) in unsigned, but LESS in signed (-1 < 1).

            // ----------------------------------------------------------------
            // Default Case (Defensive)
            // ----------------------------------------------------------------
            default: result = 32'b0;
            // This should never be reached if alu_op is properly driven by
            // the ALU Control unit. Its purpose is purely defensive: it
            // guarantees that 'result' is assigned on every possible code
            // path, which prevents the synthesizer from inferring a latch.
            // If this default ever fires during simulation, it indicates a
            // bug in the control logic upstream.
        endcase
    end

    // ========================================================================
    // Zero Flag Generation
    // ========================================================================
    //
    // Continuous assignment (assign) is used here instead of putting this
    // inside the always_comb block. Why?
    //   - The zero flag depends solely on 'result', not on 'alu_op' or the
    //     inputs directly. It is a simple derived signal.
    //   - Using 'assign' makes this dependency explicit and separate from
    //     the operation-selection logic, improving readability.
    //   - Both approaches (assign vs. inside always_comb) produce identical
    //     hardware: a 32-input NOR gate (or equivalently, a 32-input OR
    //     gate feeding an inverter). The output is HIGH only when every
    //     single bit of 'result' is zero.
    //
    // The reduction OR operator (|result) ORs all 32 bits of 'result' into
    // a single bit: it is 1 if ANY bit is set, 0 only if ALL bits are zero.
    // The ~ inverts this: zero==1 when result==0, zero==0 otherwise.
    // ========================================================================

    assign zero = ~(|result);

endmodule
