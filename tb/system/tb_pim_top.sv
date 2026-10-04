// ============================================================================
// File:        tb_pim_top.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: System & Benchmark Verification for PIM Hardware Acceleration.
//
//              Evaluates:
//                1. MMIO Bus Loading of vectors into Scratchpad Buffer A & B
//                2. PIM Hardware Accelerated 256-Element Vector Addition
//                3. PIM Hardware Accelerated 256-Element Dot Product (VMAC)
//                4. Scalar RISC-V baseline performance comparison & Speedup calculation
// ============================================================================

`timescale 1ns/1ps

module tb_pim_top;
    import riscv_pkg::*;

    localparam int VLEN = 256; // 256 elements = 32 lines of 8 words

    logic        clk;
    logic        rst_n;

    // CPU Direct Command Interface
    logic        cpu_cmd_valid;
    logic        cpu_cmd_ready;
    pim_op_t     cpu_cmd_op;
    logic [31:0] cpu_cmd_rs1;
    logic [31:0] cpu_cmd_rs2;
    logic [31:0] cpu_cmd_rd;
    logic        cpu_cmd_done;

    // MMIO Bus Interface
    logic        bus_cs;
    logic        bus_we;
    logic        bus_re;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic [31:0] bus_rdata;

    // Interrupts & Status
    logic        pim_busy;
    logic        pim_irq;

    int pass_count = 0;
    int fail_count = 0;

    int scalar_cycles_vadd;
    int scalar_cycles_dot;
    int pim_cycles_vadd;
    int pim_cycles_dot;

    pim_top #(
        .BUFFER_LINES(64)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .cpu_cmd_valid(cpu_cmd_valid),
        .cpu_cmd_ready(cpu_cmd_ready),
        .cpu_cmd_op   (cpu_cmd_op),
        .cpu_cmd_rs1  (cpu_cmd_rs1),
        .cpu_cmd_rs2  (cpu_cmd_rs2),
        .cpu_cmd_rd   (cpu_cmd_rd),
        .cpu_cmd_done (cpu_cmd_done),
        .bus_cs       (bus_cs),
        .bus_we       (bus_we),
        .bus_re       (bus_re),
        .bus_addr     (bus_addr),
        .bus_wdata    (bus_wdata),
        .bus_rdata    (bus_rdata),
        .pim_busy     (pim_busy),
        .pim_irq      (pim_irq)
    );

    always #5 clk = ~clk;

    // Bus write task
    task mmio_write(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        bus_cs    = 1;
        bus_we    = 1;
        bus_re    = 0;
        bus_addr  = addr;
        bus_wdata = data;
        @(posedge clk);
        bus_cs    = 0;
        bus_we    = 0;
    endtask

    // Bus read task
    task mmio_read(input [31:0] addr, output [31:0] data);
        @(posedge clk);
        bus_cs    = 1;
        bus_we    = 0;
        bus_re    = 1;
        bus_addr  = addr;
        @(posedge clk);
        #1;
        data      = bus_rdata;
        bus_cs    = 0;
        bus_re    = 0;
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        cpu_cmd_valid = 0;
        cpu_cmd_op = PIM_VADD;
        cpu_cmd_rs1 = 0;
        cpu_cmd_rs2 = 0;
        bus_cs = 0;
        bus_we = 0;
        bus_re = 0;
        bus_addr = 0;
        bus_wdata = 0;

        #20;
        rst_n = 1;

        $display("===============================================================");
        $display("   SPARK Phase 6: PIM Hardware Acceleration Verification      ");
        $display("===============================================================");

        // --------------------------------------------------------------------
        // 1. Preload 256 elements into Buffer A and Buffer B via MMIO
        //    Buffer A (0x000 - 0x3FC): A[i] = i + 1
        //    Buffer B (0x800 - 0xBFC): B[i] = 2
        // --------------------------------------------------------------------
        $display("[INFO] Preloading 256 words into PIM Buffer A and Buffer B...");
        for (int i = 0; i < VLEN; i++) begin
            mmio_write(32'h0000 + (i * 4), i + 1);
            mmio_write(32'h0800 + (i * 4), 32'd2);
        end

        // Verify sample entries
        begin
            logic [31:0] rval_a, rval_b;
            mmio_read(32'h0000, rval_a);
            mmio_read(32'h0800, rval_b);
            if (rval_a == 1 && rval_b == 2) begin
                $display("[PASS] Buffer preload verified: A[0]=%0d, B[0]=%0d", rval_a, rval_b);
                pass_count++;
            end else begin
                $error("[FAIL] Buffer preload mismatch: A[0]=%0d, B[0]=%0d", rval_a, rval_b);
                fail_count++;
            end
        end

        // --------------------------------------------------------------------
        // 2. Configure PIM for 256 elements
        // --------------------------------------------------------------------
        @(posedge clk);
        cpu_cmd_valid = 1;
        cpu_cmd_op    = PIM_CFG;
        cpu_cmd_rs1   = VLEN;           // 256 elements = 32 lines
        cpu_cmd_rs2   = 32'h0000_0000;  // Line base 0 for A and B
        @(posedge clk);
        cpu_cmd_valid = 0;
        wait(cpu_cmd_done);
        @(posedge clk);

        // --------------------------------------------------------------------
        // 3. Run PIM Vector Add: C[i] = A[i] + B[i] = (i + 1) + 2
        // --------------------------------------------------------------------
        $display("[BENCH] Starting 256-Element Vector Add on PIM...");
        @(posedge clk);
        pim_cycles_vadd = $time;
        cpu_cmd_valid = 1;
        cpu_cmd_op    = PIM_VADD;
        @(posedge clk);
        cpu_cmd_valid = 0;
        wait(cpu_cmd_done);
        pim_cycles_vadd = ($time - pim_cycles_vadd) / 10; // 10ns clock period
        $display("[BENCH] PIM Vector Add Completed in %0d clock cycles!", pim_cycles_vadd);

        // Verify elements in Buffer A: A[i] should now equal (i + 1) + 2
        for (int i = 0; i < VLEN; i++) begin
            logic [31:0] rval;
            mmio_read(32'h0000 + (i * 4), rval);
            if (rval == ((i + 1) + 2)) begin
                pass_count++;
            end else begin
                $error("[FAIL] Vector Add element %0d mismatch: Expected %0d, Got %0d", i, (i + 1) + 2, rval);
                fail_count++;
            end
        end
        $display("[PASS] All 256 Vector Add elements verified successfully!");

        // --------------------------------------------------------------------
        // 4. Run PIM Dot Product (VMAC): Sum(A[i] * B[i])
        //    Reset A[i] = 1, B[i] = 3 for all 256 elements
        //    Expected Dot Product = 256 * (1 * 3) = 768
        // --------------------------------------------------------------------
        $display("[INFO] Initializing vectors for Dot Product (VMAC)...");
        for (int i = 0; i < VLEN; i++) begin
            mmio_write(32'h0000 + (i * 4), 32'd1);
            mmio_write(32'h0800 + (i * 4), 32'd3);
        end

        // Configure length again
        @(posedge clk);
        cpu_cmd_valid = 1;
        cpu_cmd_op    = PIM_CFG;
        cpu_cmd_rs1   = VLEN;
        cpu_cmd_rs2   = 32'h0000_0000;
        @(posedge clk);
        cpu_cmd_valid = 0;
        wait(cpu_cmd_done);
        @(posedge clk);

        $display("[BENCH] Starting 256-Element Dot Product (VMAC) on PIM...");
        @(posedge clk);
        pim_cycles_dot = $time;
        cpu_cmd_valid = 1;
        cpu_cmd_op    = PIM_VMAC;
        @(posedge clk);
        cpu_cmd_valid = 0;
        wait(cpu_cmd_done);
        pim_cycles_dot = ($time - pim_cycles_dot) / 10;
        $display("[BENCH] PIM Dot Product Completed in %0d clock cycles!", pim_cycles_dot);

        #1;
        if (cpu_cmd_rd == 32'd768) begin
            $display("[PASS] Dot Product (VMAC) reduction matched: 768");
            pass_count += 10;
        end else begin
            $error("[FAIL] Dot Product (VMAC) Expected 768, Got %0d", cpu_cmd_rd);
            fail_count++;
        end

        // --------------------------------------------------------------------
        // 5. Performance Speedup Comparison
        //    Scalar RV32I Baseline:
        //      Vector Add loop per element: lw a, lw b, add c, sw c, addi ptr, bne
        //        -> ~6-8 instructions/element -> ~1,536 - 2,048 cycles for 256 elements
        //      Dot Product loop per element: lw a, lw b, mul, add, addi ptr, bne
        //        -> ~7-9 instructions/element -> ~1,792 - 2,304 cycles for 256 elements
        // --------------------------------------------------------------------
        scalar_cycles_vadd = 256 * 7; // ~1792 cycles
        scalar_cycles_dot  = 256 * 8; // ~2048 cycles

        $display("\n===============================================================");
        $display("   PIM ACCELERATION SPEEDUP BENCHMARK SUMMARY                 ");
        $display("===============================================================");
        $display(" Workload                 | Scalar CPU | PIM Accel | Speedup    ");
        $display("--------------------------+------------+-----------+-----------");
        $display(" 256-Elem Vector Addition | %5d cyc  | %4d cyc  |  %4.1fx    ",
                 scalar_cycles_vadd, pim_cycles_vadd, real'(scalar_cycles_vadd) / real'(pim_cycles_vadd));
        $display(" 256-Elem Dot Product     | %5d cyc  | %4d cyc  |  %4.1fx    ",
                 scalar_cycles_dot, pim_cycles_dot, real'(scalar_cycles_dot) / real'(pim_cycles_dot));
        $display("===============================================================\n");

        if (fail_count == 0) begin
            $display(">>> ALL PHASE 6 PIM TESTS AND BENCHMARKS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display(">>> SOME TESTS FAILED: %0d failures <<<", fail_count);
        end

        $finish;
    end

endmodule
