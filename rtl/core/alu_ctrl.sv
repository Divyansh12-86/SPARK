// ============================================================================
// File:        alu_ctrl.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: ALU Control Unit for RV32I.
//
//              Decodes the 2-bit alu_op hint from the main Control Unit
//              along with funct3 (instr[14:12]) and funct7[5] (instr[30])
//              to generate the final 4-bit alu_op_t operation code for the ALU.
//
//              Pure combinational logic — zero latency.
// ============================================================================

module alu_ctrl
    import riscv_pkg::*;
(
    input  logic [1:0] alu_op_hint,  // Coarse hint from main control unit:
                                     //   2'b00 = Memory / Address / Upper Imm (ADD)
                                     //   2'b01 = Branch comparison
                                     //   2'b10 = R-type ALU
                                     //   2'b11 = I-type ALU
    input  logic [2:0] funct3,       // instr[14:12]
    input  logic       funct7_5,     // instr[30] (distinguishes ADD/SUB and SRL/SRA)
    output alu_op_t    alu_op        // 4-bit typed operation code for the ALU
);

    always_comb begin
        case (alu_op_hint)
            // ----------------------------------------------------------------
            // 2'b00: Loads, Stores, LUI, AUIPC, JAL, JALR
            // All use the ALU as an adder for address calculation or offset.
            // ----------------------------------------------------------------
            2'b00: alu_op = ALU_ADD;

            // ----------------------------------------------------------------
            // 2'b01: Branch Instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // ----------------------------------------------------------------
            2'b01: begin
                case (funct3)
                    3'b000:  alu_op = ALU_SUB;   // BEQ  (zero flag indicates equality)
                    3'b001:  alu_op = ALU_SUB;   // BNE  (zero flag indicates equality)
                    3'b100:  alu_op = ALU_SLT;   // BLT  (signed less-than comparison)
                    3'b101:  alu_op = ALU_SLT;   // BGE  (signed less-than comparison)
                    3'b110:  alu_op = ALU_SLTU;  // BLTU (unsigned less-than comparison)
                    3'b111:  alu_op = ALU_SLTU;  // BGEU (unsigned less-than comparison)
                    default: alu_op = ALU_SUB;
                endcase
            end

            // ----------------------------------------------------------------
            // 2'b10: R-type Register-Register Instructions
            // Uses both funct3 and funct7_5 (instr[30]) to distinguish ADD/SUB
            // and SRL/SRA.
            // ----------------------------------------------------------------
            2'b10: begin
                case (funct3)
                    3'b000:  alu_op = funct7_5 ? ALU_SUB : ALU_ADD; // ADD / SUB
                    3'b001:  alu_op = ALU_SLL;                      // SLL
                    3'b010:  alu_op = ALU_SLT;                      // SLT
                    3'b011:  alu_op = ALU_SLTU;                     // SLTU
                    3'b100:  alu_op = ALU_XOR;                      // XOR
                    3'b101:  alu_op = funct7_5 ? ALU_SRA : ALU_SRL; // SRL / SRA
                    3'b110:  alu_op = ALU_OR;                       // OR
                    3'b111:  alu_op = ALU_AND;                      // AND
                    default: alu_op = ALU_ADD;
                endcase
            end

            // ----------------------------------------------------------------
            // 2'b11: I-type Immediate-Register Instructions
            // Note: ADDI does not have a SUB variant (always ADD, regardless
            // of immediate bit 30). For shift operations (SRLI/SRAI), funct7_5
            // still distinguishes arithmetic vs logical shift.
            // ----------------------------------------------------------------
            2'b11: begin
                case (funct3)
                    3'b000:  alu_op = ALU_ADD;                      // ADDI (always ADD)
                    3'b001:  alu_op = ALU_SLL;                      // SLLI
                    3'b010:  alu_op = ALU_SLT;                      // SLTI
                    3'b011:  alu_op = ALU_SLTU;                     // SLTIU
                    3'b100:  alu_op = ALU_XOR;                      // XORI
                    3'b101:  alu_op = funct7_5 ? ALU_SRA : ALU_SRL; // SRLI / SRAI
                    3'b110:  alu_op = ALU_OR;                       // ORI
                    3'b111:  alu_op = ALU_AND;                      // ANDI
                    default: alu_op = ALU_ADD;
                endcase
            end

            default: alu_op = ALU_ADD;
        endcase
    end

endmodule
