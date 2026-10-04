// ============================================================================
// File:        tb_soc_top.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: System-Level Self-Checking Testbench for SPARK SoC.
//              Verifies:
//                - Pipelined CPU core fetching instructions from Boot ROM
//                - Memory-mapped writes to 16550 UART (transmitting "SPARK")
//                - Memory-mapped configuration of CLINT timer compare
//                - Timer interrupt trigger from CLINT
// ============================================================================

`timescale 1ns / 1ps

module tb_soc_top;

    logic        clk;
    logic        rst_n;
    logic        uart_tx;
    logic        uart_rx;

    logic [31:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_wb_data;
    logic        dbg_reg_write;

    integer pass_count;
    integer fail_count;
    integer test_num;

    // Instantiate SoC Top with test program
    soc_top #(
        .RESET_ADDR (32'h0000_0000),
        .MEM_DEPTH  (1024),
        .INIT_FILE  ("../sw/test_soc.hex")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .uart_tx       (uart_tx),
        .uart_rx       (uart_rx),
        .dbg_pc        (dbg_pc),
        .dbg_instr     (dbg_instr),
        .dbg_wb_data   (dbg_wb_data),
        .dbg_reg_write (dbg_reg_write)
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
            $display("  [FAIL] Test %0d: %s (Expected=0x%08h Actual=0x%08h)",
                     test_num, test_name, expected, actual);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Val=0x%08h)", test_num, test_name, actual);
            pass_count++;
        end
    endtask

    initial begin
        $dumpfile("soc_top_tb.vcd");
        $dumpvars(0, tb_soc_top);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        uart_rx    = 1'b1;

        $display("");
        $display("==========================================================");
        $display("  SPARK System-on-Chip (SoC) Integration Testbench");
        $display("==========================================================");

        // Reset sequence
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // Run SoC for 60 clock cycles to execute the peripheral test
        repeat (60) begin
            @(posedge clk);
            #1;
        end

        $display("");
        $display("--- Verifying SoC Architectural State ---");

        // 1. CPU register state
        check("x1 holds UART Base Address (0x1000_0000)",
              dut.u_cpu.u_reg_file.registers[1], 32'h1000_0000);

        check("x5 holds CLINT Compare Address (0x2000_4000)",
              dut.u_cpu.u_reg_file.registers[5], 32'h2000_4000);

        check("x6 indicates Program Completion (1)",
              dut.u_cpu.u_reg_file.registers[6], 32'd1);

        // 2. UART Peripheral State
        check("UART THR received final character 'K' (0x4B)",
              {24'b0, dut.u_uart.thr}, 32'h0000_004B);

        // 3. CLINT Timer Compare State
        check("CLINT mtimecmp configured to 20",
              dut.u_clint.mtimecmp[31:0], 32'd20);

        check("CLINT Timer Interrupt is ASSERTED (mtime >= 20)",
              {31'b0, dut.u_clint.timer_irq}, 32'd1);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) begin
            $display("  STATUS:  ALL TESTS PASSED — SoC INTEGRATION VERIFIED!");
        end else begin
            $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        end
        $display("==========================================================");
        $display("");

        $finish;
    end

endmodule
