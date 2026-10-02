// ============================================================================
// File:        cpu_single.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Top-level Single-Cycle RV32I Processor Core.
//
//              Integrates:
//                - Program Counter (pc_reg.sv)
//                - Instruction Memory (instr_mem.sv)
//                - Register File (reg_file.sv)
//                - Immediate Generator (imm_gen.sv)
//                - Main Control Unit (ctrl_unit.sv)
//                - ALU Control (alu_ctrl.sv)
//                - Arithmetic Logic Unit (alu.sv)
//                - Branch Decision Unit (branch_unit.sv)
//                - Data Memory (data_mem.sv)
// ============================================================================

module cpu_single
    import riscv_pkg::*;
#(
    parameter logic [31:0] RESET_ADDR = 32'h0000_0000,
    parameter int          MEM_DEPTH  = 1024,
    parameter string       INIT_FILE  = ""
) (
    input  logic        clk,
    input  logic        rst_n,

    // Debug / Observation Ports
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_alu_result,
    output logic [31:0] dbg_wb_data,
    output logic        dbg_reg_write
);

    // ========================================================================
    // Internal Signals
    // ========================================================================

    // PC wires
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic [31:0] pc_plus4;
    logic [31:0] branch_target;
    logic [31:0] jalr_target;

    // Instruction fields
    logic [31:0] instr;
    wire  [6:0]  opcode   = instr[6:0];
    wire  [4:0]  rd       = instr[11:7];
    wire  [2:0]  funct3   = instr[14:12];
    wire  [4:0]  rs1      = instr[19:15];
    wire  [4:0]  rs2      = instr[24:20];
    wire         funct7_5 = instr[30];

    // Control signals
    logic        reg_write;
    alu_src_t    alu_src;
    logic        mem_write;
    logic        mem_read;
    wb_src_t     wb_src;
    logic        branch;
    logic        jump;
    logic [1:0]  alu_op_hint;
    alu_op_t     alu_op;
    logic        branch_taken;

    // Register File wires
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] wb_data;

    // Immediate
    logic [31:0] imm;

    // ALU wires
    logic [31:0] alu_in_a;
    logic [31:0] alu_in_b;
    logic [31:0] alu_result;
    /* verilator lint_off UNUSEDSIGNAL */
    logic        alu_zero;
    /* verilator lint_on UNUSEDSIGNAL */

    // Data Memory wires
    logic [31:0] mem_read_data;

    // ========================================================================
    // 1. Program Counter & Fetch
    // ========================================================================
    assign pc_plus4      = pc + 32'd4;
    assign branch_target = pc + imm;
    assign jalr_target   = (rs1_data + imm) & ~32'd1; // RISC-V specifies LSB is 0

    always_comb begin
        if (jump) begin
            pc_next = (opcode == OP_JALR) ? jalr_target : branch_target;
        end else if (branch_taken) begin
            pc_next = branch_target;
        end else begin
            pc_next = pc_plus4;
        end
    end

    pc_reg #(
        .RESET_ADDR(RESET_ADDR)
    ) u_pc_reg (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (1'b1), // Always enabled in single-cycle CPU
        .pc_next (pc_next),
        .pc      (pc)
    );

    instr_mem #(
        .DEPTH     (MEM_DEPTH),
        .INIT_FILE (INIT_FILE)
    ) u_instr_mem (
        .addr  (pc),
        .instr (instr)
    );

    // ========================================================================
    // 2. Decode & Control
    // ========================================================================
    ctrl_unit u_ctrl_unit (
        .opcode    (opcode),
        .funct3    (funct3),
        .reg_write (reg_write),
        .alu_src   (alu_src),
        .mem_write (mem_write),
        .mem_read  (mem_read),
        .wb_src    (wb_src),
        .branch    (branch),
        .jump      (jump),
        .alu_op    (alu_op_hint)
    );

    alu_ctrl u_alu_ctrl (
        .alu_op_hint (alu_op_hint),
        .funct3      (funct3),
        .funct7_5    (funct7_5),
        .alu_op      (alu_op)
    );

    reg_file u_reg_file (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1),
        .rs1_data (rs1_data),
        .rs2_addr (rs2),
        .rs2_data (rs2_data),
        .wr_en    (reg_write),
        .rd_addr  (rd),
        .rd_data  (wb_data)
    );

    imm_gen u_imm_gen (
        .instr (instr),
        .imm   (imm)
    );

    branch_unit u_branch_unit (
        .branch       (branch),
        .funct3       (funct3),
        .rs1_data     (rs1_data),
        .rs2_data     (rs2_data),
        .branch_taken (branch_taken)
    );

    // ========================================================================
    // 3. Execute (ALU)
    // ========================================================================
    // Operand A selection:
    //   AUIPC: PC
    //   LUI:   0 (so 0 + imm = imm)
    //   All other: rs1_data
    always_comb begin
        if (opcode == OP_AUIPC)
            alu_in_a = pc;
        else if (opcode == OP_LUI)
            alu_in_a = 32'b0;
        else
            alu_in_a = rs1_data;
    end

    // Operand B selection:
    assign alu_in_b = (alu_src == ALU_SRC_IMM) ? imm : rs2_data;

    alu u_alu (
        .a      (alu_in_a),
        .b      (alu_in_b),
        .alu_op (alu_op),
        .result (alu_result),
        .zero   (alu_zero)
    );

    // ========================================================================
    // 4. Data Memory
    // ========================================================================
    data_mem #(
        .DEPTH(MEM_DEPTH)
    ) u_data_mem (
        .clk        (clk),
        .mem_read   (mem_read),
        .mem_write  (mem_write),
        .funct3     (funct3),
        .addr       (alu_result),
        .write_data (rs2_data),
        .read_data  (mem_read_data)
    );

    // ========================================================================
    // 5. Writeback Mux
    // ========================================================================
    always_comb begin
        case (wb_src)
            WB_SRC_ALU: wb_data = alu_result;
            WB_SRC_MEM: wb_data = mem_read_data;
            WB_SRC_PC4: wb_data = pc_plus4;
            default:    wb_data = alu_result;
        endcase
    end

    // ========================================================================
    // Debug Outputs
    // ========================================================================
    assign dbg_pc         = pc;
    assign dbg_instr      = instr;
    assign dbg_alu_result = alu_result;
    assign dbg_wb_data    = wb_data;
    assign dbg_reg_write  = reg_write;

endmodule
