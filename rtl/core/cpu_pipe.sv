// ============================================================================
// File:        cpu_pipe.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Top-Level 5-Stage Pipelined RV32I Processor Core.
//
//              Pipeline Stages:
//                1. IF  - Instruction Fetch
//                2. ID  - Instruction Decode & Register Fetch
//                3. EX  - Execute & Address Calculation
//                4. MEM - Memory Access
//                5. WB  - Register Writeback
//
//              Features:
//                - Full Data Forwarding (EX-to-EX and MEM-to-EX)
//                - Load-Use Hazard Detection with 1-Cycle Stall
//                - Branch & Jump Misprediction Flushes in EX Stage
//                - WB-to-ID Register File Forwarding (Write-First Semantics)
//                - Byte-Addressable Memory Subsystem
// ============================================================================

module cpu_pipe
    import riscv_pkg::*;
#(
    parameter logic [31:0] RESET_ADDR = 32'h0000_0000,
    parameter int          MEM_DEPTH  = 1024,
    parameter string       INIT_FILE  = ""
) (
    input  logic        clk,
    input  logic        rst_n,

    // Hardware Interrupt Lines (from CLINT / PLIC)
    input  logic        timer_irq,
    input  logic        external_irq,

    // Privileged Architecture State
    output logic [1:0]  priv_mode_out,
    output logic [31:0] satp_out,

    // External Memory & Instruction Fetch Interface
    input  logic [31:0] ext_mem_rdata,
    input  logic [31:0] ext_instr_rdata,

    // Debug / Observation Ports
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_alu_result,
    output logic [31:0] dbg_wb_data,
    output logic        dbg_reg_write,
    output logic        dbg_stall,
    output logic        dbg_flush
);

    // ========================================================================
    // Forward Declarations of Stage Signals
    // ========================================================================

    // Hazard control wires
    logic stall_pc;
    logic stall_if_id;
    logic flush_if_id;
    logic flush_id_ex;

    // --- IF Stage Signals ---
    logic [31:0] pc_if;
    logic [31:0] pc_next;
    logic [31:0] pc_plus4_if;
    logic [31:0] instr_if;

    // --- ID Stage Signals ---
    logic [31:0] pc_id;
    logic [31:0] instr_id;

    wire  [6:0]  opcode_id   = instr_id[6:0];
    wire  [4:0]  rd_id       = instr_id[11:7];
    wire  [2:0]  funct3_id   = instr_id[14:12];
    wire  [4:0]  rs1_id      = instr_id[19:15];
    wire  [4:0]  rs2_id      = instr_id[24:20];
    wire         funct7_5_id = instr_id[30];

    logic        reg_write_id;
    alu_src_t    alu_src_id;
    logic        mem_write_id;
    logic        mem_read_id;
    wb_src_t     wb_src_id;
    logic        branch_id;
    logic        jump_id;
    logic [1:0]  alu_op_hint_id;

    logic [31:0] rf_rs1_data;
    logic [31:0] rf_rs2_data;
    logic [31:0] rs1_data_id;
    logic [31:0] rs2_data_id;
    logic [31:0] imm_id;

    // --- EX Stage Signals ---
    logic        reg_write_ex;
    alu_src_t    alu_src_ex;
    logic        mem_write_ex;
    logic        mem_read_ex;
    wb_src_t     wb_src_ex;
    logic        branch_ex;
    logic        jump_ex;
    logic [1:0]  alu_op_hint_ex;

    logic [31:0] pc_ex;
    logic [31:0] rs1_data_ex;
    logic [31:0] rs2_data_ex;
    logic [31:0] imm_ex;
    logic [2:0]  funct3_ex;
    logic        funct7_5_ex;
    logic [4:0]  rs1_addr_ex;
    logic [4:0]  rs2_addr_ex;
    logic [4:0]  rd_addr_ex;
    logic [6:0]  opcode_ex;
    logic [31:0] instr_ex;

    // Privileged Architecture & Trap Wires
    logic [31:0] csr_rdata;
    logic        irq_pending;
    logic [31:0] mtvec_out;
    logic [31:0] stvec_out;
    logic [31:0] mepc_out;
    logic [31:0] sepc_out;
    logic [1:0]  priv_mode_internal;
    logic [31:0] satp_internal;

    assign priv_mode_out = priv_mode_internal;
    assign satp_out      = satp_internal;

    logic        trap_enter;
    logic        trap_is_interrupt;
    logic [30:0] trap_cause;
    logic [31:0] trap_pc;
    logic [31:0] trap_val;
    logic        trap_return_m;
    logic        trap_return_s;
    logic        trap_redirect;
    logic [31:0] trap_pc_target;

    logic [1:0]  forward_a;
    logic [1:0]  forward_b;
    logic [31:0] fwd_rs1_data;
    logic [31:0] fwd_rs2_data;

    logic [31:0] alu_in_a;
    logic [31:0] alu_in_b;
    alu_op_t     alu_op_ex;
    logic [31:0] alu_result_ex;
    /* verilator lint_off UNUSEDSIGNAL */
    logic        alu_zero_ex;
    /* verilator lint_on UNUSEDSIGNAL */

    logic        branch_taken_ex;
    logic [31:0] branch_target_ex;
    logic [31:0] jalr_target_ex;
    logic [31:0] pc_plus4_ex;

    // --- MEM Stage Signals ---
    logic        reg_write_mem;
    logic        mem_write_mem;
    logic        mem_read_mem;
    wb_src_t     wb_src_mem;

    logic [31:0] alu_result_mem;
    logic [31:0] write_data_mem;
    logic [4:0]  rd_addr_mem;
    logic [2:0]  funct3_mem;
    logic [31:0] pc_plus4_mem;
    logic [31:0] mem_read_data_mem;

    // --- WB Stage Signals ---
    logic        reg_write_wb;
    wb_src_t     wb_src_wb;
    logic [31:0] alu_result_wb;
    logic [31:0] mem_read_data_wb;
    logic [4:0]  rd_addr_wb;
    logic [31:0] pc_plus4_wb;
    logic [31:0] wb_data;

    // ========================================================================
    // 1. STAGE 1: INSTRUCTION FETCH (IF)
    // ========================================================================
    assign pc_plus4_if      = pc_if + 32'd4;
    assign branch_target_ex = pc_ex + imm_ex;
    assign jalr_target_ex   = (fwd_rs1_data + imm_ex) & ~32'd1;
    assign pc_plus4_ex      = pc_ex + 32'd4;

    // Next PC selection (evaluated in EX stage for branches/jumps/traps)
    always_comb begin
        if (trap_redirect) begin
            pc_next = trap_pc_target;
        end else if (jump_ex) begin
            pc_next = (opcode_ex == OP_JALR) ? jalr_target_ex : branch_target_ex;
        end else if (branch_taken_ex) begin
            pc_next = branch_target_ex;
        end else begin
            pc_next = pc_plus4_if;
        end
    end

    pc_reg #(
        .RESET_ADDR(RESET_ADDR)
    ) u_pc_reg (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (!stall_pc), // Freeze PC during load-use hazard
        .pc_next (pc_next),
        .pc      (pc_if)
    );

    logic [31:0] instr_if_rom;

    instr_mem #(
        .DEPTH     (MEM_DEPTH),
        .INIT_FILE (INIT_FILE)
    ) u_instr_mem (
        .addr  (pc_if),
        .instr (instr_if_rom)
    );

    // Mux between internal Boot ROM (0x0000_0000) and Main RAM (0x8000_0000)
    assign instr_if = (pc_if[31]) ? ext_instr_rdata : instr_if_rom;

    if_id_reg u_if_id_reg (
        .clk      (clk),
        .rst_n    (rst_n),
        .stall    (stall_if_id),
        .flush    (flush_if_id),
        .pc_if    (pc_if),
        .instr_if (instr_if),
        .pc_id    (pc_id),
        .instr_id (instr_id)
    );

    // ========================================================================
    // 2. STAGE 2: INSTRUCTION DECODE & REGISTER FETCH (ID)
    // ========================================================================
    ctrl_unit u_ctrl_unit (
        .opcode    (opcode_id),
        .funct3    (funct3_id),
        .reg_write (reg_write_id),
        .alu_src   (alu_src_id),
        .mem_write (mem_write_id),
        .mem_read  (mem_read_id),
        .wb_src    (wb_src_id),
        .branch    (branch_id),
        .jump      (jump_id),
        .alu_op    (alu_op_hint_id)
    );

    reg_file u_reg_file (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1_id),
        .rs1_data (rf_rs1_data),
        .rs2_addr (rs2_id),
        .rs2_data (rf_rs2_data),
        .wr_en    (reg_write_wb),
        .rd_addr  (rd_addr_wb),
        .rd_data  (wb_data)
    );

    // WB-to-ID Internal Forwarding (write-first semantics):
    // If WB writes to register rs in the same cycle ID reads rs, forward wb_data.
    assign rs1_data_id = (reg_write_wb && (rd_addr_wb != 5'b0) && (rd_addr_wb == rs1_id))
                       ? wb_data : rf_rs1_data;
    assign rs2_data_id = (reg_write_wb && (rd_addr_wb != 5'b0) && (rd_addr_wb == rs2_id))
                       ? wb_data : rf_rs2_data;

    imm_gen u_imm_gen (
        .instr (instr_id),
        .imm   (imm_id)
    );

    hazard_unit u_hazard_unit (
        .rs1_addr_id     (rs1_id),
        .rs2_addr_id     (rs2_id),
        .mem_read_ex     (mem_read_ex),
        .rd_addr_ex      (rd_addr_ex),
        .branch_taken_ex (branch_taken_ex),
        .jump_ex         (jump_ex),
        .trap_redirect   (trap_redirect),
        .stall_pc        (stall_pc),
        .stall_if_id     (stall_if_id),
        .flush_if_id     (flush_if_id),
        .flush_id_ex     (flush_id_ex)
    );

    id_ex_reg u_id_ex_reg (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (flush_id_ex),

        .reg_write_id   (reg_write_id),
        .alu_src_id     (alu_src_id),
        .mem_write_id   (mem_write_id),
        .mem_read_id    (mem_read_id),
        .wb_src_id      (wb_src_id),
        .branch_id      (branch_id),
        .jump_id        (jump_id),
        .alu_op_hint_id (alu_op_hint_id),

        .pc_id          (pc_id),
        .rs1_data_id    (rs1_data_id),
        .rs2_data_id    (rs2_data_id),
        .imm_id         (imm_id),
        .funct3_id      (funct3_id),
        .funct7_5_id    (funct7_5_id),
        .rs1_addr_id    (rs1_id),
        .rs2_addr_id    (rs2_id),
        .rd_addr_id     (rd_id),
        .opcode_id      (opcode_id),
        .instr_id       (instr_id),

        .reg_write_ex   (reg_write_ex),
        .alu_src_ex     (alu_src_ex),
        .mem_write_ex   (mem_write_ex),
        .mem_read_ex    (mem_read_ex),
        .wb_src_ex      (wb_src_ex),
        .branch_ex      (branch_ex),
        .jump_ex        (jump_ex),
        .alu_op_hint_ex (alu_op_hint_ex),

        .pc_ex          (pc_ex),
        .rs1_data_ex    (rs1_data_ex),
        .rs2_data_ex    (rs2_data_ex),
        .imm_ex         (imm_ex),
        .funct3_ex      (funct3_ex),
        .funct7_5_ex    (funct7_5_ex),
        .rs1_addr_ex    (rs1_addr_ex),
        .rs2_addr_ex    (rs2_addr_ex),
        .rd_addr_ex     (rd_addr_ex),
        .opcode_ex      (opcode_ex),
        .instr_ex       (instr_ex)
    );

    // ========================================================================
    // 3. STAGE 3: EXECUTE (EX)
    // ========================================================================
    forwarding_unit u_forwarding_unit (
        .rs1_addr_ex   (rs1_addr_ex),
        .rs2_addr_ex   (rs2_addr_ex),
        .reg_write_mem (reg_write_mem),
        .rd_addr_mem   (rd_addr_mem),
        .reg_write_wb  (reg_write_wb),
        .rd_addr_wb    (rd_addr_wb),
        .forward_a     (forward_a),
        .forward_b     (forward_b)
    );

    // Forwarding Mux for rs1
    always_comb begin
        case (forward_a)
            2'b10:   fwd_rs1_data = alu_result_mem; // EX hazard
            2'b01:   fwd_rs1_data = wb_data;        // MEM hazard
            default: fwd_rs1_data = rs1_data_ex;    // No hazard
        endcase
    end

    // Forwarding Mux for rs2
    always_comb begin
        case (forward_b)
            2'b10:   fwd_rs2_data = alu_result_mem; // EX hazard
            2'b01:   fwd_rs2_data = wb_data;        // MEM hazard
            default: fwd_rs2_data = rs2_data_ex;    // No hazard
        endcase
    end

    // ALU Operand A Selection: AUIPC uses PC, LUI uses 0, others use fwd_rs1
    always_comb begin
        if (opcode_ex == OP_AUIPC)
            alu_in_a = pc_ex;
        else if (opcode_ex == OP_LUI)
            alu_in_a = 32'b0;
        else
            alu_in_a = fwd_rs1_data;
    end

    // ALU Operand B Selection: Immediate vs Forwarded rs2
    assign alu_in_b = (alu_src_ex == ALU_SRC_IMM) ? imm_ex : fwd_rs2_data;

    alu_ctrl u_alu_ctrl (
        .alu_op_hint (alu_op_hint_ex),
        .funct3      (funct3_ex),
        .funct7_5    (funct7_5_ex),
        .alu_op      (alu_op_ex)
    );

    alu u_alu (
        .a      (alu_in_a),
        .b      (alu_in_b),
        .alu_op (alu_op_ex),
        .result (alu_result_ex),
        .zero   (alu_zero_ex)
    );

    branch_unit u_branch_unit (
        .branch       (branch_ex),
        .funct3       (funct3_ex),
        .rs1_data     (fwd_rs1_data),
        .rs2_data     (fwd_rs2_data),
        .branch_taken (branch_taken_ex)
    );

    // ========================================================================
    // Privileged Architecture & Trap Control Units
    // ========================================================================
    trap_ctrl u_trap_ctrl (
        .instr             (instr_ex),
        .current_pc        (pc_ex),
        .priv_mode         (priv_mode_internal),
        .illegal_instr     (1'b0),
        .irq_pending       (irq_pending),
        .timer_irq         (timer_irq),
        .external_irq      (external_irq),
        .mtvec             (mtvec_out),
        .stvec             (stvec_out),
        .mepc              (mepc_out),
        .sepc              (sepc_out),
        .trap_enter        (trap_enter),
        .trap_is_interrupt (trap_is_interrupt),
        .trap_cause        (trap_cause),
        .trap_pc           (trap_pc),
        .trap_val          (trap_val),
        .trap_return_m     (trap_return_m),
        .trap_return_s     (trap_return_s),
        .trap_redirect     (trap_redirect),
        .trap_pc_target    (trap_pc_target)
    );

    wire is_csr_ex = (opcode_ex == OP_SYSTEM) && (funct3_ex != CSR_OP_NONE);
    wire csr_we_ex = is_csr_ex && !flush_id_ex &&
                     ((funct3_ex == CSR_OP_RW) || (funct3_ex == CSR_OP_RWI) || (rs1_addr_ex != 5'b0));
    wire [31:0] csr_wdata_ex = funct3_ex[2] ? {27'b0, rs1_addr_ex} : fwd_rs1_data;

    csr_file u_csr_file (
        .clk               (clk),
        .rst_n             (rst_n),
        .csr_addr          (instr_ex[31:20]),
        .csr_op            (funct3_ex),
        .csr_we            (csr_we_ex),
        .csr_wdata         (csr_wdata_ex),
        .csr_rdata         (csr_rdata),
        .trap_enter        (trap_enter),
        .trap_is_interrupt (trap_is_interrupt),
        .trap_cause        (trap_cause),
        .trap_pc           (trap_pc),
        .trap_val          (trap_val),
        .trap_return_m     (trap_return_m),
        .trap_return_s     (trap_return_s),
        .timer_irq         (timer_irq),
        .external_irq      (external_irq),
        .irq_pending       (irq_pending),
        .mtvec_out         (mtvec_out),
        .stvec_out         (stvec_out),
        .mepc_out          (mepc_out),
        .sepc_out          (sepc_out),
        .priv_mode_out     (priv_mode_internal),
        .satp_out          (satp_internal)
    );

    wire [31:0] ex_result_data = (wb_src_ex == WB_SRC_CSR) ? csr_rdata : alu_result_ex;

    ex_mem_reg u_ex_mem_reg (
        .clk            (clk),
        .rst_n          (rst_n),
        .reg_write_ex   (reg_write_ex),
        .mem_write_ex   (mem_write_ex),
        .mem_read_ex    (mem_read_ex),
        .wb_src_ex      (wb_src_ex),
        .alu_result_ex  (ex_result_data),
        .write_data_ex  (fwd_rs2_data),
        .rd_addr_ex     (rd_addr_ex),
        .funct3_ex      (funct3_ex),
        .pc_plus4_ex    (pc_plus4_ex),

        .reg_write_mem  (reg_write_mem),
        .mem_write_mem  (mem_write_mem),
        .mem_read_mem   (mem_read_mem),
        .wb_src_mem     (wb_src_mem),
        .alu_result_mem (alu_result_mem),
        .write_data_mem (write_data_mem),
        .rd_addr_mem    (rd_addr_mem),
        .funct3_mem     (funct3_mem),
        .pc_plus4_mem   (pc_plus4_mem)
    );

    // ========================================================================
    // 4. STAGE 4: MEMORY ACCESS (MEM)
    // ========================================================================
    data_mem #(
        .DEPTH(MEM_DEPTH)
    ) u_data_mem (
        .clk        (clk),
        .mem_read   (mem_read_mem),
        .mem_write  (mem_write_mem),
        .funct3     (funct3_mem),
        .addr       (alu_result_mem),
        .write_data (write_data_mem),
        .read_data  (mem_read_data_mem)
    );

    // Mux between internal data memory (0x0000_0000) and external bus peripherals/RAM
    wire is_ext_mem = (alu_result_mem[31:28] != 4'h0);
    wire [31:0] effective_mem_rdata = is_ext_mem ? ext_mem_rdata : mem_read_data_mem;

    mem_wb_reg u_mem_wb_reg (
        .clk              (clk),
        .rst_n            (rst_n),
        .reg_write_mem    (reg_write_mem),
        .wb_src_mem       (wb_src_mem),
        .alu_result_mem   (alu_result_mem),
        .mem_read_data_mem(effective_mem_rdata),
        .rd_addr_mem      (rd_addr_mem),
        .pc_plus4_mem     (pc_plus4_mem),

        .reg_write_wb     (reg_write_wb),
        .wb_src_wb        (wb_src_wb),
        .alu_result_wb    (alu_result_wb),
        .mem_read_data_wb (mem_read_data_wb),
        .rd_addr_wb       (rd_addr_wb),
        .pc_plus4_wb      (pc_plus4_wb)
    );

    // ========================================================================
    // 5. STAGE 5: WRITEBACK (WB)
    // ========================================================================
    always_comb begin
        case (wb_src_wb)
            WB_SRC_ALU: wb_data = alu_result_wb;
            WB_SRC_MEM: wb_data = mem_read_data_wb;
            WB_SRC_PC4: wb_data = pc_plus4_wb;
            WB_SRC_CSR: wb_data = alu_result_wb;
            default:    wb_data = alu_result_wb;
        endcase
    end

    // ========================================================================
    // Debug Outputs
    // ========================================================================
    assign dbg_pc         = pc_if;
    assign dbg_instr      = instr_id;
    assign dbg_alu_result = ex_result_data;
    assign dbg_wb_data    = wb_data;
    assign dbg_reg_write  = reg_write_wb;
    assign dbg_stall      = stall_pc;
    assign dbg_flush      = flush_if_id;

endmodule
