// ============================================================================
// File:        tb_alu_ctrl.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for the RV32I ALU Control Unit.
// ============================================================================

`timescale 1ns / 1ps

module tb_alu_ctrl;

    import riscv_pkg::*;

    logic [1:0] tb_alu_op_hint;
    logic [2:0] tb_funct3;
    logic       tb_funct7_5;
    alu_op_t    tb_alu_op;

    integer pass_count;
    integer fail_count;
    integer test_num;

    alu_ctrl dut (
        .alu_op_hint (tb_alu_op_hint),
        .funct3      (tb_funct3),
        .funct7_5    (tb_funct7_5),
        .alu_op      (tb_alu_op)
    );

    task check(
        input string   test_name,
        input alu_op_t expected_op
    );
        test_num++;
        if (tb_alu_op !== expected_op) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Hint=2'b%02b funct3=3'b%03b funct7_5=%0b",
                     tb_alu_op_hint, tb_funct3, tb_funct7_5);
            $display("         Expected=%s Actual=%s", expected_op.name(), tb_alu_op.name());
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Output=%s)", test_num, test_name, tb_alu_op.name());
            pass_count++;
        end
    endtask

    task apply_and_check(
        input logic [1:0] hint,
        input logic [2:0] f3,
        input logic       f7_5,
        input string      test_name,
        input alu_op_t    expected_op
    );
        tb_alu_op_hint = hint;
        tb_funct3      = f3;
        tb_funct7_5    = f7_5;
        #10;
        check(test_name, expected_op);
    endtask

    initial begin
        $dumpfile("alu_ctrl_tb.vcd");
        $dumpvars(0, tb_alu_ctrl);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK ALU Control Testbench");
        $display("==========================================================");

        // ----------------------------------------------------------------
        // 1. Memory / Address Calculation (2'b00)
        // ----------------------------------------------------------------
        $display("");
        $display("--- Memory / Address (Hint 2'b00) ---");
        apply_and_check(2'b00, 3'b010, 1'b0, "Load/Store address calculation", ALU_ADD);

        // ----------------------------------------------------------------
        // 2. Branch Instructions (2'b01)
        // ----------------------------------------------------------------
        $display("");
        $display("--- Branch Instructions (Hint 2'b01) ---");
        apply_and_check(2'b01, 3'b000, 1'b0, "BEQ  (SUB for zero check)", ALU_SUB);
        apply_and_check(2'b01, 3'b001, 1'b0, "BNE  (SUB for zero check)", ALU_SUB);
        apply_and_check(2'b01, 3'b100, 1'b0, "BLT  (signed SLT)",        ALU_SLT);
        apply_and_check(2'b01, 3'b101, 1'b0, "BGE  (signed SLT)",        ALU_SLT);
        apply_and_check(2'b01, 3'b110, 1'b0, "BLTU (unsigned SLTU)",      ALU_SLTU);
        apply_and_check(2'b01, 3'b111, 1'b0, "BGEU (unsigned SLTU)",      ALU_SLTU);

        // ----------------------------------------------------------------
        // 3. R-type Instructions (2'b10)
        // ----------------------------------------------------------------
        $display("");
        $display("--- R-type Instructions (Hint 2'b10) ---");
        apply_and_check(2'b10, 3'b000, 1'b0, "ADD",  ALU_ADD);
        apply_and_check(2'b10, 3'b000, 1'b1, "SUB",  ALU_SUB);
        apply_and_check(2'b10, 3'b001, 1'b0, "SLL",  ALU_SLL);
        apply_and_check(2'b10, 3'b010, 1'b0, "SLT",  ALU_SLT);
        apply_and_check(2'b10, 3'b011, 1'b0, "SLTU", ALU_SLTU);
        apply_and_check(2'b10, 3'b100, 1'b0, "XOR",  ALU_XOR);
        apply_and_check(2'b10, 3'b101, 1'b0, "SRL",  ALU_SRL);
        apply_and_check(2'b10, 3'b101, 1'b1, "SRA",  ALU_SRA);
        apply_and_check(2'b10, 3'b110, 1'b0, "OR",   ALU_OR);
        apply_and_check(2'b10, 3'b111, 1'b0, "AND",  ALU_AND);

        // ----------------------------------------------------------------
        // 4. I-type Instructions (2'b11)
        // ----------------------------------------------------------------
        $display("");
        $display("--- I-type Instructions (Hint 2'b11) ---");
        // Critical test: funct7_5=1 must STILL be ALU_ADD for ADDI (negative immediate)
        apply_and_check(2'b11, 3'b000, 1'b1, "ADDI with negative imm (must remain ADD)", ALU_ADD);
        apply_and_check(2'b11, 3'b001, 1'b0, "SLLI", ALU_SLL);
        apply_and_check(2'b11, 3'b010, 1'b0, "SLTI", ALU_SLT);
        apply_and_check(2'b11, 3'b011, 1'b0, "SLTIU",ALU_SLTU);
        apply_and_check(2'b11, 3'b100, 1'b0, "XORI", ALU_XOR);
        apply_and_check(2'b11, 3'b101, 1'b0, "SRLI", ALU_SRL);
        apply_and_check(2'b11, 3'b101, 1'b1, "SRAI", ALU_SRA);
        apply_and_check(2'b11, 3'b110, 1'b0, "ORI",  ALU_OR);
        apply_and_check(2'b11, 3'b111, 1'b0, "ANDI", ALU_AND);

        // ================================================================
        // Summary
        // ================================================================
        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);

        if (fail_count == 0)
            $display("  STATUS:  ALL TESTS PASSED");
        else
            $display("  STATUS:  %0d TEST(S) FAILED", fail_count);

        $display("==========================================================");
        $display("");

        $finish;
    end

endmodule
