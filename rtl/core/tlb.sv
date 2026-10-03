// ============================================================================
// File:        tlb.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Translation Lookaside Buffer (TLB) for Sv32 Virtual Memory.
//
//              Fully-associative 16-entry cache of recently translated
//              Virtual Page Numbers (VPN) to Physical Page Numbers (PPN).
//              Supports single-cycle lookup, round-robin/LRU eviction, and
//              sfence.vma invalidation.
// ============================================================================

module tlb #(
    parameter int ENTRIES = 16
) (
    input  logic        clk,
    input  logic        rst_n,

    // Translation Lookup Port
    input  logic [19:0] vpn,          // Virtual Page Number to lookup (vaddr[31:12])
    output logic        hit,          // 1 = TLB Hit
    output logic [19:0] ppn,          // Translated Physical Page Number
    output logic [7:0]  pte_flags,    // D, A, G, U, X, W, R, V

    // TLB Update Port (from MMU Page Table Walker)
    input  logic        update_en,
    input  logic [19:0] update_vpn,
    input  logic [19:0] update_ppn,
    input  logic [7:0]  update_flags,

    // Flush Port (sfence.vma)
    input  logic        flush_all,
    input  logic        flush_vpn_en,
    input  logic [19:0] flush_vpn
);

    // TLB Entry Storage
    logic        valid_entries [0:ENTRIES-1];
    logic [19:0] vpn_entries   [0:ENTRIES-1];
    logic [19:0] ppn_entries   [0:ENTRIES-1];
    logic [7:0]  flag_entries  [0:ENTRIES-1];

    // Replacement pointer (FIFO / Round-robin)
    logic [$clog2(ENTRIES)-1:0] replace_ptr;

    // ========================================================================
    // Associative Lookup
    // ========================================================================
    always_comb begin
        hit       = 1'b0;
        ppn       = 20'b0;
        pte_flags = 8'b0;

        for (int i = 0; i < ENTRIES; i++) begin
            if (valid_entries[i] && (vpn_entries[i] == vpn)) begin
                hit       = 1'b1;
                ppn       = ppn_entries[i];
                pte_flags = flag_entries[i];
            end
        end
    end

    // ========================================================================
    // Synchronous Update & Invalidation
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n || flush_all) begin
            for (int i = 0; i < ENTRIES; i++) begin
                valid_entries[i] <= 1'b0;
                vpn_entries[i]   <= 20'b0;
                ppn_entries[i]   <= 20'b0;
                flag_entries[i]  <= 8'b0;
            end
            replace_ptr <= '0;
        end else if (flush_vpn_en) begin
            // Invalidate entry matching specific VPN
            for (int i = 0; i < ENTRIES; i++) begin
                if (valid_entries[i] && (vpn_entries[i] == flush_vpn)) begin
                    valid_entries[i] <= 1'b0;
                end
            end
        end else if (update_en) begin
            // Check if VPN is already present to update it in-place
            logic [$clog2(ENTRIES)-1:0] match_idx;
            bit                         found_match;
            found_match = 1'b0;
            match_idx   = '0;

            for (int i = 0; i < ENTRIES; i++) begin
                if (valid_entries[i] && (vpn_entries[i] == update_vpn)) begin
                    found_match = 1'b1;
                    match_idx   = 4'(i);
                end
            end

            if (found_match) begin
                ppn_entries[match_idx]  <= update_ppn;
                flag_entries[match_idx] <= update_flags;
            end else begin
                // Insert at replace_ptr
                valid_entries[replace_ptr] <= 1'b1;
                vpn_entries[replace_ptr]   <= update_vpn;
                ppn_entries[replace_ptr]   <= update_ppn;
                flag_entries[replace_ptr]  <= update_flags;
                replace_ptr                <= replace_ptr + 1'b1;
            end
        end
    end

endmodule
