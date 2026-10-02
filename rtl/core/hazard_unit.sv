// ============================================================================
// File:        hazard_unit.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Hazard Detection Unit for 5-Stage RV32I Pipeline.
//
//              Handles:
//                1. Load-Use Data Hazards:
//                   Occurs when an instruction in EX is a Load (mem_read_ex=1)
//                   and the instruction in ID depends on its rd.
//                   Data is not available until MEM stage, so forwarding alone
//                   cannot prevent the hazard. A 1-cycle stall is inserted by:
//                     - Freezing PC (stall_pc = 1)
//                     - Freezing IF/ID register (stall_if_id = 1)
//                     - Flushing ID/EX register with a bubble (flush_id_ex = 1)
//
//                2. Control Hazards (Branch / Jump):
//                   When a branch is taken or an unconditional jump executes,
//                   the speculatively fetched instructions in IF and ID must
//                   be cancelled:
//                     - flush_if_id = 1
//                     - flush_id_ex = 1
// ============================================================================

module hazard_unit (
    // Inputs from Decode stage
    input  logic [4:0] rs1_addr_id,
    input  logic [4:0] rs2_addr_id,

    // Inputs from Execute stage
    input  logic       mem_read_ex,
    input  logic [4:0] rd_addr_ex,
    input  logic       branch_taken_ex,
    input  logic       jump_ex,
    input  logic       trap_redirect,

    // Stall and Flush outputs
    output logic       stall_pc,
    output logic       stall_if_id,
    output logic       flush_if_id,
    output logic       flush_id_ex
);

    logic load_use_hazard;

    always_comb begin
        // --------------------------------------------------------------------
        // 1. Load-Use Hazard Detection
        // --------------------------------------------------------------------
        // If the instruction currently in Execute is loading from memory, and
        // the instruction currently in Decode reads that same register:
        if (mem_read_ex && (rd_addr_ex != 5'b0) &&
            ((rd_addr_ex == rs1_addr_id) || (rd_addr_ex == rs2_addr_id))) begin
            load_use_hazard = 1'b1;
        end else begin
            load_use_hazard = 1'b0;
        end

        // --------------------------------------------------------------------
        // 2. Stall & Flush Signal Assignment
        // --------------------------------------------------------------------
        if (trap_redirect || branch_taken_ex || jump_ex) begin
            // Trap/Branch/Jump taken: flush both younger instructions in the pipe
            stall_pc    = 1'b0;
            stall_if_id = 1'b0;
            flush_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end else if (load_use_hazard) begin
            // Load-Use stall: freeze fetch and decode, inject bubble into execute
            stall_pc    = 1'b1;
            stall_if_id = 1'b1;
            flush_if_id = 1'b0;
            flush_id_ex = 1'b1;
        end else begin
            // Normal execution: no stalls, no flushes
            stall_pc    = 1'b0;
            stall_if_id = 1'b0;
            flush_if_id = 1'b0;
            flush_id_ex = 1'b0;
        end
    end

endmodule
