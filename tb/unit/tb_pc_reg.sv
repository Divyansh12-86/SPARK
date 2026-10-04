// ============================================================================
// File:        tb_pc_reg.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for the Program Counter Register.
// ============================================================================

`timescale 1ns / 1ps

module tb_pc_reg;

    logic        clk;
    logic        rst_n;
    logic        en;
    logic [31:0] pc_next;
    logic [31:0] pc;

    integer pass_count;
    integer fail_count;
    integer test_num;

    // Instantiate with custom reset address to test parameterization
    localparam logic [31:0] TEST_BOOT_ADDR = 32'h0000_0000;

    pc_reg #(
        .RESET_ADDR(TEST_BOOT_ADDR)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (en),
        .pc_next (pc_next),
        .pc      (pc)
    );

    // Clock: 100MHz (10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    task check(
        input string       test_name,
        input logic [31:0] expected_pc
    );
        test_num++;
        if (pc !== expected_pc) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Expected PC = 0x%08h", expected_pc);
            $display("         Actual PC   = 0x%08h", pc);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (PC=0x%08h)", test_num, test_name, pc);
            pass_count++;
        end
    endtask

    initial begin
        $dumpfile("pc_reg_tb.vcd");
        $dumpvars(0, tb_pc_reg);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        en      = 1'b0;
        pc_next = 32'h0;
        rst_n   = 1'b0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Program Counter (PC) Register Testbench");
        $display("==========================================================");

        // ----------------------------------------------------------------
        // 1. Reset Test
        // ----------------------------------------------------------------
        $display("");
        $display("--- Reset State ---");
        @(posedge clk);
        #1;
        check("PC reset to 0x00000000", 32'h0000_0000);

        rst_n = 1'b1;
        en    = 1'b1;

        // ----------------------------------------------------------------
        // 2. Sequential Increment (PC + 4)
        // ----------------------------------------------------------------
        $display("");
        $display("--- Sequential Instruction Step (PC + 4) ---");
        pc_next = 32'h0000_0004;
        @(posedge clk);
        #1;
        check("PC updated to 0x00000004", 32'h0000_0004);

        pc_next = 32'h0000_0008;
        @(posedge clk);
        #1;
        check("PC updated to 0x00000008", 32'h0000_0008);

        pc_next = 32'h0000_000C;
        @(posedge clk);
        #1;
        check("PC updated to 0x0000000C", 32'h0000_000C);

        // ----------------------------------------------------------------
        // 3. Branch / Jump Update
        // ----------------------------------------------------------------
        $display("");
        $display("--- Branch / Jump Target ---");
        pc_next = 32'h0000_1000;
        @(posedge clk);
        #1;
        check("PC jumped to 0x00001000", 32'h0000_1000);

        // ----------------------------------------------------------------
        // 4. Stall / Enable Gating (en = 0 holds PC)
        // ----------------------------------------------------------------
        $display("");
        $display("--- Enable / Stall Gating (en = 0) ---");
        en      = 1'b0;
        pc_next = 32'h0000_2000; // Next PC changes, but en=0
        @(posedge clk);
        #1;
        check("PC holds 0x00001000 during stall (cycle 1)", 32'h0000_1000);

        pc_next = 32'h0000_3000;
        @(posedge clk);
        #1;
        check("PC holds 0x00001000 during stall (cycle 2)", 32'h0000_1000);

        // Re-enable
        en      = 1'b1;
        pc_next = 32'h0000_1004;
        @(posedge clk);
        #1;
        check("PC resumes after stall to 0x00001004", 32'h0000_1004);

        // ----------------------------------------------------------------
        // 5. Reset Clears PC
        // ----------------------------------------------------------------
        $display("");
        $display("--- Mid-stream Reset ---");
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        check("PC returns to RESET_ADDR on reset", 32'h0000_0000);

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
