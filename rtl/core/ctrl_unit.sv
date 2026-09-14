// ============================================================================
// File:        ctrl_unit.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Main Control Unit for the RV32I single-cycle datapath.
//
//              Takes the 7-bit opcode field from the instruction and produces
//              all datapath control signals. This is purely combinational —
//              no clock, no state.
//
//              The Control Unit does NOT generate the specific ALU operation
//              code (ALU_ADD, ALU_SUB, etc.). That is the job of the separate
//              ALU Control unit (alu_ctrl.sv), which takes the 2-bit alu_op
//              output from this module along with funct3/funct7 from the
//              instruction to produce the final 4-bit alu_op_t code.
//              This two-level decode mirrors the classic Patterson & Hennessy
//              RISC-V CPU architecture.
//
// Control Signals Produced:
//   reg_write   — 1: write result to register file rd
//   alu_src     — selects ALU operand B: rs2 register or sign-extended immediate
//   mem_write   — 1: write to data memory (Store instructions)
//   mem_read    — 1: read from data memory (Load instructions)
//   wb_src      — selects what value is written back to the register file
//   branch      — 1: this instruction may branch (BEQ/BNE/BLT/BGE/BLTU/BGEU)
//   jump        — 1: unconditional jump (JAL/JALR — always taken)
//   alu_op[1:0] — coarse ALU operation hint sent to the ALU Control unit:
//                   2'b00 = ADD (loads, stores, LUI, AUIPC use adder)
//                   2'b01 = SUB (branch comparison uses subtractor)
//                   2'b10 = decode from funct3/funct7 (R-type and I-ALU)
// ============================================================================

module ctrl_unit
    import riscv_pkg::*;
