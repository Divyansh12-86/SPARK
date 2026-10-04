// ============================================================================
// File:        tb_csr_file.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Control and Status Register (CSR) File.
// ============================================================================

`timescale 1ns / 1ps

module tb_csr_file;

    import riscv_pkg::*;

    logic        clk;
    logic        rst_n;

    logic [11:0] csr_addr;
    logic [2:0]  csr_op;
    logic        csr_we;
    logic [31:0] csr_wdata;
    logic [31:0] csr_rdata;

    logic        trap_enter;
    logic        trap_is_interrupt;
    logic [30:0] trap_cause;
    logic [31:0] trap_pc;
    logic [31:0] trap_val;
    logic        trap_return_m;
    logic        trap_return_s;

    logic        timer_irq;
    logic        external_irq;

    logic        irq_pending;
    logic [31:0] mtvec_out;
    logic [31:0] stvec_out;
    logic [31:0] mepc_out;
    logic [31:0] sepc_out;
    logic [1:0]  priv_mode_out;
    logic [31:0] satp_out;

    integer pass_count;
    integer fail_count;
    integer test_num;

    csr_file dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .csr_addr         (csr_addr),
        .csr_op           (csr_op),
        .csr_we           (csr_we),
        .csr_wdata        (csr_wdata),
        .csr_rdata        (csr_rdata),

        .trap_enter       (trap_enter),
        .trap_is_interrupt(trap_is_interrupt),
        .trap_cause       (trap_cause),
        .trap_pc          (trap_pc),
        .trap_val         (trap_val),
        .trap_return_m    (trap_return_m),
        .trap_return_s    (trap_return_s),

        .timer_irq        (timer_irq),
        .external_irq     (external_irq),

        .irq_pending      (irq_pending),
        .mtvec_out        (mtvec_out),
        .stvec_out        (stvec_out),
        .mepc_out         (mepc_out),
        .sepc_out         (sepc_out),
        .priv_mode_out    (priv_mode_out),
        .satp_out         (satp_out)
    );

    // 100MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task check(
        input string       test_name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        test_num++;
        if (actual !== expected) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Expected=0x%08h Actual=0x%08h", expected, actual);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Val=0x%08h)", test_num, test_name, actual);
            pass_count++;
        end
    endtask

    task csr_write(
        input logic [11:0] addr,
        input logic [2:0]  op,
        input logic [31:0] data
    );
        csr_addr  = addr;
        csr_op    = op;
        csr_we    = 1'b1;
        csr_wdata = data;
        @(posedge clk);
        #1;
        csr_we    = 1'b0;
    endtask

    initial begin
        pass_count        = 0;
        fail_count        = 0;
        test_num          = 0;

        csr_addr          = 12'b0;
        csr_op            = 3'b0;
        csr_we            = 1'b0;
        csr_wdata         = 32'b0;
        trap_enter        = 1'b0;
        trap_is_interrupt = 1'b0;
        trap_cause        = 31'b0;
        trap_pc           = 32'b0;
        trap_val          = 32'b0;
        trap_return_m     = 1'b0;
        trap_return_s     = 1'b0;
        timer_irq         = 1'b0;
        external_irq      = 1'b0;

        $display("");
        $display("==========================================================");
        $display("  SPARK CSR File Testbench");
        $display("==========================================================");

        // 1. Reset check
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        check("Initial privilege mode is Machine (PRIV_M = 2'b11)", {30'b0, priv_mode_out}, 32'd3);

        // 2. CSRRW: Atomic write and readback of mtvec
        csr_write(CSR_MTVEC, CSR_OP_RW, 32'h0000_1000);
        csr_addr = CSR_MTVEC;
        #1;
        check("CSRRW: mtvec = 0x00001000", csr_rdata, 32'h0000_1000);

        // 3. CSRRW: Atomic write to mscratch
        csr_write(CSR_MSCRATCH, CSR_OP_RW, 32'hCAFE_BABE);
        csr_addr = CSR_MSCRATCH;
        #1;
        check("CSRRW: mscratch = 0xCAFEBABE", csr_rdata, 32'hCAFE_BABE);

        // 4. CSRRS: Atomic bit-set
        // Set bit 3 (MIE) in mstatus
        csr_write(CSR_MSTATUS, CSR_OP_RS, 32'h0000_0008);
        csr_addr = CSR_MSTATUS;
        #1;
        check("CSRRS: mstatus[3] (MIE) set to 1", csr_rdata & 32'h0000_0008, 32'h0000_0008);

        // 5. CSRRC: Atomic bit-clear
        // Clear bit 3 (MIE) in mstatus
        csr_write(CSR_MSTATUS, CSR_OP_RC, 32'h0000_0008);
        csr_addr = CSR_MSTATUS;
        #1;
        check("CSRRC: mstatus[3] (MIE) cleared to 0", csr_rdata & 32'h0000_0008, 32'h0000_0000);

        // 6. Supervisor satp register (for xv6 virtual memory)
        csr_write(CSR_SATP, CSR_OP_RW, 32'h8000_0000);
        check("SATP: Sv32 page table base set", satp_out, 32'h8000_0000);

        // 7. Hardware Trap Entry
        trap_enter        = 1'b1;
        trap_is_interrupt = 1'b0;
        trap_cause        = EXC_ECALL_M;
        trap_pc           = 32'h0000_0400;
        trap_val          = 32'h0;
        @(posedge clk);
        #1;
        trap_enter        = 1'b0;

        check("Trap Entry: mepc saved trap_pc (0x400)", mepc_out, 32'h0000_0400);
        csr_addr = CSR_MCAUSE;
        #1;
        check("Trap Entry: mcause saved exception cause (11)", csr_rdata, 32'd11);

        // 8. Hardware Trap Return (MRET)
        trap_return_m = 1'b1;
        @(posedge clk);
        #1;
        trap_return_m = 1'b0;

        check("MRET: Restored execution mode", {30'b0, priv_mode_out}, 32'd3);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
