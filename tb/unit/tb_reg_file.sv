// ============================================================================
// File:        tb_reg_file.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for the RV32I Register File.
// ============================================================================

`timescale 1ns / 1ps

module tb_reg_file;

    // Clock and reset
    logic        clk;
    logic        rst_n;

    // Read ports
    logic [4:0]  rs1_addr;
    logic [31:0] rs1_data;
    logic [4:0]  rs2_addr;
    logic [31:0] rs2_data;

    // Write port
    logic        wr_en;
    logic [4:0]  rd_addr;
    logic [31:0] rd_data;

    // Test tracking
    integer pass_count;
    integer fail_count;
    integer test_num;

    // DUT instantiation
    reg_file dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1_addr),
        .rs1_data (rs1_data),
        .rs2_addr (rs2_addr),
        .rs2_data (rs2_data),
        .wr_en    (wr_en),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data)
    );

    // Clock generation: 10ns period (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // ========================================================================
    // Verification Tasks
    // ========================================================================

    task check_read(
        input string       test_name,
        input logic [31:0] expected_rs1,
        input logic [31:0] expected_rs2
    );
        test_num++;
        if (rs1_data !== expected_rs1 || rs2_data !== expected_rs2) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         rs1_addr=%0d  Expected=0x%08h  Actual=0x%08h",
                     rs1_addr, expected_rs1, rs1_data);
            $display("         rs2_addr=%0d  Expected=0x%08h  Actual=0x%08h",
                     rs2_addr, expected_rs2, rs2_data);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s", test_num, test_name);
            pass_count++;
        end
    endtask

    task write_reg(
        input logic [4:0]  addr,
        input logic [31:0] data
    );
        wr_en   = 1'b1;
        rd_addr = addr;
        rd_data = data;
        @(posedge clk);
        #1; // Small delay after clock edge for signal settling
        wr_en   = 1'b0;
    endtask

    // ========================================================================
    // Main Test Sequence
    // ========================================================================

    initial begin
        $dumpfile("reg_file_tb.vcd");
        $dumpvars(0, tb_reg_file);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        // Initialize inputs
        wr_en    = 1'b0;
        rd_addr  = 5'b0;
        rd_data  = 32'b0;
        rs1_addr = 5'b0;
        rs2_addr = 5'b0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Register File Testbench");
        $display("==========================================================");

        // ================================================================
        // Reset Test
        // ================================================================
        $display("");
        $display("--- Reset ---");

        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        #1;

        // After reset, all registers should read zero
        rs1_addr = 5'd0;
        rs2_addr = 5'd1;
        #1;
        check_read("x0=0 and x1=0 after reset", 32'h0, 32'h0);

        rs1_addr = 5'd15;
        rs2_addr = 5'd31;
        #1;
        check_read("x15=0 and x31=0 after reset", 32'h0, 32'h0);

        // ================================================================
        // Basic Write and Read
        // ================================================================
        $display("");
        $display("--- Basic Write/Read ---");

        // Write 0xDEADBEEF to x1
        write_reg(5'd1, 32'hDEAD_BEEF);
        rs1_addr = 5'd1;
        rs2_addr = 5'd0;
        #1;
        check_read("Write 0xDEADBEEF to x1, read back",
                   32'hDEAD_BEEF, 32'h0);

        // Write 0x12345678 to x2
        write_reg(5'd2, 32'h1234_5678);
        rs1_addr = 5'd1;
        rs2_addr = 5'd2;
        #1;
        check_read("Read x1 and x2 simultaneously",
                   32'hDEAD_BEEF, 32'h1234_5678);

        // ================================================================
        // x0 Hardwired Zero — Write Attempt Must Be Discarded
        // ================================================================
        $display("");
        $display("--- x0 Hardwired Zero ---");

        // Attempt to write 0xFFFFFFFF to x0
        write_reg(5'd0, 32'hFFFF_FFFF);
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        #1;
        check_read("Write 0xFFFFFFFF to x0 must be discarded — still 0",
                   32'h0, 32'h0);

        // Verify x1 was not corrupted by the x0 write attempt
        rs1_addr = 5'd1;
        rs2_addr = 5'd0;
        #1;
        check_read("x1 still holds 0xDEADBEEF after x0 write attempt",
                   32'hDEAD_BEEF, 32'h0);

        // ================================================================
        // Write Enable Gating
        // ================================================================
        $display("");
        $display("--- Write Enable ---");

        // With wr_en=0, write to x5 should NOT take effect
        wr_en   = 1'b0;
        rd_addr = 5'd5;
        rd_data = 32'hBADC_0FFE;
        @(posedge clk);
        #1;
        rs1_addr = 5'd5;
        rs2_addr = 5'd5;
        #1;
        check_read("wr_en=0: write to x5 must not take effect (still 0)",
                   32'h0, 32'h0);

        // Now actually write to x5 with wr_en=1
        write_reg(5'd5, 32'hBADC_0FFE);
        rs1_addr = 5'd5;
        rs2_addr = 5'd5;
        #1;
        check_read("wr_en=1: x5 = 0xBADC0FFE",
                   32'hBADC_0FFE, 32'hBADC_0FFE);

        // ================================================================
        // Write to Multiple Registers and Read-Back
        // ================================================================
        $display("");
        $display("--- Multi-Register ---");

        write_reg(5'd10, 32'hAAAA_AAAA);
        write_reg(5'd20, 32'hBBBB_BBBB);
        write_reg(5'd31, 32'hCCCC_CCCC);

        rs1_addr = 5'd10;
        rs2_addr = 5'd20;
        #1;
        check_read("x10=0xAAAAAAAA, x20=0xBBBBBBBB",
                   32'hAAAA_AAAA, 32'hBBBB_BBBB);

        rs1_addr = 5'd31;
        rs2_addr = 5'd1;
        #1;
        check_read("x31=0xCCCCCCCC, x1=0xDEADBEEF (still held)",
                   32'hCCCC_CCCC, 32'hDEAD_BEEF);

        // ================================================================
        // Overwrite Test
        // ================================================================
        $display("");
        $display("--- Overwrite ---");

        write_reg(5'd1, 32'hCAFE_BABE);
        rs1_addr = 5'd1;
        rs2_addr = 5'd2;
        #1;
        check_read("Overwrite x1 to 0xCAFEBABE, x2 unchanged",
                   32'hCAFE_BABE, 32'h1234_5678);

        // ================================================================
        // Reset Clears All Registers
        // ================================================================
        $display("");
        $display("--- Reset Clears All ---");

        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        #1;

        rs1_addr = 5'd1;
        rs2_addr = 5'd31;
        #1;
        check_read("After 2nd reset: x1=0, x31=0",
                   32'h0, 32'h0);

        rs1_addr = 5'd10;
        rs2_addr = 5'd20;
        #1;
        check_read("After 2nd reset: x10=0, x20=0",
                   32'h0, 32'h0);

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
