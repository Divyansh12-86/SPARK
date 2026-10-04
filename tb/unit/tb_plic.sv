// ============================================================================
// File:        tb_plic.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Platform-Level Interrupt Controller (PLIC).
// ============================================================================

`timescale 1ns / 1ps

module tb_plic;

    logic       clk;
    logic       rst_n;
    logic       cs;
    logic       read_en;
    logic       write_en;
    logic [23:0] addr;
    logic [31:0] write_data;
    logic [31:0] read_data;
    logic [3:1] irq_sources;
    logic       external_irq;

    integer pass_count;
    integer fail_count;
    integer test_num;

    plic #(
        .NUM_SOURCES(4)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .cs           (cs),
        .read_en      (read_en),
        .write_en     (write_en),
        .addr         (addr),
        .write_data   (write_data),
        .read_data    (read_data),
        .irq_sources  (irq_sources),
        .external_irq (external_irq)
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

    task plic_write(
        input logic [23:0] a,
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
        pass_count  = 0;
        fail_count  = 0;
        test_num    = 0;
        cs          = 0;
        read_en     = 0;
        write_en    = 0;
        addr        = 0;
        write_data  = 0;
        irq_sources = 3'b0;

        $display("");
        $display("==========================================================");
        $display("  SPARK PLIC (External Interrupt Controller) Testbench");
        $display("==========================================================");

        // 1. Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        check("Initial external_irq is DEASSERTED (0)", {31'b0, external_irq}, 32'd0);

        // 2. Configure: Source 1 priority = 5, Enable source 1, Threshold = 2
        plic_write(24'h000004, 32'd5); // Priority 5
        plic_write(24'h001000, 32'd2); // Enable bit 1 (source 1)
        plic_write(24'h200000, 32'd2); // Threshold 2

        // 3. Trigger interrupt on Source 1 (UART)
        irq_sources[1] = 1'b1;
        @(posedge clk);
        #1;
        irq_sources[1] = 1'b0;

        check("Source 1 active: external_irq is ASSERTED (1)", {31'b0, external_irq}, 32'd1);

        // 4. Claim Interrupt: reading 0x200004 returns active source ID (1)
        cs      = 1'b1;
        read_en = 1'b1;
        addr    = 24'h200004;
        #1;
        check("Read Claim register returns source 1", read_data, 32'd1);
        @(posedge clk);
        #1;
        cs      = 1'b0;
        read_en = 1'b0;

        // Pending bit was cleared by Claim
        check("After Claim: external_irq is DEASSERTED (0)", {31'b0, external_irq}, 32'd0);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
