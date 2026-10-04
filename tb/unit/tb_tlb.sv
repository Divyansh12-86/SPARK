// ============================================================================
// File:        tb_tlb.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for Translation Lookaside Buffer (TLB).
// ============================================================================

`timescale 1ns / 1ps

module tb_tlb;

    logic        clk;
    logic        rst_n;

    logic [19:0] vpn;
    logic        hit;
    logic [19:0] ppn;
    logic [7:0]  pte_flags;

    logic        update_en;
    logic [19:0] update_vpn;
    logic [19:0] update_ppn;
    logic [7:0]  update_flags;

    logic        flush_all;
    logic        flush_vpn_en;
    logic [19:0] flush_vpn;

    integer pass_count;
    integer fail_count;
    integer test_num;

    tlb #(
        .ENTRIES(16)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .vpn          (vpn),
        .hit          (hit),
        .ppn          (ppn),
        .pte_flags    (pte_flags),

        .update_en    (update_en),
        .update_vpn   (update_vpn),
        .update_ppn   (update_ppn),
        .update_flags (update_flags),

        .flush_all    (flush_all),
        .flush_vpn_en (flush_vpn_en),
        .flush_vpn    (flush_vpn)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check(
        input string       test_name,
        input logic        exp_hit,
        input logic [19:0] exp_ppn
    );
        test_num++;
        if (hit !== exp_hit || (exp_hit && ppn !== exp_ppn)) begin
            $display("  [FAIL] Test %0d: %s (Hit: Exp=%0b Act=%0b | PPN: Exp=0x%05h Act=0x%05h)",
                     test_num, test_name, exp_hit, hit, exp_ppn, ppn);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (Hit=%0b PPN=0x%05h)", test_num, test_name, hit, ppn);
            pass_count++;
        end
    endtask

    initial begin
        pass_count   = 0;
        fail_count   = 0;
        test_num     = 0;

        vpn          = 20'b0;
        update_en    = 1'b0;
        update_vpn   = 20'b0;
        update_ppn   = 20'b0;
        update_flags = 8'b0;
        flush_all    = 1'b0;
        flush_vpn_en = 1'b0;
        flush_vpn    = 20'b0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Translation Lookaside Buffer (TLB) Testbench");
        $display("==========================================================");

        // 1. Reset
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // 2. Lookup on empty TLB
        vpn = 20'h12345;
        #1;
        check("Initial lookup on empty TLB is a MISS", 1'b0, 20'b0);

        // 3. Insert translation: VPN 0x12345 -> PPN 0x80000 (R, W, V flags = 0x07)
        update_en    = 1'b1;
        update_vpn   = 20'h12345;
        update_ppn   = 20'h80000;
        update_flags = 8'h07;
        @(posedge clk);
        #1;
        update_en    = 1'b0;

        // 4. Lookup again: must HIT
        vpn = 20'h12345;
        #1;
        check("Lookup after insertion is a HIT (PPN=0x80000)", 1'b1, 20'h80000);

        // 5. Invalidate specific VPN
        flush_vpn_en = 1'b1;
        flush_vpn    = 20'h12345;
        @(posedge clk);
        #1;
        flush_vpn_en = 1'b0;

        #1;
        check("Lookup after selective invalidation is a MISS", 1'b0, 20'b0);

        // 6. Insert two entries and flush all
        update_en    = 1'b1;
        update_vpn   = 20'hAAAAA;
        update_ppn   = 20'h11111;
        @(posedge clk);
        #1;
        update_vpn   = 20'hBBBBB;
        update_ppn   = 20'h22222;
        @(posedge clk);
        #1;
        update_en    = 1'b0;

        vpn = 20'hAAAAA;
        #1;
        check("Entry A is present", 1'b1, 20'h11111);

        flush_all = 1'b1;
        @(posedge clk);
        #1;
        flush_all = 1'b0;

        #1;
        check("After flush_all, Entry A is gone (MISS)", 1'b0, 20'b0);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
