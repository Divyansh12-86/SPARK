// ============================================================================
// File:        ex_mem_reg.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: EX/MEM Pipeline Register (Execute -> Memory stage boundary).
//
//              Registers memory access control signals, writeback controls,
//              computed ALU result (or memory address), write data, and rd.
// ============================================================================

module ex_mem_reg
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Control signals from Execute
    input  logic        reg_write_ex,
    input  logic        mem_write_ex,
    input  logic        mem_read_ex,
    input  wb_src_t     wb_src_ex,

    // Datapath signals from Execute
    input  logic [31:0] alu_result_ex,
    input  logic [31:0] write_data_ex,  // Forwarded rs2 data to be written to memory
    input  logic [4:0]  rd_addr_ex,
    input  logic [2:0]  funct3_ex,      // Memory access width (SB, SH, SW, etc.)
    input  logic [31:0] pc_plus4_ex,

    // Registered outputs to Memory
    output logic        reg_write_mem,
    output logic        mem_write_mem,
    output logic        mem_read_mem,
    output wb_src_t     wb_src_mem,

    output logic [31:0] alu_result_mem,
    output logic [31:0] write_data_mem,
    output logic [4:0]  rd_addr_mem,
    output logic [2:0]  funct3_mem,
    output logic [31:0] pc_plus4_mem
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_write_mem  <= 1'b0;
            mem_write_mem  <= 1'b0;
            mem_read_mem   <= 1'b0;
            wb_src_mem     <= WB_SRC_ALU;

            alu_result_mem <= 32'b0;
            write_data_mem <= 32'b0;
            rd_addr_mem    <= 5'b0;
            funct3_mem     <= 3'b0;
            pc_plus4_mem   <= 32'b0;
        end else begin
            reg_write_mem  <= reg_write_ex;
            mem_write_mem  <= mem_write_ex;
            mem_read_mem   <= mem_read_ex;
            wb_src_mem     <= wb_src_ex;

            alu_result_mem <= alu_result_ex;
            write_data_mem <= write_data_ex;
            rd_addr_mem    <= rd_addr_ex;
            funct3_mem     <= funct3_ex;
            pc_plus4_mem   <= pc_plus4_ex;
        end
    end

endmodule
