// ============================================================================
// File:        mem_wb_reg.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: MEM/WB Pipeline Register (Memory -> Writeback stage boundary).
//
//              Registers final memory output data, ALU results, PC+4,
//              and destination register address rd for register file writeback.
// ============================================================================

module mem_wb_reg
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Control signals from Memory stage
    input  logic        reg_write_mem,
    input  wb_src_t     wb_src_mem,

    // Datapath signals from Memory stage
    input  logic [31:0] alu_result_mem,
    input  logic [31:0] mem_read_data_mem,
    input  logic [4:0]  rd_addr_mem,
    input  logic [31:0] pc_plus4_mem,

    // Registered outputs to Writeback stage
    output logic        reg_write_wb,
    output wb_src_t     wb_src_wb,

    output logic [31:0] alu_result_wb,
    output logic [31:0] mem_read_data_wb,
    output logic [4:0]  rd_addr_wb,
    output logic [31:0] pc_plus4_wb
);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_write_wb     <= 1'b0;
            wb_src_wb        <= WB_SRC_ALU;
            alu_result_wb    <= 32'b0;
            mem_read_data_wb <= 32'b0;
            rd_addr_wb       <= 5'b0;
            pc_plus4_wb      <= 32'b0;
        end else begin
            reg_write_wb     <= reg_write_mem;
            wb_src_wb        <= wb_src_mem;
            alu_result_wb    <= alu_result_mem;
            mem_read_data_wb <= mem_read_data_mem;
            rd_addr_wb       <= rd_addr_mem;
            pc_plus4_wb      <= pc_plus4_mem;
        end
    end

endmodule
