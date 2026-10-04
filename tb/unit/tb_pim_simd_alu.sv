// ============================================================================
// File:        tb_pim_simd_alu.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Unit Testbench for 8-Lane 32-bit Integer SIMD ALU.
// ============================================================================

`timescale 1ns/1ps

module tb_pim_simd_alu;
    import riscv_pkg::*;

    localparam int LANES = 8;

    logic              clk;
    logic              rst_n;
    logic              en;
    pim_op_t           op;
    logic [LANES-1:0][31:0] vec_a;
    logic [LANES-1:0][31:0] vec_b;
    logic [31:0]       scalar_in;
    logic [LANES-1:0][31:0] result_vec;
    logic [31:0]       reduction_out;

    int pass_count = 0;
    int fail_count = 0;

    pim_simd_alu #(
        .LANES(LANES)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en),
        .op           (op),
        .vec_a        (vec_a),
        .vec_b        (vec_b),
        .scalar_in    (scalar_in),
        .result_vec   (result_vec),
        .reduction_out(reduction_out)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        en = 0;
        op = PIM_VADD;
        vec_a = '0;
        vec_b = '0;
        scalar_in = '0;

        #20;
        rst_n = 1;
        en = 1;

        $display("=== PIM SIMD ALU Unit Verification Start ===");

        // Test 1: PIM_VADD (Parallel vector addition)
        op = PIM_VADD;
        for (int i = 0; i < LANES; i++) begin
            vec_a[i] = 32'd10 * (i + 1);
            vec_b[i] = 32'd5  * (i + 1);
        end
        @(posedge clk);
        #1;
        for (int i = 0; i < LANES; i++) begin
            if (result_vec[i] == (vec_a[i] + vec_b[i])) begin
                pass_count++;
            end else begin
                $error("[FAIL] VADD lane %0d: Expected %0d, Got %0d", i, (vec_a[i] + vec_b[i]), result_vec[i]);
                fail_count++;
            end
        end

        // Test 2: PIM_VMAC (Elementwise parallel multiplication)
        op = PIM_VMAC;
        for (int i = 0; i < LANES; i++) begin
            vec_a[i] = 32'd2 * (i + 1);
            vec_b[i] = 32'd3;
        end
        @(posedge clk);
        #1;
        for (int i = 0; i < LANES; i++) begin
            if (result_vec[i] == (vec_a[i] * vec_b[i])) begin
                pass_count++;
            end else begin
                $error("[FAIL] VMAC lane %0d: Expected %0d, Got %0d", i, (vec_a[i] * vec_b[i]), result_vec[i]);
                fail_count++;
            end
        end

        // Test 3: PIM_VAND (Parallel bitwise AND)
        op = PIM_VAND;
        for (int i = 0; i < LANES; i++) begin
            vec_a[i] = 32'hFFFF_0000;
            vec_b[i] = 32'h0F0F_0F0F;
        end
        @(posedge clk);
        #1;
        for (int i = 0; i < LANES; i++) begin
            if (result_vec[i] == 32'h0F0F_0000) begin
                pass_count++;
            end else begin
                $error("[FAIL] VAND lane %0d: Expected 0x0F0F0000, Got 0x%08h", i, result_vec[i]);
                fail_count++;
            end
        end

        // Test 4: PIM_VSUM (Binary adder tree reduction)
        op = PIM_VSUM;
        for (int i = 0; i < LANES; i++) begin
            vec_a[i] = 32'd10; // 8 * 10 = 80
        end
        @(posedge clk);
        #1;
        if (reduction_out == 32'd80 && result_vec[0] == 32'd80) begin
            $display("[PASS] VSUM: Tree reduction yielded 80");
            pass_count += 2;
        end else begin
            $error("[FAIL] VSUM: Expected 80, Got red=%0d, vec0=%0d", reduction_out, result_vec[0]);
            fail_count++;
        end

        // Test 5: PIM_VFILL (Scalar broadcast)
        op = PIM_VFILL;
        scalar_in = 32'hDEADBEEF;
        @(posedge clk);
        #1;
        for (int i = 0; i < LANES; i++) begin
            if (result_vec[i] == 32'hDEADBEEF) begin
                pass_count++;
            end else begin
                $error("[FAIL] VFILL lane %0d: Expected 0xDEADBEEF, Got 0x%08h", i, result_vec[i]);
                fail_count++;
            end
        end

        $display("=== PIM SIMD ALU Summary: %0d Passed, %0d Failed ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL PIM SIMD ALU TESTS PASSED!");
        $finish;
    end

endmodule
