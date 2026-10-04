// ============================================================================
// File:        tb_pim_buffer.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Unit Testbench for Dual-Ported 256-bit Near-Memory SRAM Buffer.
// ============================================================================

`timescale 1ns/1ps

module tb_pim_buffer;

    localparam int DEPTH = 64;
    localparam int ADDR_W = 6;

    logic                 clk;
    logic                 rst_n;

    // Port A (256-bit wide)
    logic                 porta_en;
    logic                 porta_we;
    logic [ADDR_W-1:0]    porta_addr;
    logic [7:0][31:0]     porta_wdata;
    logic [7:0][31:0]     porta_rdata;

    // Port B (32-bit word)
    logic                 portb_en;
    logic                 portb_we;
    logic [ADDR_W+2:0]    portb_addr;
    logic [31:0]          portb_wdata;
    logic [31:0]          portb_rdata;

    int pass_count = 0;
    int fail_count = 0;

    pim_buffer #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_W)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .porta_en   (porta_en),
        .porta_we   (porta_we),
        .porta_addr (porta_addr),
        .porta_wdata(porta_wdata),
        .porta_rdata(porta_rdata),
        .portb_en   (portb_en),
        .portb_we   (portb_we),
        .portb_addr (portb_addr),
        .portb_wdata(portb_wdata),
        .portb_rdata(portb_rdata)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        porta_en = 0;
        porta_we = 0;
        porta_addr = '0;
        porta_wdata = '0;
        portb_en = 0;
        portb_we = 0;
        portb_addr = '0;
        portb_wdata = '0;

        #20;
        rst_n = 1;

        $display("=== PIM Buffer Unit Verification Start ===");

        // Test 1: Write 256-bit line via Port A, read back via Port A
        @(posedge clk);
        porta_en   = 1;
        porta_we   = 1;
        porta_addr = 6'd0;
        for (int i = 0; i < 8; i++) begin
            porta_wdata[i] = 32'h1000 + i;
        end

        @(posedge clk);
        porta_we   = 0;
        porta_addr = 6'd0;

        @(posedge clk);
        #1;
        for (int i = 0; i < 8; i++) begin
            if (porta_rdata[i] == (32'h1000 + i)) begin
                pass_count++;
            end else begin
                $error("[FAIL] Port A readback idx %0d: Expected %08h, Got %08h", i, 32'h1000 + i, porta_rdata[i]);
                fail_count++;
            end
        end

        // Test 2: Read individual words of Line 0 via Port B
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            portb_en   = 1;
            portb_we   = 0;
            portb_addr = {6'd0, i[2:0]};
            @(posedge clk);
            #1;
            if (portb_rdata == (32'h1000 + i)) begin
                pass_count++;
            end else begin
                $error("[FAIL] Port B readback word %0d: Expected %08h, Got %08h", i, 32'h1000 + i, portb_rdata);
                fail_count++;
            end
        end

        // Test 3: Write via Port B, read via Port A
        // Write line 2 word 3 = 0xCAFEBABE
        @(posedge clk);
        portb_en   = 1;
        portb_we   = 1;
        portb_addr = {6'd2, 3'd3};
        portb_wdata = 32'hCAFEBABE;

        @(posedge clk);
        portb_we   = 0;
        porta_en   = 1;
        porta_we   = 0;
        porta_addr = 6'd2;

        @(posedge clk);
        #1;
        if (porta_rdata[3] == 32'hCAFEBABE) begin
            $display("[PASS] Port B write -> Port A read matched");
            pass_count++;
        end else begin
            $error("[FAIL] Port B write -> Port A read mismatch: Got %08h", porta_rdata[3]);
            fail_count++;
        end

        $display("=== PIM Buffer Summary: %0d Passed, %0d Failed ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL PIM BUFFER TESTS PASSED!");
        $finish;
    end

endmodule
