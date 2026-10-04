// ============================================================================
// File:        tb_trap_ctrl.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Trap Controller.
// ============================================================================

`timescale 1ns / 1ps

module tb_trap_ctrl;

    import riscv_pkg::*;

    logic [31:0] tb_instr;
    logic [31:0] tb_current_pc;
    logic [1:0]  tb_priv_mode;
    logic        tb_illegal_instr;

    logic        tb_irq_pending;
    logic        tb_timer_irq;
    logic        tb_external_irq;

    logic [31:0] tb_mtvec;
    logic [31:0] tb_stvec;
    logic [31:0] tb_mepc;
    logic [31:0] tb_sepc;

    logic        tb_trap_enter;
    logic        tb_trap_is_interrupt;
    logic [30:0] tb_trap_cause;
    logic [31:0] tb_trap_pc;
    logic [31:0] tb_trap_val;
    logic        tb_trap_return_m;
    logic        tb_trap_return_s;
    logic        tb_trap_redirect;
    logic [31:0] tb_trap_pc_target;

    integer pass_count;
    integer fail_count;
    integer test_num;

    trap_ctrl dut (
        .instr            (tb_instr),
        .current_pc       (tb_current_pc),
        .priv_mode        (tb_priv_mode),
        .illegal_instr    (tb_illegal_instr),

        .irq_pending      (tb_irq_pending),
        .timer_irq        (tb_timer_irq),
        .external_irq     (tb_external_irq),

        .mtvec            (tb_mtvec),
        .stvec            (tb_stvec),
        .mepc             (tb_mepc),
        .sepc             (tb_sepc),

        .trap_enter       (tb_trap_enter),
        .trap_is_interrupt(tb_trap_is_interrupt),
        .trap_cause       (tb_trap_cause),
        .trap_pc          (tb_trap_pc),
        .trap_val         (tb_trap_val),
        .trap_return_m    (tb_trap_return_m),
        .trap_return_s    (tb_trap_return_s),
        .trap_redirect    (tb_trap_redirect),
        .trap_pc_target   (tb_trap_pc_target)
    );

    task check(
        input string       test_name,
        input logic        exp_redirect,
        input logic [31:0] exp_target,
        input logic        exp_enter
    );
        test_num++;
        if (tb_trap_redirect !== exp_redirect ||
            tb_trap_pc_target !== exp_target  ||
            tb_trap_enter !== exp_enter) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Redirect: Exp=%0b Act=%0b | Target: Exp=0x%08h Act=0x%08h | Enter: Exp=%0b Act=%0b",
                     exp_redirect, tb_trap_redirect, exp_target, tb_trap_pc_target, exp_enter, tb_trap_enter);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Target=0x%08h)", test_num, test_name, tb_trap_pc_target);
            pass_count++;
        end
    endtask

    initial begin
        pass_count        = 0;
        fail_count        = 0;
        test_num          = 0;

        tb_instr          = 32'h00000013; // NOP
        tb_current_pc     = 32'h00000100;
        tb_priv_mode      = PRIV_M;
        tb_illegal_instr  = 1'b0;
        tb_irq_pending    = 1'b0;
        tb_timer_irq      = 1'b0;
        tb_external_irq   = 1'b0;

        tb_mtvec          = 32'h0000_1000;
        tb_stvec          = 32'h0000_2000;
        tb_mepc           = 32'h0000_0140;
        tb_sepc           = 32'h0000_0280;

        $display("");
        $display("==========================================================");
        $display("  SPARK Trap Controller Testbench");
        $display("==========================================================");

        // 1. Normal execution (no trap)
        #5;
        check("Normal execution (no trap)", 1'b0, 32'h0000_0100, 1'b0);

        // 2. ECALL from User Mode
        tb_instr     = 32'h0000_0073; // ECALL
        tb_priv_mode = PRIV_U;
        #5;
        check("ECALL from User mode -> Jump to mtvec", 1'b1, 32'h0000_1000, 1'b1);

        // 3. MRET (Trap return to mepc)
        tb_instr = 32'h3020_0073; // MRET
        #5;
        check("MRET -> Return PC to mepc (0x140)", 1'b1, 32'h0000_0140, 1'b0);

        // 4. SRET (Supervisor trap return to sepc)
        tb_instr = 32'h1020_0073; // SRET
        #5;
        check("SRET -> Return PC to sepc (0x280)", 1'b1, 32'h0000_0280, 1'b0);

        // 5. Hardware Timer Interrupt
        tb_instr       = 32'h00000013; // NOP
        tb_irq_pending = 1'b1;
        tb_timer_irq   = 1'b1;
        #5;
        check("Timer Interrupt -> Jump to mtvec", 1'b1, 32'h0000_1000, 1'b1);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
