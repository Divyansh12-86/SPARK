// ============================================================================
// File:        tb_branch_unit.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for RV32I Branch Decision Unit.
// ============================================================================

`timescale 1ns / 1ps

module tb_branch_unit;

    logic        tb_branch;
    logic [2:0]  tb_funct3;
    logic [31:0] tb_rs1;
    logic [31:0] tb_rs2;
    logic        tb_branch_taken;

    integer pass_count;
    integer fail_count;
    integer test_num;

    branch_unit dut (
        .branch       (tb_branch),
        .funct3       (tb_funct3),
        .rs1_data     (tb_rs1),
        .rs2_data     (tb_rs2),
        .branch_taken (tb_branch_taken)
    );

    task check(
        input string test_name,
        input logic  expected_taken
    );
        test_num++;
        if (tb_branch_taken !== expected_taken) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         branch=%0b funct3=%03b rs1=0x%08h rs2=0x%08h",
                     tb_branch, tb_funct3, tb_rs1, tb_rs2);
            $display("         Expected=%0b Actual=%0b", expected_taken, tb_branch_taken);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Taken=%0b)", test_num, test_name, tb_branch_taken);
            pass_count++;
        end
    endtask

    task apply_and_check(
        input logic        branch,
        input logic [2:0]  f3,
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input string       test_name,
        input logic        expected_taken
    );
        tb_branch = branch;
        tb_funct3 = f3;
        tb_rs1    = rs1;
        tb_rs2    = rs2;
        #10;
        check(test_name, expected_taken);
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Branch Unit Testbench");
        $display("==========================================================");

        // BEQ
        apply_and_check(1'b1, 3'b000, 32'd10, 32'd10, "BEQ: 10 == 10 (Taken)", 1'b1);
        apply_and_check(1'b1, 3'b000, 32'd10, 32'd20, "BEQ: 10 == 20 (Not taken)", 1'b0);

        // BNE
        apply_and_check(1'b1, 3'b001, 32'd10, 32'd20, "BNE: 10 != 20 (Taken)", 1'b1);
        apply_and_check(1'b1, 3'b001, 32'd10, 32'd10, "BNE: 10 != 10 (Not taken)", 1'b0);

        // BLT (Signed)
        apply_and_check(1'b1, 3'b100, 32'hFFFF_FFFF, 32'd1, "BLT: -1 < 1 (Signed Taken)", 1'b1);
        apply_and_check(1'b1, 3'b100, 32'd1, 32'hFFFF_FFFF, "BLT: 1 < -1 (Signed Not taken)", 1'b0);
        apply_and_check(1'b1, 3'b100, 32'd5, 32'd5,         "BLT: 5 < 5 (Not taken)", 1'b0);

        // BGE (Signed)
        apply_and_check(1'b1, 3'b101, 32'd1, 32'hFFFF_FFFF, "BGE: 1 >= -1 (Signed Taken)", 1'b1);
        apply_and_check(1'b1, 3'b101, 32'd5, 32'd5,         "BGE: 5 >= 5 (Equal Taken)", 1'b1);
        apply_and_check(1'b1, 3'b101, 32'hFFFF_FFFF, 32'd1, "BGE: -1 >= 1 (Signed Not taken)", 1'b0);

        // BLTU (Unsigned)
        apply_and_check(1'b1, 3'b110, 32'd1, 32'hFFFF_FFFF, "BLTU: 1 < 0xFFFFFFFF (Unsigned Taken)", 1'b1);
        apply_and_check(1'b1, 3'b110, 32'hFFFF_FFFF, 32'd1, "BLTU: 0xFFFFFFFF < 1 (Unsigned Not taken)", 1'b0);

        // BGEU (Unsigned)
        apply_and_check(1'b1, 3'b111, 32'hFFFF_FFFF, 32'd1, "BGEU: 0xFFFFFFFF >= 1 (Unsigned Taken)", 1'b1);
        apply_and_check(1'b1, 3'b111, 32'd1, 32'hFFFF_FFFF, "BGEU: 1 >= 0xFFFFFFFF (Unsigned Not taken)", 1'b0);

        // Branch signal disabled (branch=0): must NOT take even if condition matches
        apply_and_check(1'b0, 3'b000, 32'd10, 32'd10, "branch=0: BEQ condition met but branch=0 (Not taken)", 1'b0);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
