// ============================================================================
// File:        if_id_reg.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: IF/ID Pipeline Register (Fetch -> Decode stage boundary).
//
//              Holds instruction and PC fetched from Instruction Memory.
//              Supports synchronous stall (holds current value) and flush
//              (clears to NOP = 32'h00000013 = addi x0, x0, 0).
// ============================================================================

module if_id_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        stall,     // 1 = hold current contents (load-use hazard)
    input  logic        flush,     // 1 = clear to NOP (branch/jump misprediction)
    input  logic [31:0] pc_if,     // PC of fetched instruction
    input  logic [31:0] instr_if,  // Fetched instruction word
    output logic [31:0] pc_id,     // Registered PC to decode stage
    output logic [31:0] instr_id   // Registered instruction to decode stage
);

    localparam logic [31:0] NOP_INSTR = 32'h0000_0013; // addi x0, x0, 0

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc_id    <= 32'b0;
            instr_id <= NOP_INSTR;
        end else if (flush) begin
            pc_id    <= 32'b0;
            instr_id <= NOP_INSTR;
        end else if (!stall) begin
            pc_id    <= pc_if;
            instr_id <= instr_if;
        end
    end

endmodule
