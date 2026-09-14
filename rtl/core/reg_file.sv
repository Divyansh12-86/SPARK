// ============================================================================
// File:        reg_file.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: 32-entry x 32-bit Register File for RV32I.
//
//              2 asynchronous read ports (rs1, rs2) — combinational, zero latency.
//              1 synchronous write port (rd) — writes on rising clock edge.
//              Register x0 is hardwired to zero: reads always return 0,
//              writes are silently discarded.
// ============================================================================

module reg_file (
    input  logic        clk,        // System clock
    input  logic        rst_n,      // Active-low synchronous reset

    // Read port 1 (rs1)
    input  logic [4:0]  rs1_addr,   // Source register 1 address (5 bits = 0..31)
    output logic [31:0] rs1_data,   // Source register 1 data out

    // Read port 2 (rs2)
    input  logic [4:0]  rs2_addr,   // Source register 2 address
    output logic [31:0] rs2_data,   // Source register 2 data out

    // Write port (rd)
    input  logic        wr_en,      // Write enable (active high)
    input  logic [4:0]  rd_addr,    // Destination register address
    input  logic [31:0] rd_data     // Data to write
);

    // 32 registers, each 32 bits wide.
    // In synthesis, this infers a bank of 32 x 32 = 1024 flip-flops.
    logic [31:0] registers [0:31];

    // ========================================================================
    // Synchronous Write with Reset
    // ========================================================================
    // Writes happen on the rising clock edge. On reset, all registers are
    // cleared to zero. Writes to address 0 are blocked (x0 stays zero).

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Synchronous reset: clear all registers to zero.
            for (int i = 0; i < 32; i++) begin
                registers[i] <= 32'b0;
            end
        end else if (wr_en && rd_addr != 5'b0) begin
            // Write only if enabled AND destination is not x0.
            // The rd_addr != 0 check is what enforces the RISC-V rule
            // that x0 is hardwired to zero — any write targeting x0 is
            // silently dropped, regardless of wr_en.
            registers[rd_addr] <= rd_data;
        end
    end

    // ========================================================================
    // Asynchronous (Combinational) Reads
    // ========================================================================
    // Reads are purely combinational — no clock needed. The output changes
    // immediately when the address changes. x0 always returns zero regardless
    // of what might be stored in registers[0] (belt-and-suspenders with the
    // write-block above).

    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : registers[rs2_addr];

endmodule
