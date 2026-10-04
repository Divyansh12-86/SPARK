// ============================================================================
// File:        tb_ctrl_unit.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for the RV32I Main Control Unit.
//
//              Applies every distinct opcode and checks all output control
//              signals simultaneously. Also verifies that an unknown opcode
//              produces a safe NOP state.
// ============================================================================

`timescale 1ns / 1ps

module tb_ctrl_unit;

    import riscv_pkg::*;

    logic [6:0]   tb_opcode;
    logic [2:0]   tb_funct3;
    logic         tb_reg_write;
    alu_src_t     tb_alu_src;
    logic         tb_mem_write;
    logic         tb_mem_read;
    wb_src_t      tb_wb_src;
    logic         tb_branch;
    logic         tb_jump;
    logic [1:0]   tb_alu_op;

    integer pass_count;
    integer fail_count;
    integer test_num;

    ctrl_unit dut (
        .opcode    (tb_opcode),
        .funct3    (tb_funct3),
        .reg_write (tb_reg_write),
        .alu_src   (tb_alu_src),
        .mem_write (tb_mem_write),
        .mem_read  (tb_mem_read),
        .wb_src    (tb_wb_src),
        .branch    (tb_branch),
        .jump      (tb_jump),
        .alu_op    (tb_alu_op)
    );

    // ========================================================================
    // Check task: verifies all 8 control outputs in one call
    // ========================================================================
    task check(
        input string      test_name,
        input logic       exp_rw,
        input alu_src_t   exp_asrc,
        input logic       exp_mw,
        input logic       exp_mr,
        input wb_src_t    exp_wb,
        input logic       exp_br,
        input logic       exp_jmp,
        input logic [1:0] exp_aop
    );
        test_num++;
        if (tb_reg_write !== exp_rw   ||
            tb_alu_src   !== exp_asrc ||
            tb_mem_write !== exp_mw   ||
            tb_mem_read  !== exp_mr   ||
            tb_wb_src    !== exp_wb   ||
            tb_branch    !== exp_br   ||
            tb_jump      !== exp_jmp  ||
            tb_alu_op    !== exp_aop)
        begin
            $display("  [FAIL] Test %0d: %s  (opcode=7'b%07b)", test_num, test_name, tb_opcode);
            $display("         Signal     Expected  Actual");
            $display("         reg_write  %0b         %0b", exp_rw,   tb_reg_write);
            $display("         alu_src    %0b         %0b", exp_asrc, tb_alu_src);
            $display("         mem_write  %0b         %0b", exp_mw,   tb_mem_write);
            $display("         mem_read   %0b         %0b", exp_mr,   tb_mem_read);
            $display("         wb_src     %02b        %02b", exp_wb,   tb_wb_src);
            $display("         branch     %0b         %0b", exp_br,   tb_branch);
            $display("         jump       %0b         %0b", exp_jmp,  tb_jump);
            $display("         alu_op     %02b        %02b", exp_aop,  tb_alu_op);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s", test_num, test_name);
            pass_count++;
        end
    endtask

    task apply_and_check(
        input logic [6:0] opcode_val,
        input string      test_name,
        input logic       exp_rw,
        input alu_src_t   exp_asrc,
        input logic       exp_mw,
        input logic       exp_mr,
        input wb_src_t    exp_wb,
        input logic       exp_br,
        input logic       exp_jmp,
        input logic [1:0] exp_aop
    );
        tb_opcode = opcode_val;
        tb_funct3 = 3'b000;
        #10;
        check(test_name, exp_rw, exp_asrc, exp_mw, exp_mr,
              exp_wb, exp_br, exp_jmp, exp_aop);
    endtask

    task apply_and_check_csr(
        input logic [6:0] opcode_val,
        input logic [2:0] funct3_val,
        input string      test_name,
        input logic       exp_rw,
        input alu_src_t   exp_asrc,
        input logic       exp_mw,
        input logic       exp_mr,
        input wb_src_t    exp_wb,
        input logic       exp_br,
        input logic       exp_jmp,
        input logic [1:0] exp_aop
    );
        tb_opcode = opcode_val;
        tb_funct3 = funct3_val;
        #10;
        check(test_name, exp_rw, exp_asrc, exp_mw, exp_mr,
              exp_wb, exp_br, exp_jmp, exp_aop);
    endtask

    initial begin
        $dumpfile("ctrl_unit_tb.vcd");
        $dumpvars(0, tb_ctrl_unit);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Control Unit Testbench");
        $display("==========================================================");
        $display("  Columns: reg_write | alu_src | mem_write | mem_read |");
        $display("           wb_src | branch | jump | alu_op");
        $display("");

        // ----------------------------------------------------------------
        // R-type: reg_write=1, src=REG, no mem, wb=ALU, alu_op=10
        // ----------------------------------------------------------------
        apply_and_check(OP_R_TYPE, "R-type (ADD/SUB/AND/OR...)",
            1'b1, ALU_SRC_REG, 1'b0, 1'b0, WB_SRC_ALU, 1'b0, 1'b0, 2'b10);

        // ----------------------------------------------------------------
        // I-type ALU: reg_write=1, src=IMM, no mem, wb=ALU, alu_op=11
        // ----------------------------------------------------------------
        apply_and_check(OP_I_ALU, "I-type ALU (ADDI/ANDI/ORI...)",
            1'b1, ALU_SRC_IMM, 1'b0, 1'b0, WB_SRC_ALU, 1'b0, 1'b0, 2'b11);

        // ----------------------------------------------------------------
        // Load: reg_write=1, src=IMM, mem_read=1, wb=MEM, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check(OP_LOAD, "Load (LW/LH/LB...)",
            1'b1, ALU_SRC_IMM, 1'b0, 1'b1, WB_SRC_MEM, 1'b0, 1'b0, 2'b00);

        // ----------------------------------------------------------------
        // Store: reg_write=0, src=IMM, mem_write=1, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check(OP_STORE, "Store (SW/SH/SB)",
            1'b0, ALU_SRC_IMM, 1'b1, 1'b0, WB_SRC_ALU, 1'b0, 1'b0, 2'b00);

        // ----------------------------------------------------------------
        // Branch: reg_write=0, src=REG, branch=1, alu_op=01
        // ----------------------------------------------------------------
        apply_and_check(OP_BRANCH, "Branch (BEQ/BNE/BLT...)",
            1'b0, ALU_SRC_REG, 1'b0, 1'b0, WB_SRC_ALU, 1'b1, 1'b0, 2'b01);

        // ----------------------------------------------------------------
        // JAL: reg_write=1, wb=PC4, jump=1, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check(OP_JAL, "JAL",
            1'b1, ALU_SRC_IMM, 1'b0, 1'b0, WB_SRC_PC4, 1'b0, 1'b1, 2'b00);

        // ----------------------------------------------------------------
        // JALR: reg_write=1, src=IMM, wb=PC4, jump=1, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check(OP_JALR, "JALR",
            1'b1, ALU_SRC_IMM, 1'b0, 1'b0, WB_SRC_PC4, 1'b0, 1'b1, 2'b00);

        // ----------------------------------------------------------------
        // LUI: reg_write=1, src=IMM, wb=ALU, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check(OP_LUI, "LUI",
            1'b1, ALU_SRC_IMM, 1'b0, 1'b0, WB_SRC_ALU, 1'b0, 1'b0, 2'b00);

        // ----------------------------------------------------------------
        // AUIPC: reg_write=1, src=IMM, wb=ALU, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check(OP_AUIPC, "AUIPC",
            1'b1, ALU_SRC_IMM, 1'b0, 1'b0, WB_SRC_ALU, 1'b0, 1'b0, 2'b00);

        // ----------------------------------------------------------------
        // SYSTEM Trap (ECALL / EBREAK / MRET / SRET): funct3=000
        //   reg_write=0, wb=ALU, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check_csr(OP_SYSTEM, 3'b000, "SYSTEM (ECALL/MRET)",
            1'b0, ALU_SRC_REG, 1'b0, 1'b0, WB_SRC_ALU, 1'b0, 1'b0, 2'b00);

        // ----------------------------------------------------------------
        // SYSTEM CSR (CSRRW / CSRRS / CSRRC): funct3!=000
        //   reg_write=1, wb=CSR, alu_op=00
        // ----------------------------------------------------------------
        apply_and_check_csr(OP_SYSTEM, 3'b001, "CSRRW (Atomic Read/Write)",
            1'b1, ALU_SRC_REG, 1'b0, 1'b0, WB_SRC_CSR, 1'b0, 1'b0, 2'b00);

        apply_and_check_csr(OP_SYSTEM, 3'b010, "CSRRS (Atomic Read/Set)",
            1'b1, ALU_SRC_REG, 1'b0, 1'b0, WB_SRC_CSR, 1'b0, 1'b0, 2'b00);

        // ----------------------------------------------------------------
        // Unknown opcode: safe NOP — everything disabled
        // ----------------------------------------------------------------
        apply_and_check(7'b1111111, "Unknown opcode (safe NOP)",
            1'b0, ALU_SRC_REG, 1'b0, 1'b0, WB_SRC_ALU, 1'b0, 1'b0, 2'b00);

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
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
