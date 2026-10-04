// ============================================================================
// File:        plic.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Platform-Level Interrupt Controller (PLIC) for RISC-V.
//
//              Memory-Mapped Registers (Base 0xC000_0000):
//                Offset 0x000004: Source 1 Priority (e.g. UART)
//                Offset 0x001000: Interrupt Enable (bit 1 = Source 1 enable)
//                Offset 0x200000: Priority Threshold (Context 0)
//                Offset 0x200004: Claim / Complete (Context 0):
//                                   Read:  Claims active interrupt, returns ID
//                                   Write: Completes interrupt servicing
//
//              Asserts external_irq to the CPU when an enabled source with
//              priority strictly greater than the threshold is pending.
// ============================================================================

module plic #(
    parameter int NUM_SOURCES = 4
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Bus Interface
    input  logic                   cs,
    input  logic                   read_en,
    input  logic                   write_en,
    input  logic [23:0]            addr,       // Offset within PLIC space
    input  logic [31:0]            write_data,
    output logic [31:0]            read_data,

    // Interrupt Source Lines (from devices)
    input  logic [NUM_SOURCES-1:1] irq_sources, // Source 0 is reserved/none

    // External Interrupt Output to CPU / CSR File
    output logic                   external_irq // MEIP
);

    // Register state
    logic [31:0] priority_regs [1:NUM_SOURCES-1];
    logic [31:0] enable_reg;
    logic [31:0] threshold_reg;
    logic [31:0] pending_reg;
    logic [31:0] claimed_source;

    // Detect level assertion from interrupt sources
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pending_reg <= 32'b0;
        end else begin
            for (int i = 1; i < NUM_SOURCES; i++) begin
                if (irq_sources[i]) begin
                    pending_reg[i] <= 1'b1;
                end
            end

            // Software Claim clears pending bit
            if (cs && read_en && (addr == 24'h200004)) begin
                if (claimed_source != 32'b0) begin
                    pending_reg[claimed_source] <= 1'b0;
                end
            end
        end
    end

    // Find highest priority pending & enabled interrupt
    logic [31:0] max_priority;
    logic [31:0] best_id;

    always_comb begin
        max_priority = threshold_reg;
        best_id      = 32'b0;

        for (int i = 1; i < NUM_SOURCES; i++) begin
            if (pending_reg[i] && enable_reg[i]) begin
                if (priority_regs[i] > max_priority) begin
                    max_priority = priority_regs[i];
                    best_id      = i;
                end
            end
        end
    end

    assign claimed_source = best_id;
    assign external_irq   = (best_id != 32'b0);

    // ========================================================================
    // Bus Read
    // ========================================================================
    always_comb begin
        if (cs && read_en) begin
            case (addr)
                24'h000004: read_data = priority_regs[1];
                24'h001000: read_data = enable_reg;
                24'h200000: read_data = threshold_reg;
                24'h200004: read_data = claimed_source; // Read Claim returns ID
                default:    read_data = 32'b0;
            endcase
        end else begin
            read_data = 32'b0;
        end
    end

    // ========================================================================
    // Bus Write
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 1; i < NUM_SOURCES; i++) begin
                priority_regs[i] <= 32'b0;
            end
            enable_reg    <= 32'b0;
            threshold_reg <= 32'b0;
        end else if (cs && write_en) begin
            case (addr)
                24'h000004: priority_regs[1] <= write_data;
                24'h001000: enable_reg       <= write_data;
                24'h200000: threshold_reg    <= write_data;
                24'h200004: begin
                    // Write to complete register (acknowledge)
                end
                default: ;
            endcase
        end
    end

endmodule
