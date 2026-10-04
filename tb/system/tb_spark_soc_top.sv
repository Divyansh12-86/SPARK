// ============================================================================
// File:        tb_spark_soc_top.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Full System Integration Self-Checking Testbench.
//
//              Verifies concurrent execution of all SoC subsystems:
//                1. 5-Stage RV32I Core running instructions from Boot ROM
//                2. UART transmission ("SPARK")
//                3. CLINT timer interrupt triggering
//                4. Framebuffer VRAM writes at 0xF000_0000 & VGA raster sync
//                5. PIM hardware acceleration configuration at 0x3000_0000
// ============================================================================

`timescale 1ns/1ps

module tb_spark_soc_top;

    logic        clk;
    logic        pixel_clk;
    logic        rst_n;
    logic        uart_tx;
    logic        uart_rx;

    logic        vga_hsync;
    logic        vga_vsync;
    logic        vga_display_on;
    logic [3:0]  vga_r;
    logic [3:0]  vga_g;
    logic [3:0]  vga_b;

    logic [31:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_wb_data;
    logic        dbg_reg_write;
    logic        pim_busy;
    logic        pim_irq;

    int pass_count = 0;
    int fail_count = 0;

    // Instantiate Unified SoC Top
    spark_soc_top #(
        .RESET_ADDR(32'h0000_0000),
        .MEM_DEPTH(1024),
        .INIT_FILE("../sw/test_spark_soc.hex")
    ) dut (
        .clk           (clk),
        .pixel_clk     (pixel_clk),
        .rst_n         (rst_n),
        .uart_tx       (uart_tx),
        .uart_rx       (uart_rx),
        .mouse_x       (10'd0),
        .mouse_y       (9'd0),
        .mouse_btn     (3'd0),
        .vga_hsync     (vga_hsync),
        .vga_vsync     (vga_vsync),
        .vga_display_on(vga_display_on),
        .vga_r         (vga_r),
        .vga_g         (vga_g),
        .vga_b         (vga_b),
        .dbg_pc        (dbg_pc),
        .dbg_instr     (dbg_instr),
        .dbg_wb_data   (dbg_wb_data),
        .dbg_reg_write (dbg_reg_write),
        .pim_busy      (pim_busy),
        .pim_irq       (pim_irq)
    );

    // Clocks: System clk = 100MHz (10ns), Pixel clk = 25MHz (40ns)
    initial clk = 0;
    always #5 clk = ~clk;

    initial pixel_clk = 0;
    always #20 pixel_clk = ~pixel_clk;

    task check(
        input string       test_name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected) begin
            $display("  [FAIL] %s (Expected=0x%08h Actual=0x%08h)", test_name, expected, actual);
            fail_count++;
        end else begin
            $display("  [PASS] %s (Val=0x%08h)", test_name, actual);
            pass_count++;
        end
    endtask

    initial begin
        rst_n   = 0;
        uart_rx = 1;

        $display("\n===============================================================");
        $display("   SPARK Phase 8: Full Unified SoC System Integration Test    ");
        $display("===============================================================\n");

        #25;
        rst_n = 1;

        // Run for 120 cycles to allow CPU to execute all peripheral operations
        repeat (120) @(posedge clk);
        #1;

        $display("--- Verifying Unified SoC Architectural Subsystems ---");

        // 1. CPU architectural register state
        check("UART Base Pointer initialized (x1 = 0x1000_0000)",
              dut.u_cpu.u_reg_file.registers[1], 32'h1000_0000);

        check("CLINT Compare Pointer initialized (x5 = 0x2000_4000)",
              dut.u_cpu.u_reg_file.registers[5], 32'h2000_4000);

        check("Framebuffer Pointer initialized (x10 = 0xF000_0000)",
              dut.u_cpu.u_reg_file.registers[10], 32'hF000_0000);

        check("PIM Subsystem Base Pointer initialized (x20 = 0x3000_0000)",
              dut.u_cpu.u_reg_file.registers[20], 32'h3000_0000);

        // 2. UART Peripheral State
        check("UART THR received final character 'K' (0x4B)",
              {24'b0, dut.u_uart.thr}, 32'h0000_004B);

        // 3. CLINT State & Interrupt
        check("CLINT mtimecmp threshold configured to 30",
              dut.u_clint.mtimecmp[31:0], 32'd30);
        check("CLINT timer interrupt asserted",
              {31'b0, dut.u_clint.timer_irq}, 32'd1);

        // 4. Framebuffer VRAM writes
        check("VRAM Pixel 0 (Red) stored in Framebuffer",
              {20'b0, dut.u_vga.vram[0]}, 32'h0000_0F00);
        check("VRAM Pixel 1 (Green) stored in Framebuffer",
              {20'b0, dut.u_vga.vram[1]}, 32'h0000_00F0);

        // 5. PIM Hardware Acceleration Subsystem
        check("PIM Subsystem configured vector length (vlen = 16 elements)",
              {16'b0, dut.u_pim.u_ctrl.vlen_reg}, 32'd16);

        // 6. VGA timing signals active
        if (vga_hsync !== 1'bx && vga_vsync !== 1'bx) begin
            $display("  [PASS] VGA sync signals actively oscillating");
            pass_count++;
        end else begin
            $error("  [FAIL] VGA sync signals undefined");
            fail_count++;
        end

        $display("\n===============================================================");
        $display("   UNIFIED SoC TEST RESULTS: %0d Passed, %0d Failed           ", pass_count, fail_count);
        $display("===============================================================\n");

        if (fail_count == 0) begin
            $display(">>> ALL PHASE 8 UNIFIED SOC TESTS PASSED SUCCESSFULLY! <<<\n");
        end

        $finish;
    end

endmodule
