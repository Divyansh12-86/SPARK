// ============================================================================
// File:        tb_pim_ctrl.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Unit Testbench for PIM Master Execution Controller.
// ============================================================================

`timescale 1ns/1ps

module tb_pim_ctrl;
    import riscv_pkg::*;

    localparam int BUFFER_LINES = 64;
    localparam int ADDR_W = 6;

    logic                     clk;
    logic                     rst_n;

    // CPU Command Interface
    logic                     cmd_valid;
    logic                     cmd_ready;
    pim_op_t                  cmd_op;
    logic [31:0]              cmd_rs1_val;
    logic [31:0]              cmd_rs2_val;
    logic [31:0]              cmd_rd_val;
    logic                     cmd_done;

    // Buffer A Control Interface
    logic                     buf_a_en;
    logic                     buf_a_we;
    logic [ADDR_W-1:0]        buf_a_addr;
    logic [7:0][31:0]         buf_a_wdata;
    logic [7:0][31:0]         buf_a_rdata;

    // Buffer B Control Interface
    logic                     buf_b_en;
    logic                     buf_b_we;
    logic [ADDR_W-1:0]        buf_b_addr;
    logic [7:0][31:0]         buf_b_wdata;
    logic [7:0][31:0]         buf_b_rdata;

    // SIMD ALU Interface
    logic                     alu_en;
    pim_op_t                  alu_op;
    logic [7:0][31:0]         alu_vec_a;
    logic [7:0][31:0]         alu_vec_b;
    logic [31:0]              alu_scalar_in;
    logic [7:0][31:0]         alu_result_vec;
    logic [31:0]              alu_reduction_out;

    // SoC Interface
    logic                     pim_busy;
    logic                     pim_irq;
    logic [31:0]              perf_cycle_cnt;

    int pass_count = 0;
    int fail_count = 0;

    // Instantiate Controller
    pim_ctrl #(
        .BUFFER_LINES(BUFFER_LINES)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .cmd_op           (cmd_op),
        .cmd_rs1_val      (cmd_rs1_val),
        .cmd_rs2_val      (cmd_rs2_val),
        .cmd_rd_val       (cmd_rd_val),
        .cmd_done         (cmd_done),
        .buf_a_en         (buf_a_en),
        .buf_a_we         (buf_a_we),
        .buf_a_addr       (buf_a_addr),
        .buf_a_wdata      (buf_a_wdata),
        .buf_a_rdata      (buf_a_rdata),
        .buf_b_en         (buf_b_en),
        .buf_b_we         (buf_b_we),
        .buf_b_addr       (buf_b_addr),
        .buf_b_wdata      (buf_b_wdata),
        .buf_b_rdata      (buf_b_rdata),
        .alu_en           (alu_en),
        .alu_op           (alu_op),
        .alu_vec_a        (alu_vec_a),
        .alu_vec_b        (alu_vec_b),
        .alu_scalar_in    (alu_scalar_in),
        .alu_result_vec   (alu_result_vec),
        .alu_reduction_out(alu_reduction_out),
        .pim_busy         (pim_busy),
        .pim_irq          (pim_irq),
        .perf_cycle_cnt   (perf_cycle_cnt)
    );

    // Instantiate SIMD ALU
    pim_simd_alu #(
        .LANES(8)
    ) u_simd_alu (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (alu_en),
        .op           (alu_op),
        .vec_a        (alu_vec_a),
        .vec_b        (alu_vec_b),
        .scalar_in    (alu_scalar_in),
        .result_vec   (alu_result_vec),
        .reduction_out(alu_reduction_out)
    );

    // Instantiate actual dual-ported PIM buffers for A and B
    logic                    buf_a_b_en = 0;
    logic                    buf_a_b_we = 0;
    logic [ADDR_W+2:0]       buf_a_b_addr = 0;
    logic [31:0]             buf_a_b_wdata = 0;
    logic [31:0]             buf_a_b_rdata;

    logic                    buf_b_b_en = 0;
    logic                    buf_b_b_we = 0;
    logic [ADDR_W+2:0]       buf_b_b_addr = 0;
    logic [31:0]             buf_b_b_wdata = 0;
    logic [31:0]             buf_b_b_rdata;

    pim_buffer #(
        .DEPTH(BUFFER_LINES),
        .ADDR_WIDTH(ADDR_W)
    ) u_buf_a (
        .clk        (clk),
        .rst_n      (rst_n),
        .porta_en   (buf_a_en),
        .porta_we   (buf_a_we),
        .porta_addr (buf_a_addr),
        .porta_wdata(buf_a_wdata),
        .porta_rdata(buf_a_rdata),
        .portb_en   (buf_a_b_en),
        .portb_we   (buf_a_b_we),
        .portb_addr (buf_a_b_addr),
        .portb_wdata(buf_a_b_wdata),
        .portb_rdata(buf_a_b_rdata)
    );

    pim_buffer #(
        .DEPTH(BUFFER_LINES),
        .ADDR_WIDTH(ADDR_W)
    ) u_buf_b (
        .clk        (clk),
        .rst_n      (rst_n),
        .porta_en   (buf_b_en),
        .porta_we   (buf_b_we),
        .porta_addr (buf_b_addr),
        .porta_wdata(buf_b_wdata),
        .porta_rdata(buf_b_rdata),
        .portb_en   (buf_b_b_en),
        .portb_we   (buf_b_b_we),
        .portb_addr (buf_b_b_addr),
        .portb_wdata(buf_b_b_wdata),
        .portb_rdata(buf_b_b_rdata)
    );

    always #5 clk = ~clk;

    task write_word_a(input [ADDR_W+2:0] addr, input [31:0] data);
        @(posedge clk);
        buf_a_b_en    = 1;
        buf_a_b_we    = 1;
        buf_a_b_addr  = addr;
        buf_a_b_wdata = data;
        @(posedge clk);
        buf_a_b_en    = 0;
        buf_a_b_we    = 0;
    endtask

    task write_word_b(input [ADDR_W+2:0] addr, input [31:0] data);
        @(posedge clk);
        buf_b_b_en    = 1;
        buf_b_b_we    = 1;
        buf_b_b_addr  = addr;
        buf_b_b_wdata = data;
        @(posedge clk);
        buf_b_b_en    = 0;
        buf_b_b_we    = 0;
    endtask

    task read_word_a(input [ADDR_W+2:0] addr, output [31:0] data);
        @(posedge clk);
        buf_a_b_en    = 1;
        buf_a_b_we    = 0;
        buf_a_b_addr  = addr;
        @(posedge clk);
        #1;
        data          = buf_a_b_rdata;
        buf_a_b_en    = 0;
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        cmd_valid = 0;
        cmd_op = PIM_VADD;
        cmd_rs1_val = 0;
        cmd_rs2_val = 0;

        #20;
        rst_n = 1;

        // Preload buffers via Port B
        for (int i = 0; i < 16; i++) begin
            write_word_a(i[ADDR_W+2:0], 32'd10);
            write_word_b(i[ADDR_W+2:0], 32'd20);
        end

        $display("=== PIM Controller Unit Verification Start ===");

        // Test 1: PIM_CFG (Set vector length = 16 elements = 2 lines)
        @(posedge clk);
        cmd_valid   = 1;
        cmd_op      = PIM_CFG;
        cmd_rs1_val = 32'd16;       // 16 elements
        cmd_rs2_val = 32'h0000_0000; // Line base 0 for A and B
        @(posedge clk);
        cmd_valid   = 0;

        // Wait for command completion
        wait(cmd_done);
        #1;
        if (cmd_rd_val[15:0] == 16'd16) begin
            $display("[PASS] PIM_CFG: vlen configured to 16 elements");
            pass_count++;
        end else begin
            $error("[FAIL] PIM_CFG: Expected vlen 16, Got %0d", cmd_rd_val[15:0]);
            fail_count++;
        end

        @(posedge clk);

        // Test 2: PIM_VADD across the 2 lines (16 elements)
        cmd_valid   = 1;
        cmd_op      = PIM_VADD;
        cmd_rs1_val = 32'd0;
        cmd_rs2_val = 32'd0;
        @(posedge clk);
        cmd_valid   = 0;

        wait(cmd_done);
        #1;
        if (cmd_done && pim_irq) begin
            $display("[PASS] PIM_VADD execution complete and IRQ fired");
            pass_count++;
        end else begin
            $error("[FAIL] PIM_VADD did not complete cleanly");
            fail_count++;
        end

        // Verify buffer A contents after VADD (10 + 20 = 30)
        for (int l = 0; l < 2; l++) begin
            for (int w = 0; w < 8; w++) begin
                logic [31:0] rdata;
                read_word_a({l[ADDR_W-1:0], w[2:0]}, rdata);
                if (rdata == 32'd30) begin
                    pass_count++;
                end else begin
                    $error("[FAIL] buf_a[%0d][%0d]: Expected 30, Got %0d", l, w, rdata);
                    fail_count++;
                end
            end
        end

        @(posedge clk);

        // Test 3: PIM_VSUM across the 2 lines (16 elements of value 30 -> 16 * 30 = 480)
        cmd_valid   = 1;
        cmd_op      = PIM_VSUM;
        @(posedge clk);
        cmd_valid   = 0;

        wait(cmd_done);
        #1;
        if (cmd_rd_val == 32'd480) begin
            $display("[PASS] PIM_VSUM reduction sum matched 480");
            pass_count++;
        end else begin
            $error("[FAIL] PIM_VSUM: Expected 480, Got %0d", cmd_rd_val);
            fail_count++;
        end

        $display("=== PIM Controller Summary: %0d Passed, %0d Failed ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL PIM CONTROLLER TESTS PASSED!");
        $finish;
    end

endmodule
