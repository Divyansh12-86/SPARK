// ============================================================================
// File:        tb_custom_decoder.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Custom Instruction Decoder (PIM).
// ============================================================================

`timescale 1ns / 1ps

module tb_custom_decoder;

    import riscv_pkg::*;

    logic [31:0] tb_instr;
    logic        tb_is_custom;
    pim_op_t     tb_pim_op;
    logic        tb_pim_valid;
    logic        tb_illegal_custom;

    integer pass_count;
    integer fail_count;
    integer test_num;

    custom_decoder dut (
        .instr          (tb_instr),
        .is_custom      (tb_is_custom),
        .pim_op         (tb_pim_op),
        .pim_valid      (tb_pim_valid),
        .illegal_custom (tb_illegal_custom)
    );

    task check(
        input string   test_name,
        input logic    exp_custom,
        input pim_op_t exp_op,
        input logic    exp_valid,
        input logic    exp_illegal
    );
        test_num++;
        if (tb_is_custom !== exp_custom ||
            (exp_valid && tb_pim_op !== exp_op) ||
            tb_pim_valid !== exp_valid ||
            tb_illegal_custom !== exp_illegal) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Custom=%0b Valid=%0b Op=%s Illegal=%0b",
                     tb_is_custom, tb_pim_valid, tb_pim_op.name(), tb_illegal_custom);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Op=%s Valid=%0b)",
                     test_num, test_name, tb_pim_op.name(), tb_pim_valid);
            pass_count++;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Custom Instruction Decoder Testbench");
        $display("==========================================================");

        // 1. Standard instruction (ADD): must NOT be custom
        tb_instr = 32'h002081b3; // add x3, x1, x2 (opcode 0110011)
        #5;
        check("Standard ADD is not custom", 1'b0, PIM_VADD, 1'b0, 1'b0);

        // 2. pim.vadd (opcode 0101011, funct3 = 000, funct7 = 0000000)
        tb_instr = 32'b0000000_00010_00001_000_00011_0101011;
        #5;
        check("pim.vadd decoded", 1'b1, PIM_VADD, 1'b1, 1'b0);

        // 3. pim.vmac (funct3 = 001)
        tb_instr = 32'b0000000_00010_00001_001_00011_0101011;
        #5;
        check("pim.vmac decoded", 1'b1, PIM_VMAC, 1'b1, 1'b0);

        // 4. pim.vand (funct3 = 010)
        tb_instr = 32'b0000000_00010_00001_010_00011_0101011;
        #5;
        check("pim.vand decoded", 1'b1, PIM_VAND, 1'b1, 1'b0);

        // 5. pim.vsum (funct3 = 011)
        tb_instr = 32'b0000000_00010_00001_011_00011_0101011;
        #5;
        check("pim.vsum decoded", 1'b1, PIM_VSUM, 1'b1, 1'b0);

        // 6. pim.cfg (funct3 = 100)
        tb_instr = 32'b0000000_00010_00001_100_00011_0101011;
        #5;
        check("pim.cfg decoded", 1'b1, PIM_CFG, 1'b1, 1'b0);

        // 7. pim.vfill (funct3 = 101)
        tb_instr = 32'b0000000_00010_00001_101_00011_0101011;
        #5;
        check("pim.vfill decoded", 1'b1, PIM_VFILL, 1'b1, 1'b0);

        // 8. Invalid custom-1 funct3 (funct3 = 111)
        tb_instr = 32'b0000000_00010_00001_111_00011_0101011;
        #5;
        check("Invalid custom-1 funct3 triggers illegal_custom", 1'b1, PIM_VADD, 1'b0, 1'b1);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
