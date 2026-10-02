// ============================================================================
// File:        pc_reg.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: 32-bit Program Counter (PC) Register for RV32I.
//
//              Stores the current instruction address. Updates synchronously
//              on each rising clock edge when enable (en) is asserted.
//              Synchronous active-low reset resets the PC to RESET_ADDR.
// ============================================================================

module pc_reg #(
    parameter logic [31:0] RESET_ADDR = 32'h0000_0000
) (
    input  logic        clk,      // System clock
    input  logic        rst_n,    // Active-low synchronous reset
    input  logic        en,       // Clock enable (1 = update PC, 0 = stall/hold)
    input  logic [31:0] pc_next,  // Next PC value (from PC calculation mux)
    output logic [31:0] pc        // Current PC value (to instruction memory)
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc <= RESET_ADDR;
        end else if (en) begin
            pc <= pc_next;
        end
    end

endmodule
