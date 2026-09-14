// ============================================================================
// File:        tb_alu.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for the RV32I ALU (alu.sv).
//
//              This testbench is NOT synthesizable hardware — it exists only
//              in simulation. It applies directed test vectors to the ALU,
//              compares each output against a pre-computed expected value, and
//              reports PASS/FAIL for every test. At the end, a summary line
//              reports total passed vs total run. If ANY test fails, a non-zero
//              $finish code is returned (useful for automated regression scripts).
//
//              Methodology: Directed testing with deliberate corner-case
//              coverage. Each ALU operation gets multiple test vectors chosen
//              to exercise typical values, boundary conditions, and the exact
//              signed/unsigned edge cases where real ALU bugs manifest.
//
//              Waveform: This testbench generates a VCD dump file (alu_tb.vcd)
//              that can be opened in GTKWave for visual inspection. Questa
//              also captures waveforms in its native WLF format when run with
//              -voptargs="+acc".
// ============================================================================

`timescale 1ns / 1ps
// `timescale sets the simulation time unit and precision.
//   - 1ns: each `#1` delay in this file means 1 nanosecond.
//   - 1ps: the simulator tracks time with picosecond resolution.
// This is a testbench-only directive. Synthesizable RTL should not depend
// on timescale for correctness (real hardware has no concept of simulator
// time steps), but testbenches need it to define meaningful delays between
// stimulus changes so the waveform viewer can display readable transitions.