(
    input  logic [6:0] opcode,      // instr[6:0]

    output logic       reg_write,   // 1 = write to register file
    output alu_src_t   alu_src,     // Operand B mux select
    output logic       mem_write,   // 1 = write to data memory
    output logic       mem_read,    // 1 = read from data memory
    output wb_src_t    wb_src,      // Writeback source mux select
    output logic       branch,      // 1 = branch instruction
    output logic       jump,        // 1 = unconditional jump
    output logic [1:0] alu_op       // Coarse ALU hint for ALU Control unit
);

    always_comb begin
        // Safe defaults: every signal is explicitly driven on every code
        // path, preventing any possibility of inferred latches. Defaults
        // represent a NOP-like state: nothing writes, nothing branches.
        reg_write = 1'b0;
        alu_src   = ALU_SRC_REG;
        mem_write = 1'b0;
        mem_read  = 1'b0;
        wb_src    = WB_SRC_ALU;
        branch    = 1'b0;
        jump      = 1'b0;
        alu_op    = 2'b00;

        case (opcode)
            // ----------------------------------------------------------------
            // R-type: register-register ALU operations
            //   ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
            //   Operand B = rs2 register data
            //   Result written back to rd
            // ----------------------------------------------------------------
            OP_R_TYPE: begin
                reg_write = 1'b1;
                alu_src   = ALU_SRC_REG;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_ALU;
                branch    = 1'b0;
                jump      = 1'b0;
                alu_op    = 2'b10;  // ALU Control will decode from funct3/funct7
            end

            // ----------------------------------------------------------------
            // I-type ALU: immediate-register ALU operations
            //   ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
            //   Operand B = sign-extended immediate
            //   Result written back to rd
            // ----------------------------------------------------------------
            OP_I_ALU: begin
                reg_write = 1'b1;
                alu_src   = ALU_SRC_IMM;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_ALU;
                branch    = 1'b0;
                jump      = 1'b0;
                alu_op    = 2'b10;  // ALU Control decodes from funct3/funct7[5]
            end

            // ----------------------------------------------------------------
            // Load: LB, LH, LW, LBU, LHU
            //   ALU computes address = rs1 + sign-extended-imm (ADD operation)
            //   Memory data is written to rd (not ALU result)
            // ----------------------------------------------------------------
            OP_LOAD: begin
                reg_write = 1'b1;
                alu_src   = ALU_SRC_IMM;
                mem_write = 1'b0;
                mem_read  = 1'b1;
                wb_src    = WB_SRC_MEM;
                branch    = 1'b0;
                jump      = 1'b0;
                alu_op    = 2'b00;  // Always ADD for address calculation
            end

            // ----------------------------------------------------------------
            // Store: SB, SH, SW
            //   ALU computes address = rs1 + sign-extended-imm (ADD operation)
            //   rs2 data is written to memory; nothing written to register file
            // ----------------------------------------------------------------
            OP_STORE: begin
                reg_write = 1'b0;
                alu_src   = ALU_SRC_IMM;
                mem_write = 1'b1;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_ALU;  // Don't-care (reg_write=0)
                branch    = 1'b0;
                jump      = 1'b0;
                alu_op    = 2'b00;  // Always ADD for address calculation
            end

            // ----------------------------------------------------------------
            // Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
            //   ALU compares rs1 and rs2 (SUB or SLT depending on condition)
            //   branch=1 signals to the PC logic that a branch may be taken;
            //   the zero flag from the ALU determines whether it actually is.
            //   Nothing is written to the register file or memory.
            //   alu_op=01 tells ALU Control to use SUB for BEQ/BNE, and
            //   SLT/SLTU for BLT/BGE/BLTU/BGEU (decoded from funct3).
            // ----------------------------------------------------------------
            OP_BRANCH: begin
                reg_write = 1'b0;
                alu_src   = ALU_SRC_REG;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_ALU;  // Don't-care (reg_write=0)
                branch    = 1'b1;
                jump      = 1'b0;
                alu_op    = 2'b01;  // SUB / comparison for branch condition
            end

            // ----------------------------------------------------------------
            // JAL: Jump and Link
            //   PC = PC + sign-extended J-immediate (computed externally)
            //   rd = PC + 4 (return address written to register file)
            // ----------------------------------------------------------------
            OP_JAL: begin
                reg_write = 1'b1;
                alu_src   = ALU_SRC_IMM;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_PC4;
                branch    = 1'b0;
                jump      = 1'b1;
                alu_op    = 2'b00;  // ADD for target address (PC + imm, done in PC logic)
            end

            // ----------------------------------------------------------------
            // JALR: Jump and Link Register
            //   PC = (rs1 + sign-extended-imm) & ~1 (LSB forced to 0)
            //   rd = PC + 4
            //   ALU computes rs1 + imm; LSB-clear done in PC logic.
            // ----------------------------------------------------------------
            OP_JALR: begin
                reg_write = 1'b1;
                alu_src   = ALU_SRC_IMM;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_PC4;
                branch    = 1'b0;
                jump      = 1'b1;
                alu_op    = 2'b00;  // ADD for rs1 + imm target
            end

            // ----------------------------------------------------------------
            // LUI: Load Upper Immediate
            //   rd = zero-extended upper 20 bits (imm already has lower 12=0)
            //   The immediate generator produces the full 32-bit value.
            //   ALU passes it through via ADD with rs1=x0 (handled externally)
            //   or the top-level can route imm directly to writeback.
            //   Here: ALU computes 0 + imm = imm (alu_src=IMM, alu_op=ADD).
            // ----------------------------------------------------------------
            OP_LUI: begin
                reg_write = 1'b1;
                alu_src   = ALU_SRC_IMM;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_ALU;
                branch    = 1'b0;
                jump      = 1'b0;
                alu_op    = 2'b00;  // ADD: 0 + imm = imm
            end

            // ----------------------------------------------------------------
            // AUIPC: Add Upper Immediate to PC
            //   rd = PC + upper-20-bit-immediate
            //   ALU computes PC + imm (alu_src=IMM, alu_op=ADD)
            //   Operand A into the ALU is PC (not rs1) — the CPU top-level
            //   selects this via a separate pc_src mux.
            // ----------------------------------------------------------------
            OP_AUIPC: begin
                reg_write = 1'b1;
                alu_src   = ALU_SRC_IMM;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_ALU;
                branch    = 1'b0;
                jump      = 1'b0;
                alu_op    = 2'b00;  // ADD: PC + imm
            end

            // ----------------------------------------------------------------
            // Default / unknown opcode: safe NOP — nothing happens
            // ----------------------------------------------------------------
            default: begin
                reg_write = 1'b0;
                alu_src   = ALU_SRC_REG;
                mem_write = 1'b0;
                mem_read  = 1'b0;
                wb_src    = WB_SRC_ALU;
                branch    = 1'b0;
                jump      = 1'b0;
                alu_op    = 2'b00;
            end
        endcase
    end

endmodule
