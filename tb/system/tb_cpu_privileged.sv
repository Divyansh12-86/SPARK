// ============================================================================
// File:        tb_cpu_privileged.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: System-Level Self-Checking Testbench for Privileged Architecture:
//                - CSR Atomic Instructions (CSRRW, CSRRS, CSRRC)
//                - Register writeback of old CSR values (WB_SRC_CSR)
//                - Hardware Trap Entry on Synchronous Exception (ECALL)
//                - Exception Program Counter (mepc) and Cause (mcause)
//                - Hardware Trap Return (MRET) and instruction stream resumption
// ============================================================================

`timescale 1ns / 1ps

module tb_cpu_privileged;

    import riscv_pkg::*;

    logic        clk;
    logic        rst_n;

    logic        timer_irq;
    logic        external_irq;
    logic [1:0]  priv_mode_out;
    logic [31:0] satp_out;

    logic [31:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_alu_result;
    logic [31:0] dbg_wb_data;
    logic        dbg_reg_write;
    logic        dbg_stall;
    logic        dbg_flush;

    int pass_count = 0;
    int fail_count = 0;
    int test_num   = 0;

    // Instantiate 5-Stage Pipelined CPU with Privileged test firmware
    cpu_pipe #(
        .RESET_ADDR (32'h0000_0000),
        .MEM_DEPTH  (1024),
        .INIT_FILE  ("../sw/test_csr_trap.hex")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .timer_irq     (timer_irq),
        .external_irq  (external_irq),
        .priv_mode_out   (priv_mode_out),
        .satp_out        (satp_out),
        .ext_mem_rdata   (32'b0),
        .ext_instr_rdata (32'b0),
        .dbg_pc          (dbg_pc),
        .dbg_instr     (dbg_instr),
        .dbg_alu_result(dbg_alu_result),
        .dbg_wb_data   (dbg_wb_data),
        .dbg_reg_write (dbg_reg_write),
        .dbg_stall     (dbg_stall),
        .dbg_flush     (dbg_flush)
    );

    // 100MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task check_reg(
        input int          reg_idx,
        input logic [31:0] expected_val,
        input string       test_name
    );
        logic [31:0] actual_val;
        actual_val = dut.u_reg_file.registers[reg_idx];
        test_num++;

        if (actual_val !== expected_val) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Register x%0d: Expected=0x%08h (%0d) Actual=0x%08h (%0d)",
                     reg_idx, expected_val, expected_val, actual_val, actual_val);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s -> x%0d = 0x%08h",
                     test_num, test_name, reg_idx, actual_val);
            pass_count++;
        end
    endtask

    task check_cond(
        input logic  condition,
        input string test_name
    );
        test_num++;
        if (!condition) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s", test_num, test_name);
            pass_count++;
        end
    endtask

    initial begin
        $dumpfile("cpu_privileged_tb.vcd");
        $dumpvars(0, tb_cpu_privileged);

        pass_count   = 0;
        fail_count   = 0;
        test_num     = 0;
        timer_irq    = 1'b0;
        external_irq = 1'b0;

        $display("");
        $display("===============================================================");
        $display("   SPARK Privileged Architecture & Hardware Trap Testbench    ");
        $display("===============================================================");

        // Apply Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // Run for 60 clock cycles: program executes CSR writes, ECALL trap,
        // trap handler execution, MRET return, and post-trap execution.
        repeat (60) begin
            @(posedge clk);
            #1;
        end

        $display("");
        $display("--- Verifying CSR Access & Atomic Instruction Semantics ---");

        // 1. mtvec setup & readback
        check_reg(5, 32'h0000_0000, "CSRRW x5 returned initial mtvec = 0");
        check_reg(6, 32'h0000_0060, "CSRRS x6 read updated mtvec = 0x60");

        // 2. mscratch atomic write & readback
        check_reg(7, 32'h0000_0000, "CSRRW x7 returned initial mscratch = 0");
        check_reg(8, 32'h1234_5678, "CSRRS x8 read updated mscratch = 0x12345678");

        // 3. mscratch atomic clear bits
        check_reg(9,  32'h1234_5678, "CSRRC x9 returned pre-clear mscratch = 0x12345678");
        check_reg(10, 32'h1234_5670, "CSRRS x10 read bit-cleared mscratch = 0x12345670");

        $display("");
        $display("--- Verifying Synchronous Exception Entry & Trap Handler ---");

        // 4. Trap Handler mcause & mepc capture
        check_reg(11, 32'd11,        "mcause captured Machine ECALL exception (cause = 11)");
        check_reg(12, 32'h0000_0030, "mepc incremented to return address 0x30 (0x2C + 4)");
        check_reg(13, 32'd1,         "Trap handler reached and executed (x13 = 1)");

        $display("");
        $display("--- Verifying Hardware Trap Return (MRET) & Execution Flow ---");

        // 5. Instruction stream resumed after ecall
        check_reg(15, 32'd1,         "Execution resumed after MRET at instruction following ECALL (x15 = 1)");
        check_reg(16, 32'h0050_A000, "Main program reached timer config with sentinel (x16 = 0x0050A000)");

        // 6. Privilege mode verification
        check_cond(priv_mode_out == PRIV_M, "Current core privilege mode is Machine mode (PRIV_M)");

        $display("");
        $display("--- Verifying Asynchronous Hardware Interrupt Preemption ---");

        // Assert Timer IRQ from CLINT
        @(posedge clk);
        timer_irq = 1'b1;
        repeat (2) @(posedge clk);
        #1;
        timer_irq = 1'b0;

        // Allow core to trap into interrupt vector, execute handler at 0x80, and return
        repeat (15) begin
            @(posedge clk);
            #1;
        end

        // 7. Verify hardware timer interrupt handled
        check_reg(14, 32'd7, "Hardware timer interrupt preempted core and executed handler (x14 = 7)");
        check_cond(dut.u_csr_file.mie == 32'b0, "Interrupt handler disabled mie to prevent interrupt flood");

        $display("");
        $display("===============================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) begin
            $display("  STATUS:  ALL PRIVILEGED ARCHITECTURE TESTS PASSED!");
        end else begin
            $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        end
        $display("===============================================================");
        $display("");

        $finish;
    end

endmodule
