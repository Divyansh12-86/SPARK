// ============================================================================
// File:        tb_data_mem.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Data Memory (SB, SH, SW, LB, LH, LW, LBU, LHU).
// ============================================================================

`timescale 1ns / 1ps

module tb_data_mem;

    logic        clk;
    logic        mem_read;
    logic        mem_write;
    logic [2:0]  funct3;
    logic [31:0] addr;
    logic [31:0] write_data;
    logic [31:0] read_data;

    integer pass_count;
    integer fail_count;
    integer test_num;

    data_mem #(
        .DEPTH(1024)
    ) dut (
        .clk        (clk),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .funct3     (funct3),
        .addr       (addr),
        .write_data (write_data),
        .read_data  (read_data)
    );

    // 100MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task write_mem(
        input logic [2:0]  f3,
        input logic [31:0] a,
        input logic [31:0] d
    );
        mem_write  = 1'b1;
        mem_read   = 1'b0;
        funct3     = f3;
        addr       = a;
        write_data = d;
        @(posedge clk);
        #1;
        mem_write  = 1'b0;
    endtask

    task check_read(
        input logic [2:0]  f3,
        input logic [31:0] a,
        input string       test_name,
        input logic [31:0] expected
    );
        test_num++;
        mem_read   = 1'b1;
        mem_write  = 1'b0;
        funct3     = f3;
        addr       = a;
        #2;
        if (read_data !== expected) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         Addr=0x%08h Expected=0x%08h Actual=0x%08h", a, expected, read_data);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Val=0x%08h)", test_num, test_name, read_data);
            pass_count++;
        end
        mem_read = 1'b0;
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        mem_read   = 0;
        mem_write  = 0;
        funct3     = 0;
        addr       = 0;
        write_data = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Data Memory Testbench");
        $display("==========================================================");

        // 1. SW and LW (Word access)
        write_mem(3'b010, 32'h0000_0000, 32'hDEAD_BEEF);
        check_read(3'b010, 32'h0000_0000, "SW & LW: word 0xDEADBEEF at addr 0", 32'hDEAD_BEEF);

        // 2. Byte reading from previously stored word
        // In little-endian: byte 0 = EF, byte 1 = BE, byte 2 = AD, byte 3 = DE
        check_read(3'b100, 32'h0000_0000, "LBU: byte 0 should be 0xEF", 32'h0000_00EF);
        check_read(3'b000, 32'h0000_0000, "LB:  byte 0 (0xEF) sign-extended", 32'hFFFF_FFEF);
        check_read(3'b100, 32'h0000_0001, "LBU: byte 1 should be 0xBE", 32'h0000_00BE);
        check_read(3'b100, 32'h0000_0002, "LBU: byte 2 should be 0xAD", 32'h0000_00AD);
        check_read(3'b100, 32'h0000_0003, "LBU: byte 3 should be 0xDE", 32'h0000_00DE);

        // 3. Halfword reading from word
        check_read(3'b101, 32'h0000_0000, "LHU: lower halfword 0xBEEF", 32'h0000_BEEF);
        check_read(3'b001, 32'h0000_0000, "LH:  lower halfword sign-extended", 32'hFFFF_BEEF);
        check_read(3'b101, 32'h0000_0002, "LHU: upper halfword 0xDEAD", 32'h0000_DEAD);

        // 4. SB (Store Byte) overwrite
        write_mem(3'b000, 32'h0000_0000, 32'h0000_0012); // Overwrite byte 0 with 0x12
        check_read(3'b010, 32'h0000_0000, "After SB at byte 0: word = 0xDEADBE12", 32'hDEAD_BE12);

        // 5. SH (Store Halfword) overwrite
        write_mem(3'b001, 32'h0000_0002, 32'h0000_5678); // Overwrite upper halfword with 0x5678
        check_read(3'b010, 32'h0000_0000, "After SH at half 1: word = 0x5678BE12", 32'h5678_BE12);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
