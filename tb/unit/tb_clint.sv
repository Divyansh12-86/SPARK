// ============================================================================
// File:        tb_clint.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Core Local Interruptor (CLINT).
// ============================================================================

`timescale 1ns / 1ps

module tb_clint;

    logic        clk;
    logic        rst_n;
    logic        cs;
    logic        read_en;
    logic        write_en;
    logic [15:0] addr;
    logic [31:0] write_data;
    logic [31:0] read_data;
    logic        timer_irq;
    logic        software_irq;

    integer pass_count;
    integer fail_count;
    integer test_num;

    clint dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .cs           (cs),
        .read_en      (read_en),
        .write_en     (write_en),
        .addr         (addr),
        .write_data   (write_data),
        .read_data    (read_data),
        .timer_irq    (timer_irq),
        .software_irq (software_irq)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check(
        input string       test_name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        test_num++;
        if (actual !== expected) begin
            $display("  [FAIL] Test %0d: %s (Expected=0x%08h Actual=0x%08h)",
                     test_num, test_name, expected, actual);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Val=0x%08h)", test_num, test_name, actual);
            pass_count++;
        end
    endtask

    task clint_write(
        input logic [15:0] a,
        input logic [31:0] d
    );
        cs         = 1'b1;
        write_en   = 1'b1;
        addr       = a;
        write_data = d;
        @(posedge clk);
        #1;
        cs         = 1'b0;
        write_en   = 1'b0;
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        cs         = 0;
        read_en    = 0;
        write_en   = 0;
        addr       = 0;
        write_data = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK CLINT (Timer & Software Interrupt) Testbench");
        $display("==========================================================");

        // 1. Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        check("Initial timer_irq is DEASSERTED (0)", {31'b0, timer_irq}, 32'd0);

        // 2. Set mtimecmp to 10
        clint_write(16'h4000, 32'd10);
        clint_write(16'h4004, 32'd0);

        // Wait until mtime reaches 12 cycles
        repeat (12) @(posedge clk);
        #1;
        check("mtime >= 10: timer_irq is ASSERTED (1)", {31'b0, timer_irq}, 32'd1);

        // 3. Clear timer_irq by setting mtimecmp to higher value (1000)
        clint_write(16'h4000, 32'd1000);
        #1;
        check("mtimecmp > mtime: timer_irq is CLEARED (0)", {31'b0, timer_irq}, 32'd0);

        // 4. Software Interrupt (msip)
        clint_write(16'h0000, 32'd1);
        #1;
        check("msip=1: software_irq is ASSERTED (1)", {31'b0, software_irq}, 32'd1);

        clint_write(16'h0000, 32'd0);
        #1;
        check("msip=0: software_irq is CLEARED (0)", {31'b0, software_irq}, 32'd0);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
