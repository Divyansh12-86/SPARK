// ============================================================================
// File:        branch_unit.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Branch Decision Unit for RV32I.
//
//              Evaluates branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
//              based on funct3 and register operands rs1 and rs2.
//              Generates branch_taken = 1 only if the branch instruction is
//              active AND the comparison condition evaluates to true.
//
//              Pure combinational logic — zero latency.
// ============================================================================

module branch_unit (
    input  logic        branch,       // 1 = branch instruction active (from ctrl_unit)
    input  logic [2:0]  funct3,       // instr[14:12] specifies condition
    input  logic [31:0] rs1_data,     // Source register 1 data
    input  logic [31:0] rs2_data,     // Source register 2 data
    output logic        branch_taken  // 1 = branch condition met, take branch
);

    logic condition_met;

    always_comb begin
        case (funct3)
            3'b000:  condition_met = (rs1_data == rs2_data);                        // BEQ
            3'b001:  condition_met = (rs1_data != rs2_data);                        // BNE
            3'b100:  condition_met = ($signed(rs1_data) < $signed(rs2_data));      // BLT  (signed)
            3'b101:  condition_met = ($signed(rs1_data) >= $signed(rs2_data));     // BGE  (signed)
            3'b110:  condition_met = (rs1_data < rs2_data);                         // BLTU (unsigned)
            3'b111:  condition_met = (rs1_data >= rs2_data);                        // BGEU (unsigned)
            default: condition_met = 1'b0;
        endcase
    end

    assign branch_taken = branch & condition_met;

endmodule