module tb_alu;

    // ========================================================================
    // Signal Declarations
    // ========================================================================
    //
    // These are the testbench's local signals that connect to the DUT (Device
    // Under Test). They mirror the ALU's port list exactly.
    //
    // Why `logic` and not `reg` or `wire`?
    //   In SystemVerilog, `logic` can be driven by both procedural blocks
    //   (initial/always) and continuous assignments (assign). Since this is a
    //   testbench where we drive inputs from an `initial` block and read
    //   outputs combinationally, `logic` works for everything. Legacy Verilog
    //   would require `reg` for procedurally-driven signals and `wire` for
    //   DUT outputs — SystemVerilog's `logic` eliminates that distinction.
    // ========================================================================

    // DUT input signals (driven by the testbench)
    logic [31:0]          tb_a;
    logic [31:0]          tb_b;
    riscv_pkg::alu_op_t   tb_alu_op;

    // DUT output signals (driven by the ALU, observed by the testbench)
    logic [31:0]          tb_result;
    logic                 tb_zero;

    // ========================================================================
    // Test Tracking Variables
    // ========================================================================
    //
    // These are pure software variables — they exist only in the simulator's
    // memory and have no hardware equivalent. `integer` is a 32-bit signed
    // type used for loop counters and bookkeeping in testbenches.
    // ========================================================================

    integer pass_count;
    integer fail_count;
    integer test_num;

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    //
    // This creates one instance of the ALU module named `dut` and connects
    // the testbench signals to its ports using NAMED PORT CONNECTION.
    //
    // Named connection (.port_name(signal_name)) is always preferred over
    // positional connection in professional RTL because:
    //   - If someone reorders the ports in the module definition, named
    //     connections still work correctly; positional connections silently
    //     connect to the wrong signals.
    //   - It makes the connection self-documenting — you can read which
    //     testbench signal maps to which DUT port without cross-referencing
    //     the module definition.
    // ========================================================================

    alu dut (
        .a      (tb_a),
        .b      (tb_b),
        .alu_op (tb_alu_op),
        .result (tb_result),
        .zero   (tb_zero)
    );

    // ========================================================================
    // Verification Task: check_result
    // ========================================================================
    //
    // A SystemVerilog `task` is a reusable block of procedural code (like a
    // function/subroutine in software). Unlike a `function`, a task CAN
    // contain time-consuming statements (delays, waits) — though this
    // particular task does not use any.
    //
    // Parameters:
    //   test_name    — human-readable label printed in PASS/FAIL messages
    //   expected     — the value we calculated by hand / know to be correct
    //   expected_z   — expected state of the zero flag (1 or 0)
    //
    // The task compares the DUT's actual output against the expected values.
    // On mismatch, it prints the full context (inputs, operation, expected
    // vs actual) so the developer can immediately see what went wrong without
    // needing to open a waveform viewer.
    // ========================================================================

    task check_result(
        input string       test_name,
        input logic [31:0] expected,
        input logic        expected_z
    );
        test_num++;

        if (tb_result !== expected || tb_zero !== expected_z) begin
            // !== is the 4-state inequality operator. Unlike !=, it treats
            // x and z as distinct values rather than "unknown". If the DUT
            // outputs x (uninitialized), != would return x (unknown), which
            // an if-statement treats as false — silently hiding the bug.
            // !== returns 1 (true) when values differ, even if one is x.
            // This is critical: an x in the output MUST be caught as a failure.
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Inputs:   a = 0x%08h, b = 0x%08h, op = %s",
                     tb_a, tb_b, tb_alu_op.name());
            $display("         Expected: result = 0x%08h, zero = %0b",
                     expected, expected_z);
            $display("         Actual:   result = 0x%08h, zero = %0b",
                     tb_result, tb_zero);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s", test_num, test_name);
            pass_count++;
        end
    endtask

    // ========================================================================
    // Stimulus Application Task: apply_and_check
    // ========================================================================
    //
    // This task sets the DUT inputs, waits for the combinational logic to
    // settle, then calls check_result.
    //
    // The #10 delay (10 nanoseconds) is a SIMULATION ARTIFACT, not a real
    // hardware timing constraint. Combinational logic in real silicon settles
    // in picoseconds to low nanoseconds (depending on gate count and
    // technology node). The delay here serves two purposes:
    //   1. It gives the simulator time to propagate values through the DUT
    //      before we sample the outputs (without a delay, the simulator
    //      might check outputs before evaluating the combinational logic
    //      in the same simulation time step — a delta-cycle race).
    //   2. It creates visible transitions in the waveform viewer, making
    //      each test vector distinguishable when inspecting the VCD file.
    // ========================================================================

    task apply_and_check(
        input logic [31:0]       a_val,
        input logic [31:0]       b_val,
        input riscv_pkg::alu_op_t op_val,
        input string             test_name,
        input logic [31:0]       expected,
        input logic              expected_z
    );
        tb_a      = a_val;
        tb_b      = b_val;
        tb_alu_op = op_val;
        #10;  // Wait for combinational propagation
        check_result(test_name, expected, expected_z);
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    //
    // `initial` blocks execute once at simulation time 0 and run sequentially
    // (top to bottom). They are testbench-only constructs — synthesis tools
    // ignore them entirely. In a testbench, the initial block is where you
    // apply your stimulus sequence.
    //
    // Each test vector is documented with:
    //   - The operation being tested
    //   - Why this specific input combination was chosen
    //   - The hand-calculated expected result
    // ========================================================================

    initial begin
        // VCD waveform dump for GTKWave
        // $dumpfile specifies the output filename. $dumpvars(0, tb_alu)
        // dumps ALL signals in the tb_alu hierarchy (the 0 means "all
        // levels of hierarchy below this module"). This captures both
        // testbench signals and DUT internal signals.
        $dumpfile("alu_tb.vcd");
        $dumpvars(0, tb_alu);

        // Initialize counters
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK ALU Testbench — Directed Self-Checking Tests");
        $display("==========================================================");

        // ================================================================
        // ADD Tests (ALU_ADD = 4'b0000)
        // ================================================================
        $display("");
        $display("--- ADD ---");

        // Test 1: Basic addition
        // 5 + 3 = 8. Simplest case, verifies the adder works at all.
        apply_and_check(32'd5, 32'd3, riscv_pkg::ALU_ADD,
                        "ADD: 5 + 3 = 8",
                        32'd8, 1'b0);

        // Test 2: Addition producing zero
        // 0 + 0 = 0. Zero flag must assert (zero == 1).
        apply_and_check(32'd0, 32'd0, riscv_pkg::ALU_ADD,
                        "ADD: 0 + 0 = 0 (zero flag)",
                        32'd0, 1'b1);

        // Test 3: Signed overflow wrap-around
        // 0x7FFFFFFF + 1 = 0x80000000. This is the maximum positive 32-bit
        // signed integer (2,147,483,647) plus 1, which wraps to the most
        // negative signed value (-2,147,483,648). RV32I specifies that
        // integer overflow is silently ignored (no trap, no flag) — the
        // ALU must produce the wrapped result.
        apply_and_check(32'h7FFF_FFFF, 32'd1, riscv_pkg::ALU_ADD,
                        "ADD: 0x7FFFFFFF + 1 = 0x80000000 (signed overflow)",
                        32'h8000_0000, 1'b0);

        // Test 4: Unsigned wrap-around (carry-out)
        // 0xFFFFFFFF + 1 = 0x00000000. Maximum unsigned value (4,294,967,295)
        // plus 1 wraps to 0. The carry-out bit is lost (the ALU has no
        // carry-out port — RV32I does not use it). Zero flag asserts.
        apply_and_check(32'hFFFF_FFFF, 32'd1, riscv_pkg::ALU_ADD,
                        "ADD: 0xFFFFFFFF + 1 = 0x00000000 (unsigned wrap, zero flag)",
                        32'h0000_0000, 1'b1);

        // Test 5: Large value addition
        // 0x12345678 + 0x9ABCDEF0 = 0xACF13568
        apply_and_check(32'h1234_5678, 32'h9ABC_DEF0, riscv_pkg::ALU_ADD,
                        "ADD: 0x12345678 + 0x9ABCDEF0 = 0xACF13568",
                        32'hACF1_3568, 1'b0);

        // ================================================================
        // SUB Tests (ALU_SUB = 4'b0001)
        // ================================================================
        $display("");
        $display("--- SUB ---");

        // Test 6: Basic subtraction
        // 10 - 3 = 7.
        apply_and_check(32'd10, 32'd3, riscv_pkg::ALU_SUB,
                        "SUB: 10 - 3 = 7",
                        32'd7, 1'b0);

        // Test 7: Equal operands produce zero
        // 42 - 42 = 0. This is the hardware basis for BEQ (Branch if Equal):
        // the CPU subtracts the two register values and checks the zero flag.
        apply_and_check(32'd42, 32'd42, riscv_pkg::ALU_SUB,
                        "SUB: 42 - 42 = 0 (zero flag, BEQ basis)",
                        32'd0, 1'b1);

        // Test 8: Subtraction producing underflow
        // 0 - 1 = 0xFFFFFFFF. In unsigned: wraps to max value. In signed:
        // produces -1 (two's complement representation of -1).
        apply_and_check(32'd0, 32'd1, riscv_pkg::ALU_SUB,
                        "SUB: 0 - 1 = 0xFFFFFFFF (underflow / -1)",
                        32'hFFFF_FFFF, 1'b0);

        // Test 9: Large difference
        // 0x80000000 - 0x00000001 = 0x7FFFFFFF
        apply_and_check(32'h8000_0000, 32'h0000_0001, riscv_pkg::ALU_SUB,
                        "SUB: 0x80000000 - 1 = 0x7FFFFFFF",
                        32'h7FFF_FFFF, 1'b0);

        // ================================================================
        // AND Tests (ALU_AND = 4'b0010)
        // ================================================================
        $display("");
        $display("--- AND ---");

        // Test 10: Selective bit masking
        // AND is the fundamental masking operation in hardware. Applying a
        // mask of 0x0F0F0F0F to data 0xFF00FF00 selects only the bits where
        // the mask is 1, clearing everything else.
        apply_and_check(32'hFF00_FF00, 32'h0F0F_0F0F, riscv_pkg::ALU_AND,
                        "AND: 0xFF00FF00 & 0x0F0F0F0F = 0x0F000F00",
                        32'h0F00_0F00, 1'b0);

        // Test 11: Complementary patterns produce zero
        // 0xAAAAAAAA = 1010...1010, 0x55555555 = 0101...0101. No bit
        // positions overlap, so AND produces all zeros. Zero flag asserts.
        apply_and_check(32'hAAAA_AAAA, 32'h5555_5555, riscv_pkg::ALU_AND,
                        "AND: 0xAAAAAAAA & 0x55555555 = 0x00000000 (zero flag)",
                        32'h0000_0000, 1'b1);

        // Test 12: AND with all ones (identity)
        // x & 0xFFFFFFFF = x. All-ones mask passes data through unchanged.
        apply_and_check(32'hDEAD_BEEF, 32'hFFFF_FFFF, riscv_pkg::ALU_AND,
                        "AND: 0xDEADBEEF & 0xFFFFFFFF = 0xDEADBEEF (identity)",
                        32'hDEAD_BEEF, 1'b0);

        // ================================================================
        // OR Tests (ALU_OR = 4'b0011)
        // ================================================================
        $display("");
        $display("--- OR ---");

        // Test 13: Complementary patterns produce all ones
        // 0xAAAAAAAA | 0x55555555 = 0xFFFFFFFF. Every bit position has at
        // least one 1 between the two operands.
        apply_and_check(32'hAAAA_AAAA, 32'h5555_5555, riscv_pkg::ALU_OR,
                        "OR: 0xAAAAAAAA | 0x55555555 = 0xFFFFFFFF",
                        32'hFFFF_FFFF, 1'b0);

        // Test 14: OR with zero (identity)
        // x | 0 = x. Zero contributes no bits.
        apply_and_check(32'h1234_5678, 32'h0000_0000, riscv_pkg::ALU_OR,
                        "OR: 0x12345678 | 0x00000000 = 0x12345678 (identity)",
                        32'h1234_5678, 1'b0);

        // Test 15: Both zero
        apply_and_check(32'h0000_0000, 32'h0000_0000, riscv_pkg::ALU_OR,
                        "OR: 0 | 0 = 0 (zero flag)",
                        32'h0000_0000, 1'b1);

        // ================================================================
        // XOR Tests (ALU_XOR = 4'b0100)
        // ================================================================
        $display("");
        $display("--- XOR ---");

        // Test 16: Basic XOR
        apply_and_check(32'hFF00_FF00, 32'h0F0F_0F0F, riscv_pkg::ALU_XOR,
                        "XOR: 0xFF00FF00 ^ 0x0F0F0F0F = 0xF00FF00F",
                        32'hF00F_F00F, 1'b0);

        // Test 17: XOR with itself produces zero
        // This is a fundamental identity: x ^ x = 0 for any x. In RISC-V
        // assembly, `xor rd, rs, rs` is a common idiom for zeroing a
        // register (equivalent to `li rd, 0` but avoids an immediate).
        apply_and_check(32'hDEAD_BEEF, 32'hDEAD_BEEF, riscv_pkg::ALU_XOR,
                        "XOR: 0xDEADBEEF ^ 0xDEADBEEF = 0 (self-XOR, zero flag)",
                        32'h0000_0000, 1'b1);

        // Test 18: XOR with all ones (bitwise NOT / one's complement)
        // x ^ 0xFFFFFFFF flips every bit. This is how RISC-V implements
        // the NOT pseudo-instruction: `xori rd, rs, -1`.
        apply_and_check(32'h0000_0000, 32'hFFFF_FFFF, riscv_pkg::ALU_XOR,
                        "XOR: 0x00000000 ^ 0xFFFFFFFF = 0xFFFFFFFF (bitwise NOT)",
                        32'hFFFF_FFFF, 1'b0);

        // ================================================================
        // SLL Tests (ALU_SLL = 4'b0101) — Shift Left Logical
        // ================================================================
        $display("");
        $display("--- SLL ---");

        // Test 19: Basic shift left
        // 1 << 4 = 16 (0x10). Shifting 1 left by N positions = 2^N.
        apply_and_check(32'd1, 32'd4, riscv_pkg::ALU_SLL,
                        "SLL: 1 << 4 = 16",
                        32'd16, 1'b0);

        // Test 20: Shift by 0 (no change)
        // Any value shifted by 0 should pass through unchanged.
        apply_and_check(32'hABCD_1234, 32'd0, riscv_pkg::ALU_SLL,
                        "SLL: 0xABCD1234 << 0 = 0xABCD1234 (identity)",
                        32'hABCD_1234, 1'b0);

        // Test 21: Shift to MSB position
        // 1 << 31 = 0x80000000. Places a 1 in the sign bit position.
        apply_and_check(32'd1, 32'd31, riscv_pkg::ALU_SLL,
                        "SLL: 1 << 31 = 0x80000000",
                        32'h8000_0000, 1'b0);

        // Test 22: Only b[4:0] matters for shift amount
        // b = 32 = 0b00000000_00000000_00000000_00100000
        // b[4:0] = 5'b00000 = 0. So the result should be unchanged.
        // This verifies the ALU correctly ignores bits [31:5] of operand B.
        apply_and_check(32'hDEAD_BEEF, 32'd32, riscv_pkg::ALU_SLL,
                        "SLL: b=32, b[4:0]=0, no shift (upper bits ignored)",
                        32'hDEAD_BEEF, 1'b0);

        // ================================================================
        // SRL Tests (ALU_SRL = 4'b0110) — Shift Right Logical
        // ================================================================
        $display("");
        $display("--- SRL ---");

        // Test 23: Basic logical right shift
        // 0x80000000 >> 1 = 0x40000000. The MSB (1) moves right, and a
        // ZERO is shifted in from the left. This is the defining behavior
        // of a LOGICAL right shift: zero-fill from the MSB side.
        apply_and_check(32'h8000_0000, 32'd1, riscv_pkg::ALU_SRL,
                        "SRL: 0x80000000 >> 1 = 0x40000000 (zero fill)",
                        32'h4000_0000, 1'b0);

        // Test 24: Shift right by 4
        // 0xF0 >> 4 = 0x0F. Upper nibble moves to lower nibble.
        apply_and_check(32'h0000_00F0, 32'd4, riscv_pkg::ALU_SRL,
                        "SRL: 0xF0 >> 4 = 0x0F",
                        32'h0000_000F, 1'b0);

        // Test 25: Full right shift (shift out all bits)
        // 0xFFFFFFFF >> 31 = 0x00000001. Only the original MSB remains.
        apply_and_check(32'hFFFF_FFFF, 32'd31, riscv_pkg::ALU_SRL,
                        "SRL: 0xFFFFFFFF >> 31 = 0x00000001",
                        32'h0000_0001, 1'b0);

        // ================================================================
        // SRA Tests (ALU_SRA = 4'b0111) — Shift Right Arithmetic
        // ================================================================
        //
        // THIS IS THE MOST CRITICAL OPERATION TO TEST CORRECTLY.
        // SRA differs from SRL only when the sign bit (MSB) is 1.
        // For positive numbers (MSB=0), SRA and SRL produce identical
        // results. The bug, if present, ONLY manifests with negative inputs.
        // ================================================================
        $display("");
        $display("--- SRA ---");

        // Test 26: Positive number (MSB=0) — should behave like SRL
        // 0x40000000 >>> 1 = 0x20000000. Sign bit is 0, so zero-fill
        // and sign-fill are identical. This test alone cannot distinguish
        // a correct SRA from a broken one that does SRL — you NEED a
        // negative-number test case.
        apply_and_check(32'h4000_0000, 32'd1, riscv_pkg::ALU_SRA,
                        "SRA: 0x40000000 >>> 1 = 0x20000000 (positive, same as SRL)",
                        32'h2000_0000, 1'b0);

        // Test 27: Negative number (MSB=1) — THE critical SRA test
        // 0x80000000 >>> 1 = 0xC0000000. Sign bit is 1 (negative number).
        // SRA must replicate the sign bit into the vacated MSB position:
        //   Before: 1000_0000_0000_0000_0000_0000_0000_0000
        //   After:  1100_0000_0000_0000_0000_0000_0000_0000
        //           ^ sign bit replicated (arithmetic shift)
        //
        // If the ALU incorrectly does SRL here, the result would be
        // 0x40000000 instead — zero-fill from the left. That is the
        // exact bug that $signed(a) >>> b[4:0] prevents.
        apply_and_check(32'h8000_0000, 32'd1, riscv_pkg::ALU_SRA,
                        "SRA: 0x80000000 >>> 1 = 0xC0000000 (SIGN EXTENSION)",
                        32'hC000_0000, 1'b0);

        // Test 28: All-ones arithmetic shift
        // 0xFFFFFFFF >>> 4 = 0xFFFFFFFF. Shifting a value that is all 1s
        // by any amount still produces all 1s, because the sign bit (1)
        // keeps filling from the left.
        apply_and_check(32'hFFFF_FFFF, 32'd4, riscv_pkg::ALU_SRA,
                        "SRA: 0xFFFFFFFF >>> 4 = 0xFFFFFFFF (all-ones preserved)",
                        32'hFFFF_FFFF, 1'b0);

        // Test 29: Large arithmetic shift on negative
        // 0x80000000 >>> 31 = 0xFFFFFFFF. Shifting the most negative
        // number right by 31 positions fills all bits with the sign bit (1).
        apply_and_check(32'h8000_0000, 32'd31, riscv_pkg::ALU_SRA,
                        "SRA: 0x80000000 >>> 31 = 0xFFFFFFFF (full sign extension)",
                        32'hFFFF_FFFF, 1'b0);

        // ================================================================
        // SLT Tests (ALU_SLT = 4'b1000) — Set Less Than (Signed)
        // ================================================================
        $display("");
        $display("--- SLT (Signed) ---");

        // Test 30: Small positive < larger positive
        // 3 < 5 = true (1). Basic signed comparison.
        apply_and_check(32'd3, 32'd5, riscv_pkg::ALU_SLT,
                        "SLT: 3 < 5 = 1 (signed)",
                        32'd1, 1'b0);

        // Test 31: Larger positive < smaller positive
        // 5 < 3 = false (0).
        apply_and_check(32'd5, 32'd3, riscv_pkg::ALU_SLT,
                        "SLT: 5 < 3 = 0 (signed)",
                        32'd0, 1'b1);

        // Test 32: Equal values
        // 7 < 7 = false (0). Less-than is strict inequality, not <=.
        // Zero flag asserts because result = 0.
        apply_and_check(32'd7, 32'd7, riscv_pkg::ALU_SLT,
                        "SLT: 7 < 7 = 0 (equal, not less)",
                        32'd0, 1'b1);

        // Test 33: Negative < positive (THE critical signed test)
        // 0xFFFFFFFF in signed = -1. Signed: -1 < 1 is TRUE (1).
        // This is where SLT and SLTU MUST give opposite answers.
        apply_and_check(32'hFFFF_FFFF, 32'd1, riscv_pkg::ALU_SLT,
                        "SLT: -1 (0xFFFFFFFF) < 1 = 1 (signed: -1 < 1)",
                        32'd1, 1'b0);

        // Test 34: Positive < negative (signed)
        // Signed: 1 < -1 is FALSE (0).
        apply_and_check(32'd1, 32'hFFFF_FFFF, riscv_pkg::ALU_SLT,
                        "SLT: 1 < -1 (0xFFFFFFFF) = 0 (signed: 1 > -1)",
                        32'd0, 1'b1);

        // Test 35: Most negative < most positive
        // 0x80000000 (signed: -2,147,483,648) < 0x7FFFFFFF (+2,147,483,647)
        // = TRUE. This is the extreme signed boundary.
        apply_and_check(32'h8000_0000, 32'h7FFF_FFFF, riscv_pkg::ALU_SLT,
                        "SLT: -2^31 < 2^31-1 = 1 (extreme signed boundary)",
                        32'd1, 1'b0);

        // ================================================================
        // SLTU Tests (ALU_SLTU = 4'b1001) — Set Less Than Unsigned
        // ================================================================
        $display("");
        $display("--- SLTU (Unsigned) ---");

        // Test 36: Small < large (unsigned, same as signed for positives)
        apply_and_check(32'd1, 32'd5, riscv_pkg::ALU_SLTU,
                        "SLTU: 1 < 5 = 1 (unsigned)",
                        32'd1, 1'b0);

        // Test 37: Large < small (unsigned)
        apply_and_check(32'd5, 32'd1, riscv_pkg::ALU_SLTU,
                        "SLTU: 5 < 1 = 0 (unsigned)",
                        32'd0, 1'b1);

        // Test 38: 0xFFFFFFFF vs 1 — THE critical unsigned test
        // Unsigned: 0xFFFFFFFF = 4,294,967,295 > 1 = FALSE (0).
        // This is the OPPOSITE result from SLT Test 33, where the same
        // bit pattern (-1 signed) was LESS than 1. If SLT and SLTU give
        // the same answer here, one of them is broken.
        apply_and_check(32'hFFFF_FFFF, 32'd1, riscv_pkg::ALU_SLTU,
                        "SLTU: 0xFFFFFFFF < 1 = 0 (unsigned: 4B > 1)",
                        32'd0, 1'b1);

        // Test 39: 0 < anything (unsigned)
        // Zero is less than every non-zero unsigned value.
        apply_and_check(32'd0, 32'd1, riscv_pkg::ALU_SLTU,
                        "SLTU: 0 < 1 = 1",
                        32'd1, 1'b0);

        // Test 40: Equal values (unsigned)
        apply_and_check(32'hABCD_1234, 32'hABCD_1234, riscv_pkg::ALU_SLTU,
                        "SLTU: equal values = 0",
                        32'd0, 1'b1);

        // ================================================================
        // Summary
        // ================================================================
        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);

        if (fail_count == 0) begin
            $display("  STATUS:  ALL TESTS PASSED");
        end else begin
            $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        end

        $display("==========================================================");
        $display("");

        $finish;
    end

endmodule
