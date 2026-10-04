// ============================================================================
// File:        tb_icache.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for L1 Instruction Cache.
// ============================================================================

`timescale 1ns / 1ps

module tb_icache;

    logic        clk;
    logic        rst_n;

    logic        req_valid;
    logic [31:0] addr;
    logic [31:0] rdata;
    logic        hit;
    logic        stall;

    logic        mem_req;
    logic [31:0] mem_addr;
    logic [31:0] mem_rdata;
    logic        mem_valid;

    integer pass_count;
    integer fail_count;
    integer test_num;

    icache dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (req_valid),
        .addr      (addr),
        .rdata     (rdata),
        .hit       (hit),
        .stall     (stall),

        .mem_req   (mem_req),
        .mem_addr  (mem_addr),
        .mem_rdata (mem_rdata),
        .mem_valid (mem_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Emulate main memory serving cache burst refills
    assign mem_rdata = mem_addr + 32'h0013_0000;
    always_ff @(posedge clk) begin
        if (!rst_n) mem_valid <= 1'b0;
        else        mem_valid <= mem_req;
    end

    task check(
        input string       test_name,
        input logic        exp_hit,
        input logic [31:0] exp_data
    );
        test_num++;
        if (hit !== exp_hit || (exp_hit && rdata !== exp_data)) begin
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
        addr       = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK L1 Instruction Cache (2-Way Set-Assoc) Testbench");
        $display("==========================================================");

        // 1. Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // 2. First fetch at 0x0000_1000: Cache MISS
        addr      = 32'h0000_1004; // Word 1 of line 0x1000
        req_valid = 1'b1;
        #1;
        check("Initial fetch is a cache MISS", 1'b0, 32'b0);

        // Wait for refill burst to complete
        while (stall) @(posedge clk);
        #1;

        // 3. Second fetch from same line at 0x0000_1004: Cache HIT
        #1;
        check("Fetch after refill is a cache HIT", 1'b1, 32'h0000_1004 + 32'h0013_0000);

        // 4. Fetch another word from the same 32-byte line (0x0000_1008): immediate HIT
        addr = 32'h0000_1008;
        #1;
        check("Fetch neighboring word in same line is an immediate HIT", 1'b1, 32'h0000_1008 + 32'h0013_0000);
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
