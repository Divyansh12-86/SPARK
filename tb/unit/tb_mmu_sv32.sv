// ============================================================================
// File:        tb_mmu_sv32.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Sv32 MMU and Page Table Walker.
// ============================================================================

`timescale 1ns / 1ps

module tb_mmu_sv32;

    import riscv_pkg::*;

    logic        clk;
    logic        rst_n;

    logic [31:0] satp;
    logic [1:0]  priv_mode;
    logic        sfence_vma;

    logic        req_valid;
    logic [31:0] vaddr;
    logic [1:0]  access_type;
    logic [31:0] paddr;
    logic        paddr_valid;
    logic        page_fault;
    logic        stall;

    logic        walk_req;
    logic [31:0] walk_paddr;
    logic [31:0] walk_rdata;
    logic        walk_ready;

    integer pass_count;
    integer fail_count;
    integer test_num;

    mmu_sv32 dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .satp        (satp),
        .priv_mode   (priv_mode),
        .sfence_vma  (sfence_vma),

        .req_valid   (req_valid),
        .vaddr       (vaddr),
        .access_type (access_type),
        .paddr       (paddr),
        .paddr_valid (paddr_valid),
        .page_fault  (page_fault),
        .stall       (stall),

        .walk_req    (walk_req),
        .walk_paddr  (walk_paddr),
        .walk_rdata  (walk_rdata),
        .walk_ready  (walk_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int walk_step;

    // Emulate memory responding to Page Table Walk requests
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            walk_ready <= 1'b0;
            walk_rdata <= 32'b0;
            walk_step  <= 0;
        end else if (walk_req) begin
            walk_ready <= 1'b1;
            if (walk_step == 0) begin
                // L1 PTE: Points to L0 page table at PPN 0x80100 (V=1, R=0, W=0, X=0)
                walk_rdata <= {2'b00, 20'h80100, 2'b00, 8'h01};
                walk_step  <= 1;
            end else begin
                // L0 PTE: Points to physical frame PPN 0x80500 (V=1, R=1, W=1, U=1 -> 0x17)
                walk_rdata <= {2'b00, 20'h80500, 2'b00, 8'h17};
                walk_step  <= 0;
            end
        end else begin
            walk_ready <= 1'b0;
        end
    end

    task check(
        input string       test_name,
        input logic [31:0] exp_paddr,
        input logic        exp_fault
    );
        test_num++;
        if (page_fault !== exp_fault || (!exp_fault && paddr !== exp_paddr)) begin
            $display("  [FAIL] Test %0d: %s (PAddr: Exp=0x%08h Act=0x%08h | Fault: Exp=%0b Act=%0b)",
                     test_num, test_name, exp_paddr, paddr, exp_fault, page_fault);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (PAddr=0x%08h Fault=%0b)", test_num, test_name, paddr, page_fault);
            pass_count++;
        end
    endtask

    initial begin
        pass_count  = 0;
        fail_count  = 0;
        test_num    = 0;

        satp        = 32'b0;
        priv_mode   = PRIV_U;
        sfence_vma  = 1'b0;
        req_valid   = 1'b0;
        vaddr       = 32'b0;
        access_type = 2'b00;

        $display("");
        $display("==========================================================");
        $display("  SPARK Sv32 MMU & Hardware Page Table Walker Testbench");
        $display("==========================================================");

        // 1. Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // 2. Bare Physical Mode (satp[31] = 0): Direct Passthrough
        satp        = 32'h0000_0000;
        vaddr       = 32'h1000_2004;
        req_valid   = 1'b1;
        access_type = 2'b00;
        @(posedge clk);
        #1;
        check("Bare physical translation (satp=0) passes address through", 32'h1000_2004, 1'b0);
        req_valid = 1'b0;

        // 3. Enable Sv32 Paging: satp[31] = 1, Root PPN = 0x80000
        @(posedge clk);
        satp        = 32'h8008_0000;
        vaddr       = 32'h0000_3040; // VPN1 = 0, VPN0 = 3, Offset = 0x040
        req_valid   = 1'b1;
        access_type = 2'b00; // Read access
        @(posedge clk);
        @(posedge clk);

        // Wait for page table walk to complete
        while (stall) @(posedge clk);
        #1;
        check("Sv32 Page Walk translates 0x00003040 to PPN 0x80500 + 0x040", 32'h8050_0040, 1'b0);
        req_valid = 1'b0;

        // 4. Second lookup of same page: must be a fast TLB HIT (0 stall cycles!)
        @(posedge clk);
        vaddr       = 32'h0000_3080; // Same page, different offset
        req_valid   = 1'b1;
        access_type = 2'b00;
        @(posedge clk);
        @(posedge clk);
        #1;
        check("Subsequent access to same page hits in TLB immediately", 32'h8050_0080, 1'b0);
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
