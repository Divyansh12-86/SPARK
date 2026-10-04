// ============================================================================
// File:        tb_dcache.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for L1 Data Cache.
// ============================================================================

`timescale 1ns / 1ps

module tb_dcache;

    logic        clk;
    logic        rst_n;

    logic        req_valid;
    logic        we;
    logic [2:0]  funct3;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        hit;
    logic        stall;

    logic        mem_req;
    logic        mem_we;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic        mem_valid;
    logic        mem_ready;

    integer pass_count;
    integer fail_count;
    integer test_num;

    dcache dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (req_valid),
        .we        (we),
        .funct3    (funct3),
        .addr      (addr),
        .wdata     (wdata),
        .rdata     (rdata),
        .hit       (hit),
        .stall     (stall),

        .mem_req   (mem_req),
        .mem_we    (mem_we),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_valid (mem_valid),
        .mem_ready (mem_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Emulate main memory responding to refill & writeback
    assign mem_rdata = mem_addr + 32'h0000_1000;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mem_ready <= 1'b0;
            mem_valid <= 1'b0;
        end else if (mem_req) begin
            mem_ready <= 1'b1;
            mem_valid <= !mem_we; // Valid data on read
        end else begin
            mem_ready <= 1'b0;
            mem_valid <= 1'b0;
        end
    end

    task check(
        input string       test_name,
        input logic        exp_hit,
        input logic [31:0] exp_data
    );
        test_num++;
        if (hit !== exp_hit || (exp_hit && !we && rdata !== exp_data)) begin
            $display("  [FAIL] Test %0d: %s (Hit: Exp=%0b Act=%0b | Data: Exp=0x%08h Act=0x%08h)",
                     test_num, test_name, exp_hit, hit, exp_data, rdata);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Hit=%0b Data=0x%08h)", test_num, test_name, hit, rdata);
            pass_count++;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        req_valid  = 0;
        we         = 0;
        funct3     = 3'b010; // Word access
        addr       = 0;
        wdata      = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK L1 Data Cache (4-Way Set-Assoc Write-Back) Testbench");
        $display("==========================================================");

        // 1. Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // 2. Read Miss at 0x8000_0100
        addr      = 32'h8000_0100;
        req_valid = 1'b1;
        we        = 1'b0;
        #1;
        check("Initial Read is a cache MISS", 1'b0, 32'b0);

        // Wait for refill burst
        while (stall) @(posedge clk);
        #1;

        // 3. Read Hit after refill
        #1;
        check("Read after refill is a cache HIT", 1'b1, 32'h8000_0100 + 32'h0000_1000);

        // 4. Write Hit (SW at 0x8000_0100 with 0xDEADBEEF)
        we    = 1'b1;
        wdata = 32'hDEAD_BEEF;
        @(posedge clk);
        #1;
        check("Write to cached line is a write HIT", 1'b1, 32'b0);

        // 5. Read back modified data (LW)
        we = 1'b0;
        #1;
        check("Read back modified data returns 0xDEADBEEF", 1'b1, 32'hDEAD_BEEF);
        req_valid = 1'b0;

        // 6. MMIO Uncached Access (UART at 0x1000_0000)
        @(posedge clk);
        addr      = 32'h1000_0000;
        req_valid = 1'b1;
        we        = 1'b1;
        wdata     = 32'h0000_0041;
        #1;
        check("MMIO peripheral access bypasses cache (hit=0)", 1'b0, 32'b0);

        // Wait for MMIO transaction to complete on memory bus
        while (dut.state != dut.IDLE && dut.state != dut.FINISH) @(posedge clk);
        @(posedge clk);
        #1;
        req_valid = 1'b0;

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
