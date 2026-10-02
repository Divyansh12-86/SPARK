// ============================================================================
// File:        forwarding_unit.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Data Hazard Forwarding Unit for 5-Stage RV32I Pipeline.
//
//              Resolves Read-After-Write (RAW) data hazards by forwarding
//              computed results from MEM and WB stages directly to the EX stage
//              ALU inputs, avoiding pipeline stalls for ALU-to-ALU dependencies.
//
//              Forwarding Encoding:
//                2'b00: No forwarding (operand from ID/EX register)
//                2'b10: Forward from EX/MEM stage (ALU result in MEM)
//                2'b01: Forward from MEM/WB stage (Writeback data)
//
//              Priority: EX/MEM hazard has priority over MEM/WB hazard
//              because it holds the most recently computed value.
//              x0 protection: Writes to x0 are never forwarded.
// ============================================================================

module forwarding_unit (
    input  logic [4:0] rs1_addr_ex,
    input  logic [4:0] rs2_addr_ex,

    input  logic       reg_write_mem,
    input  logic [4:0] rd_addr_mem,

    input  logic       reg_write_wb,
    input  logic [4:0] rd_addr_wb,

    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    always_comb begin
        // --------------------------------------------------------------------
        // Forwarding for Operand A (rs1)
        // --------------------------------------------------------------------
        if (reg_write_mem && (rd_addr_mem != 5'b0) && (rd_addr_mem == rs1_addr_ex)) begin
            forward_a = 2'b10; // Forward from MEM stage
        end else if (reg_write_wb && (rd_addr_wb != 5'b0) && (rd_addr_wb == rs1_addr_ex)) begin
            forward_a = 2'b01; // Forward from WB stage
        end else begin
            forward_a = 2'b00; // No forwarding
        end

        // --------------------------------------------------------------------
        // Forwarding for Operand B (rs2)
        // --------------------------------------------------------------------
        if (reg_write_mem && (rd_addr_mem != 5'b0) && (rd_addr_mem == rs2_addr_ex)) begin
            forward_b = 2'b10; // Forward from MEM stage
        end else if (reg_write_wb && (rd_addr_wb != 5'b0) && (rd_addr_wb == rs2_addr_ex)) begin
            forward_b = 2'b01; // Forward from WB stage
        end else begin
            forward_b = 2'b00; // No forwarding
        end
    end

endmodule
