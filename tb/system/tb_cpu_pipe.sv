// ============================================================================
// File:        tb_cpu_pipe.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: System-Level Self-Checking Testbench for 5-Stage Pipelined RV32I CPU.
//              Stresses and verifies:
//                - EX-to-EX Data Forwarding
//                - MEM-to-EX Data Forwarding
//                - Load-Use Hazard 1-Cycle Stall
//                - Branch Misprediction Flushes
//                - Jump (JAL) Pipeline Flushes and Link Register Write
// ============================================================================

`timescale 1ns / 1ps

module tb_cpu_pipe;

    logic        clk;
    logic        rst_n;

    logic [31:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_alu_result;
    logic [31:0] dbg_wb_data;
    logic        dbg_reg_write;
    logic        dbg_stall;
    logic        dbg_flush;

    integer pass_count;
    integer fail_count;
    integer test_num;

    // Instantiate 5-Stage Pipelined CPU
    cpu_pipe #(
        .RESET_ADDR (32'h0000_0000),
        .MEM_DEPTH  (1024),
        .INIT_FILE  ("../sw/test_pipe.hex")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .timer_irq       (1'b0),
        .external_irq    (1'b0),
        .priv_mode_out   (),
        .satp_out        (),
        .ext_mem_rdata   (32'b0),
        .ext_instr_rdata (32'b0),
        .dbg_pc        (dbg_pc),
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
            $display("  [PASS] Test %0d: %s -> x%0d = 0x%08h (%0d)",
                     test_num, test_name, reg_idx, actual_val, actual_val);
            pass_count++;
        end
    endtask

    initial begin
        $dumpfile("cpu_pipe_tb.vcd");
        $dumpvars(0, tb_cpu_pipe);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK 5-Stage Pipelined RV32I CPU — Hazard Verification");
        $display("==========================================================");

        // Apply Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // Run for 35 clock cycles to complete program pipeline flow
        repeat (35) begin
            @(posedge clk);
            #1;
        end

        $display("");
        $display("--- Verifying Architectural Register File State ---");

        // 1. RAW Hazard Forwarding
        check_reg(1, 32'd10, "x1 = 10 (Base immediate)");
        check_reg(2, 32'd15, "x2 = 15 (EX-to-EX forward x1 to addi)");
        check_reg(3, 32'd25, "x3 = 25 (Double forward x1 & x2 to add)");

        // 2. Memory & Load-Use Hazard Stall
        check_reg(4, 32'd25, "x4 = 25 (LW from memory)");
        check_reg(5, 32'd26, "x5 = 26 (LOAD-USE HAZARD: 1-cycle stall + forward)");

        // 3. Control Hazard: Branch Taken Flushes
        check_reg(6, 32'd0,  "x6 = 0  (Branch flushed younger instruction 1)");
        check_reg(7, 32'd0,  "x7 = 0  (Branch flushed younger instruction 2)");
        check_reg(8, 32'd77, "x8 = 77 (Branch destination executed successfully)");

        // 4. Jump Hazard: JAL Link Register & Flush
        check_reg(9,  32'h0000_002C, "x9 = 0x2C (JAL saved return address PC+4)");
        check_reg(10, 32'd0,         "x10 = 0 (JAL flushed younger instruction)");
        check_reg(11, 32'd1,         "x11 = 1 (Jump destination executed successfully)");

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) begin
            $display("  STATUS:  ALL TESTS PASSED — 5-STAGE PIPELINE VERIFIED!");
        end else begin
            $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        end
        $display("==========================================================");
        $display("");

        $finish;
    end

endmodule
