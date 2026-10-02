// ============================================================================
// File:        custom_decoder.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Custom Instruction Decoder for Processing-In-Memory (PIM).
//
//              Decodes RISC-V custom-1 extension instructions (opcode 0101011):
//                - pim.vadd  (Vector Add)
//                - pim.vmac  (Vector Multiply-Accumulate / Dot Product)
//                - pim.vand  (Vector Bitwise AND)
//                - pim.vsum  (Vector Reduction Sum)
//                - pim.cfg   (PIM Configuration)
//                - pim.vfill (Bulk Framebuffer/Memory Fill)
//
//              Provides the architectural hook in the Execution stage to
//              dispatch commands to the PIM controller (Phase 6).
// ============================================================================

module custom_decoder
    import riscv_pkg::*;
(
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] instr,           // 32-bit instruction word
    /* verilator lint_on UNUSEDSIGNAL */
    output logic        is_custom,       // 1 = instruction belongs to custom-1 extension
    output pim_op_t     pim_op,          // Decoded PIM operation
    output logic        pim_valid,       // 1 = valid supported PIM instruction
    output logic        illegal_custom   // 1 = opcode is custom-1 but encoding is invalid
);

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    assign is_custom = (opcode == OP_CUSTOM1);

    always_comb begin
        pim_op         = PIM_VADD;
        pim_valid      = 1'b0;
        illegal_custom = 1'b0;

        if (is_custom) begin
            // Standard PIM instructions currently use funct7 = 7'b0000000
            if (funct7 == 7'b0000000) begin
                case (funct3)
                    3'b000: begin pim_op = PIM_VADD;  pim_valid = 1'b1; end
                    3'b001: begin pim_op = PIM_VMAC;  pim_valid = 1'b1; end
                    3'b010: begin pim_op = PIM_VAND;  pim_valid = 1'b1; end
                    3'b011: begin pim_op = PIM_VSUM;  pim_valid = 1'b1; end
                    3'b100: begin pim_op = PIM_CFG;   pim_valid = 1'b1; end
                    3'b101: begin pim_op = PIM_VFILL; pim_valid = 1'b1; end
                    default: begin
                        pim_valid      = 1'b0;
                        illegal_custom = 1'b1; // Unknown custom function
                    end
                endcase
            end else begin
                pim_valid      = 1'b0;
                illegal_custom = 1'b1;
            end
        end
    end

endmodule
