// ============================================================================
// File:        pim_simd_alu.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: 8-Lane 32-bit Integer SIMD ALU for Processing-In-Memory (PIM).
//
//              Parallel execution engine operating on 256-bit vectors
//              (8 parallel 32-bit elements):
//                - PIM_VADD:  Parallel vector addition
//                - PIM_VMAC:  Vector multiply-accumulate (Dot Product)
//                - PIM_VAND:  Parallel vector bitwise AND
//                - PIM_VSUM:  Binary adder tree reduction (8 elements -> 1 scalar)
//                - PIM_CFG:   No-op on datapath (handled by controller)
//                - PIM_VFILL: Scalar broadcast to all 8 lanes
//
//              Zero-cycle combinational datapath with output register.
// ============================================================================

module pim_simd_alu
    import riscv_pkg::*;
#(
    parameter int LANES = 8
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic              clk,
    input  logic              rst_n,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic              en,

    input  pim_op_t           op,
    input  logic [LANES-1:0][31:0] vec_a,       // 8x 32-bit operands from Buffer A
    input  logic [LANES-1:0][31:0] vec_b,       // 8x 32-bit operands from Buffer B
    input  logic [31:0]       scalar_in,   // Broadcast value or accumulator init

    output logic [LANES-1:0][31:0] result_vec,  // 8x 32-bit SIMD result
    output logic [31:0]       reduction_out // 32-bit scalar sum from tree reduction
);

    // Combinational results
    logic [LANES-1:0][31:0] comb_result;
    logic [31:0]       comb_reduction;

    // ------------------------------------------------------------------------
    // Binary Adder Tree for Reduction (VSUM and VMAC)
    // ------------------------------------------------------------------------
    // Reduction on vec_a for PIM_VSUM
    wire [31:0] sum_a_l1_0 = vec_a[0] + vec_a[1];
    wire [31:0] sum_a_l1_1 = vec_a[2] + vec_a[3];
    wire [31:0] sum_a_l1_2 = vec_a[4] + vec_a[5];
    wire [31:0] sum_a_l1_3 = vec_a[6] + vec_a[7];

    wire [31:0] sum_a_l2_0 = sum_a_l1_0 + sum_a_l1_1;
    wire [31:0] sum_a_l2_1 = sum_a_l1_2 + sum_a_l1_3;

    wire [31:0] vsum_reduction = sum_a_l2_0 + sum_a_l2_1;

    // Multiplication products for PIM_VMAC
    wire [31:0] prod [LANES-1:0];
    generate
        for (genvar g = 0; g < LANES; g++) begin : gen_prod
            assign prod[g] = vec_a[g] * vec_b[g];
        end
    endgenerate

    // Reduction on products for PIM_VMAC
    wire [31:0] mac_l1_0 = prod[0] + prod[1];
    wire [31:0] mac_l1_1 = prod[2] + prod[3];
    wire [31:0] mac_l1_2 = prod[4] + prod[5];
    wire [31:0] mac_l1_3 = prod[6] + prod[7];

    wire [31:0] mac_l2_0 = mac_l1_0 + mac_l1_1;
    wire [31:0] mac_l2_1 = mac_l1_2 + mac_l1_3;

    wire [31:0] vmac_reduction = mac_l2_0 + mac_l2_1;

    // ------------------------------------------------------------------------
    // SIMD Parallel Lanes Logic
    // ------------------------------------------------------------------------
    always_comb begin
        comb_result    = '0;
        comb_reduction = 32'b0;

        case (op)
            PIM_VADD: begin
                for (int i = 0; i < LANES; i++) begin
                    comb_result[i] = vec_a[i] + vec_b[i];
                end
            end

            PIM_VMAC: begin
                for (int i = 0; i < LANES; i++) begin
                    comb_result[i] = prod[i];
                end
                comb_reduction = vmac_reduction;
            end

            PIM_VAND: begin
                for (int i = 0; i < LANES; i++) begin
                    comb_result[i] = vec_a[i] & vec_b[i];
                end
            end

            PIM_VSUM: begin
                comb_result[0] = vsum_reduction;
                for (int i = 1; i < LANES; i++) begin
                    comb_result[i] = 32'b0;
                end
                comb_reduction = vsum_reduction;
            end

            PIM_VFILL: begin
                for (int i = 0; i < LANES; i++) begin
                    comb_result[i] = scalar_in;
                end
            end

            default: begin
                for (int i = 0; i < LANES; i++) begin
                    comb_result[i] = vec_a[i];
                end
            end
        endcase
    end

    // Combinational outputs (gated by enable)
    assign result_vec    = en ? comb_result    : '0;
    assign reduction_out = en ? comb_reduction : 32'b0;

endmodule
