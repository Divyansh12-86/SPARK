// ============================================================================
// File:        tb_cpu_single.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: System-level self-checking testbench for Single-Cycle RV32I CPU.
//              Loads a test program into Instruction Memory, executes it,
//              and verifies the architectural register file state.
// ============================================================================

`timescale 1ns / 1ps

module tb_cpu_single;

    logic        clk;
    logic        rst_n;

    logic [31:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_alu_result;
    logic [31:0] dbg_wb_data;
    logic        dbg_reg_write;

    integer pass_count;
    integer fail_count;
    integer test_num;

    // Instantiate Single-Cycle CPU with test program
    cpu_single #(
        .RESET_ADDR (32'h0000_0000),
        .MEM_DEPTH  (1024),
        .INIT_FILE  ("../sw/test_prog.hex")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .dbg_pc        (dbg_pc),
        .dbg_instr     (dbg_instr),
        .dbg_alu_result(dbg_alu_result),
        .dbg_wb_data   (dbg_wb_data),
        .dbg_reg_write (dbg_reg_write)
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
            $display("  [PASS] Test %0d: %s -> x%0d = 0x%08h (%0d)",
                     test_num, test_name, reg_idx, actual_val, actual_val);
            pass_count++;
        end
    endtask

    initial begin
        $dumpfile("cpu_single_tb.vcd");
        $dumpvars(0, tb_cpu_single);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Single-Cycle RV32I CPU — System Execution Test");
        $display("==========================================================");

        // Apply Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // Run CPU for 25 cycles (program terminates in ~15 cycles and loops)
        repeat (25) begin
            @(posedge clk);
            #1;
        end

        $display("");
        $display("--- Verifying Architectural Register File State ---");

        // 1. Immediate arithmetic
        check_reg(1, 32'd10, "x1 = 10 (ADDI)");
        check_reg(2, 32'd20, "x2 = 20 (ADDI)");

        // 2. Register-register arithmetic
        check_reg(3, 32'd30, "x3 = 30 (ADD x1, x2)");
        check_reg(4, 32'd10, "x4 = 10 (SUB x2, x1)");

        // 3. Memory store and load
        check_reg(5, 32'd30, "x5 = 30 (SW then LW from memory)");

        // 4. Branch taken (x6 must be 0 because it was skipped by BEQ)
        check_reg(6, 32'd0,  "x6 = 0  (BEQ correctly skipped over instruction)");
        check_reg(7, 32'd42, "x7 = 42 (Branch destination reached)");

        // 5. Upper Immediate (LUI)
        check_reg(8, 32'h1234_5000, "x8 = 0x12345000 (LUI)");

        // 6. Jump and Link (JAL)
        check_reg(9,  32'h0000_002C, "x9 = 0x2C (JAL saved return address PC+4)");
        check_reg(10, 32'd0,         "x10 = 0 (JAL correctly skipped over instruction)");
        check_reg(11, 32'd1,         "x11 = 1 (Jump destination executed successfully)");

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) begin
            $display("  STATUS:  ALL TESTS PASSED — SINGLE-CYCLE RV32I VERIFIED!");
        end else begin
            $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        end
        $display("==========================================================");
        $display("");

        $finish;
    end

endmodule
