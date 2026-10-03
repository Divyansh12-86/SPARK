// ============================================================================
// File:        mmu_sv32.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Sv32 Memory Management Unit (MMU) with Hardware Page Table Walker.
//
//              Translates 32-bit Virtual Addresses to Physical Addresses:
//                - Fast Path: 1-cycle hit via integrated TLB (tlb.sv)
//                - Slow Path: 2-Level Hardware Page Table Walk
//                             Level 1: vaddr[31:22] (VPN[1])
//                             Level 0: vaddr[21:12] (VPN[0])
//                - Bypass Mode: Bare physical addressing when satp[31] == 0
//                               or running in Machine mode.
//                - Page Fault Detection: Read/Write/Execute permission checking,
//                                        User vs Supervisor privilege checking.
// ============================================================================

module mmu_sv32
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Processor Configuration
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] satp,             // satp[31] = MODE (1=Sv32), satp[19:0] = root PPN
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [1:0]  priv_mode,        // Current privilege mode (U, S, M)
    input  logic        sfence_vma,       // TLB flush request

    // CPU Translation Interface
    input  logic        req_valid,        // 1 = translation requested
    input  logic [31:0] vaddr,            // Virtual address
    input  logic [1:0]  access_type,      // 00 = Read, 01 = Write, 10 = Execute
    output logic [31:0] paddr,            // Physical address out
    output logic        paddr_valid,      // 1 = translation ready
    output logic        page_fault,       // 1 = page fault exception
    output logic        stall,            // 1 = stall pipeline during page walk

    // Memory Bus Interface for Page Table Walks
    output logic        walk_req,
    output logic [31:0] walk_paddr,
    input  logic [31:0] walk_rdata,
    input  logic        walk_ready
);

    // ========================================================================
    // Virtual Address Decomposition
    // ========================================================================
    wire [9:0]  vpn1        = vaddr[31:22]; // Level 1 page table index
    wire [9:0]  vpn0        = vaddr[21:12]; // Level 0 page table index
    wire [11:0] page_offset = vaddr[11:0];  // 4 KB page offset
    wire [19:0] vpn_full    = vaddr[31:12];

    wire        sv32_enabled = satp[31] && (priv_mode != PRIV_M);
    wire [19:0] root_ppn     = satp[19:0];

    // ========================================================================
    // Integrated TLB Instance
    // ========================================================================
    logic        tlb_hit;
    logic [19:0] tlb_ppn;
    logic [7:0]  tlb_flags;

    logic        tlb_update_en;
    logic [19:0] tlb_update_vpn;
    logic [19:0] tlb_update_ppn;
    logic [7:0]  tlb_update_flags;

    tlb #(
        .ENTRIES(16)
    ) u_tlb (
        .clk          (clk),
        .rst_n        (rst_n),
        .vpn          (vpn_full),
        .hit          (tlb_hit),
        .ppn          (tlb_ppn),
        .pte_flags    (tlb_flags),

        .update_en    (tlb_update_en),
        .update_vpn   (tlb_update_vpn),
        .update_ppn   (tlb_update_ppn),
        .update_flags (tlb_update_flags),

        .flush_all    (sfence_vma),
        .flush_vpn_en (1'b0),
        .flush_vpn    (20'b0)
    );

    // ========================================================================
    // Page Table Walker FSM
    // ========================================================================
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        CHECK_TLB   = 3'b001,
        WALK_L1_REQ = 3'b010,
        WALK_L1_RSP = 3'b011,
        WALK_L0_REQ = 3'b100,
        WALK_L0_RSP = 3'b101,
        FAULT       = 3'b110
    } state_t;

    state_t state;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [19:0] l1_ppn;
    logic [31:0] pte_reg;
    /* verilator lint_on UNUSEDSIGNAL */

    // Permission Checking Helper
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic check_permissions(input logic [7:0] flags, input logic [1:0] acc, input logic [1:0] priv);
    /* verilator lint_on UNUSEDSIGNAL */
        logic valid, r, w, x, u;
        valid = flags[0];
        r     = flags[1];
        w     = flags[2];
        x     = flags[3];
        u     = flags[4];

        if (!valid) return 1'b0;

        // User vs Supervisor protection
        if (priv == PRIV_U && !u) return 1'b0;
        if (priv == PRIV_S && u)  return 1'b0; // User page protection

        // Access type check
        if (acc == 2'b00 && !r) return 1'b0; // Read
        if (acc == 2'b01 && !w) return 1'b0; // Write
        if (acc == 2'b10 && !x) return 1'b0; // Execute

        return 1'b1;
    endfunction

    // ========================================================================
    // FSM and Datapath Logic
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state            <= IDLE;
            walk_req         <= 1'b0;
            walk_paddr       <= 32'b0;
            tlb_update_en    <= 1'b0;
            tlb_update_vpn   <= 20'b0;
            tlb_update_ppn   <= 20'b0;
            tlb_update_flags <= 8'b0;
            paddr            <= 32'b0;
            paddr_valid      <= 1'b0;
            page_fault       <= 1'b0;
            stall            <= 1'b0;
            l1_ppn           <= 20'b0;
            pte_reg          <= 32'b0;
        end else begin
            tlb_update_en <= 1'b0; // Default pulse

            case (state)
                IDLE: begin
                    page_fault  <= 1'b0;
                    paddr_valid <= 1'b0;
                    walk_req    <= 1'b0;

                    if (req_valid) begin
                        if (!sv32_enabled) begin
                            // Bare physical mode: direct address translation
                            paddr       <= vaddr;
                            paddr_valid <= 1'b1;
                            stall       <= 1'b0;
                        end else begin
                            // Sv32 enabled: check TLB first
                            stall <= 1'b1;
                            state <= CHECK_TLB;
                        end
                    end else begin
                        stall <= 1'b0;
                    end
                end

                CHECK_TLB: begin
                    if (tlb_hit) begin
                        if (check_permissions(tlb_flags, access_type, priv_mode)) begin
                            paddr       <= {tlb_ppn, page_offset};
                            paddr_valid <= 1'b1;
                            stall       <= 1'b0;
                            state       <= IDLE;
                        end else begin
                            page_fault  <= 1'b1;
                            stall       <= 1'b0;
                            state       <= IDLE;
                        end
                    end else begin
                        // TLB Miss -> Begin Level 1 Page Table Walk
                        walk_req   <= 1'b1;
                        walk_paddr <= {root_ppn, vpn1, 2'b00}; // Address of PTE in L1
                        state      <= WALK_L1_RSP;
                    end
                end

                WALK_L1_RSP: begin
                    if (walk_ready) begin
                        walk_req <= 1'b0;
                        pte_reg  <= walk_rdata;

                        // Check PTE Valid bit
                        if (!walk_rdata[0]) begin
                            state <= FAULT;
                        end else if (walk_rdata[1] || walk_rdata[3]) begin
                            // MegaPage (4MB page): R or X bit is set in L1
                            if (check_permissions(walk_rdata[7:0], access_type, priv_mode)) begin
                                paddr            <= {walk_rdata[29:20], vaddr[21:0]};
                                paddr_valid      <= 1'b1;
                                tlb_update_en    <= 1'b1;
                                tlb_update_vpn   <= vpn_full;
                                tlb_update_ppn   <= {walk_rdata[29:20], vpn0};
                                tlb_update_flags <= walk_rdata[7:0];
                                stall            <= 1'b0;
                                state            <= IDLE;
                            end else begin
                                state <= FAULT;
                            end
                        end else begin
                            // Pointer to Level 0 Page Table
                            l1_ppn     <= walk_rdata[29:10];
                            walk_req   <= 1'b1;
                            walk_paddr <= {walk_rdata[29:10], vpn0, 2'b00};
                            state      <= WALK_L0_RSP;
                        end
                    end
                end

                WALK_L0_RSP: begin
                    if (walk_ready) begin
                        walk_req <= 1'b0;

                        if (!walk_rdata[0]) begin
                            state <= FAULT;
                        end else if (check_permissions(walk_rdata[7:0], access_type, priv_mode)) begin
                            // Standard 4KB Page translated successfully!
                            paddr            <= {walk_rdata[29:10], page_offset};
                            paddr_valid      <= 1'b1;
                            tlb_update_en    <= 1'b1;
                            tlb_update_vpn   <= vpn_full;
                            tlb_update_ppn   <= walk_rdata[29:10];
                            tlb_update_flags <= walk_rdata[7:0];
                            stall            <= 1'b0;
                            state            <= IDLE;
                        end else begin
                            state <= FAULT;
                        end
                    end
                end

                FAULT: begin
                    page_fault <= 1'b1;
                    stall      <= 1'b0;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
