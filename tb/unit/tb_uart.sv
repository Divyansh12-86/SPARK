// ============================================================================
// File:        tb_uart.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for 16550 UART module.
// ============================================================================

`timescale 1ns / 1ps

module tb_uart;

    logic        clk;
    logic        rst_n;
    logic        cs;
    logic        read_en;
    logic        write_en;
    logic [2:0]  addr;
    logic [31:0] write_data;
    logic [31:0] read_data;
    logic        tx;
    logic        rx;
    logic        uart_irq;

    integer pass_count;
    integer fail_count;
    integer test_num;

    // Fast simulation configuration: 4 clocks per bit
    uart #(
        .CLKS_PER_BIT(4)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cs         (cs),
        .read_en    (read_en),
        .write_en   (write_en),
        .addr       (addr),
        .write_data (write_data),
        .read_data  (read_data),
        .tx         (tx),
        .rx         (rx),
        .mouse_x    (10'd0),
        .mouse_y    (9'd0),
        .mouse_btn  (3'd0),
        .uart_irq   (uart_irq)
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

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        cs         = 0;
        read_en    = 0;
        write_en   = 0;
        addr       = 0;
        write_data = 0;
        rx         = 1;

        $display("");
        $display("==========================================================");
        $display("  SPARK 16550 UART Testbench");
        $display("==========================================================");

        // 1. Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        check("Initial TX pin is IDLE (1)", {31'b0, tx}, 32'd1);

        // 2. Read LSR (offset 5): THRE bit 5 should be 1 (empty)
        cs      = 1'b1;
        read_en = 1'b1;
        addr    = 3'h5;
        #1;
        check("LSR bit 5 (THRE) is 1 (Transmitter empty)", (read_data & 32'h20), 32'h20);
        read_en = 1'b0;

        // 3. Write character 'A' (0x41) to THR (offset 0)
        write_en   = 1'b1;
        addr       = 3'h0;
        write_data = 32'h0000_0041;
        @(posedge clk);
        #1;
        write_en   = 1'b0;
        cs         = 1'b0;

        // Wait for FSM transition from IDLE -> START
        @(posedge clk);
        @(posedge clk);
        #1;
        check("Start bit is asserted LOW (0)", {31'b0, tx}, 32'd0);

        // Wait for full transmission (Start + 8 data + Stop = 10 bits * 4 clocks = 40 clocks)
        repeat (45) @(posedge clk);
        #1;

        check("After transmission TX returns to IDLE (1)", {31'b0, tx}, 32'd1);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
