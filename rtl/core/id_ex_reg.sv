// ============================================================================
// File:        id_ex_reg.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: ID/EX Pipeline Register (Decode -> Execute stage boundary).
//
//              Registers decoded control signals, register operands, immediate,
//              instruction fields, and PC.
//              Synchronous flush inserts a bubble by setting all write-enables
//              and control flags to 0 (NOP).
// ============================================================================

module id_ex_reg
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        flush,          // 1 = insert bubble (clears control signals)

    // Control signals from Decode
    input  logic        reg_write_id,
    input  alu_src_t    alu_src_id,
    input  logic        mem_write_id,
    input  logic        mem_read_id,
    input  wb_src_t     wb_src_id,
    input  logic        branch_id,
    input  logic        jump_id,
    input  logic [1:0]  alu_op_hint_id,

    // Datapath signals from Decode
    input  logic [31:0] pc_id,
    input  logic [31:0] rs1_data_id,
    input  logic [31:0] rs2_data_id,
    input  logic [31:0] imm_id,
    input  logic [2:0]  funct3_id,
    input  logic        funct7_5_id,
    input  logic [4:0]  rs1_addr_id,
    input  logic [4:0]  rs2_addr_id,
    input  logic [4:0]  rd_addr_id,
    input  logic [6:0]  opcode_id,
    input  logic [31:0] instr_id,

    // Registered outputs to Execute
    output logic        reg_write_ex,
    output alu_src_t    alu_src_ex,
    output logic        mem_write_ex,
    output logic        mem_read_ex,
    output wb_src_t     wb_src_ex,
    output logic        branch_ex,
    output logic        jump_ex,
    output logic [1:0]  alu_op_hint_ex,

    output logic [31:0] pc_ex,
    output logic [31:0] rs1_data_ex,
    output logic [31:0] rs2_data_ex,
    output logic [31:0] imm_ex,
    output logic [2:0]  funct3_ex,
    output logic        funct7_5_ex,
    output logic [4:0]  rs1_addr_ex,
    output logic [4:0]  rs2_addr_ex,
    output logic [4:0]  rd_addr_ex,
    output logic [6:0]  opcode_ex,
    output logic [31:0] instr_ex
);

    always_ff @(posedge clk) begin
        if (!rst_n || flush) begin
            // Clear control signals to 0 (insert bubble / NOP)
            reg_write_ex   <= 1'b0;
            alu_src_ex     <= ALU_SRC_REG;
            mem_write_ex   <= 1'b0;
            mem_read_ex    <= 1'b0;
            wb_src_ex      <= WB_SRC_ALU;
            branch_ex      <= 1'b0;
            jump_ex        <= 1'b0;
            alu_op_hint_ex <= 2'b00;

            pc_ex          <= 32'b0;
            rs1_data_ex    <= 32'b0;
            rs2_data_ex    <= 32'b0;
            imm_ex         <= 32'b0;
            funct3_ex      <= 3'b0;
            funct7_5_ex    <= 1'b0;
            rs1_addr_ex    <= 5'b0;
            rs2_addr_ex    <= 5'b0;
            rd_addr_ex     <= 5'b0;
            opcode_ex      <= 7'b0;
            instr_ex       <= 32'h0000_0013; // NOP (addi x0, x0, 0)
        end else begin
            reg_write_ex   <= reg_write_id;
            alu_src_ex     <= alu_src_id;
            mem_write_ex   <= mem_write_id;
            mem_read_ex    <= mem_read_id;
            wb_src_ex      <= wb_src_id;
            branch_ex      <= branch_id;
            jump_ex        <= jump_id;
            alu_op_hint_ex <= alu_op_hint_id;

            pc_ex          <= pc_id;
            rs1_data_ex    <= rs1_data_id;
            rs2_data_ex    <= rs2_data_id;
            imm_ex         <= imm_id;
            funct3_ex      <= funct3_id;
            funct7_5_ex    <= funct7_5_id;
            rs1_addr_ex    <= rs1_addr_id;
            rs2_addr_ex    <= rs2_addr_id;
            rd_addr_ex     <= rd_addr_id;
            opcode_ex      <= opcode_id;
            instr_ex       <= instr_id;
        end
    end

endmodule
