// ============================================================================
// File:        imm_gen.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Immediate Generator for RV32I.
//
//              Extracts and sign-extends the immediate value from a 32-bit
//              RISC-V instruction based on its opcode (which determines the
//              instruction format: I, S, B, U, J). R-type instructions have
//              no immediate; the output is zero for those.
//
//              Pure combinational logic — no clock, no state.
// ============================================================================

module imm_gen
    import riscv_pkg::*;
(
    input  logic [31:0] instr,   // Full 32-bit instruction
    output logic [31:0] imm      // Sign-extended 32-bit immediate
);

    // The opcode field is always instr[6:0] in every RISC-V format.
    logic [6:0] opcode;
    assign opcode = instr[6:0];

    always_comb begin
        imm = 32'b0;  // Default: no immediate (R-type, or unknown opcode)

        case (opcode)
            // ----------------------------------------------------------------
            // I-type: imm[11:0] = instr[31:20]
            //   Bit layout: [31]=sign [30:20]=imm[10:0]
            //   Sign-extend bit 31 across bits [31:12] of output.
            //   Used by: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, LB/LH/LW/LBU/LHU,
            //            JALR, SLLI/SRLI/SRAI (shift amount in imm[4:0])
            // ----------------------------------------------------------------
            OP_I_ALU,
            OP_LOAD,
            OP_JALR,
            OP_SYSTEM: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end

            // ----------------------------------------------------------------
            // S-type: imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
            //   The immediate is split across two non-contiguous fields.
            //   Used by: SB, SH, SW
            // ----------------------------------------------------------------
            OP_STORE: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // ----------------------------------------------------------------
            // B-type: imm[12|10:5] = instr[31:25], imm[4:1|11] = instr[11:7]
            //   Bit 0 is always 0 (branch targets are 2-byte aligned).
            //   The bits are scattered across the instruction to maximize
            //   overlap with S-type (reducing decode hardware mux complexity).
            //   Used by: BEQ, BNE, BLT, BGE, BLTU, BGEU
            // ----------------------------------------------------------------
            OP_BRANCH: begin
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end

            // ----------------------------------------------------------------
            // U-type: imm[31:12] = instr[31:12], imm[11:0] = 0
            //   The upper 20 bits are taken directly from the instruction.
            //   No sign extension needed — the immediate already occupies
            //   the upper bits, with zeros in the lower 12.
            //   Used by: LUI, AUIPC
            // ----------------------------------------------------------------
            OP_LUI,
            OP_AUIPC: begin
                imm = {instr[31:12], 12'b0};
            end

            // ----------------------------------------------------------------
            // J-type: imm[20|10:1|11|19:12] = instr[31:12]
            //   Bit 0 is always 0 (jump targets are 2-byte aligned).
            //   The most scattered immediate format — bits are arranged to
            //   maximize overlap with U-type and B-type, reducing the number
            //   of unique mux paths in the decode hardware.
            //   Used by: JAL
            // ----------------------------------------------------------------
            OP_JAL: begin
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end

            // R-type and unknown opcodes: no immediate
            default: begin
                imm = 32'b0;
            end
        endcase
    end

endmodule
