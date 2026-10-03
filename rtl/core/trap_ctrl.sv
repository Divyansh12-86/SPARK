// ============================================================================
// File:        trap_ctrl.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Trap Controller for RV32I Privileged Architecture.
//
//              Orchestrates exception entry, interrupt arbitration, and
//              trap returns (MRET/SRET).
//              Redirects the Program Counter to mtvec/stvec on trap entry,
//              or mepc/sepc on trap return.
// ============================================================================

module trap_ctrl
    import riscv_pkg::*;
(
    // Instruction information from Execute stage
    input  logic [31:0] instr,
    input  logic [31:0] current_pc,
    input  logic [1:0]  priv_mode,
    input  logic        illegal_instr,

    // Interrupt signals from CSR file
    input  logic        irq_pending,
    input  logic        timer_irq,
    input  logic        external_irq,

    // Target vectors from CSR file
    input  logic [31:0] mtvec,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] stvec,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] mepc,
    input  logic [31:0] sepc,

    // Controls to CSR file
    output logic        trap_enter,
    output logic        trap_is_interrupt,
    output logic [30:0] trap_cause,
    output logic [31:0] trap_pc,
    output logic [31:0] trap_val,
    output logic        trap_return_m,
    output logic        trap_return_s,

    // Controls to CPU pipeline
    output logic        trap_redirect,    // 1 = redirect PC to trap handler or return PC
    output logic [31:0] trap_pc_target    // Target PC to jump to
);

    wire is_system = (instr[6:0] == OP_SYSTEM);

    // Decode specific privileged instructions
    wire is_ecall  = is_system && (instr == 32'h0000_0073);
    wire is_ebreak = is_system && (instr == 32'h0010_0073);
    wire is_mret   = is_system && (instr == 32'h3020_0073);
    wire is_sret   = is_system && (instr == 32'h1020_0073);

    assign trap_return_m = is_mret;
    assign trap_return_s = is_sret;

    always_comb begin
        trap_enter        = 1'b0;
        trap_is_interrupt = 1'b0;
        trap_cause        = 31'b0;
        trap_pc           = current_pc;
        trap_val          = 32'b0;
        trap_redirect     = 1'b0;
        trap_pc_target    = current_pc;

        // --------------------------------------------------------------------
        // 1. Asynchronous Hardware Interrupts (Higher priority than instructions)
        // --------------------------------------------------------------------
        if (irq_pending) begin
            trap_enter        = 1'b1;
            trap_is_interrupt = 1'b1;
            trap_pc           = current_pc;
            trap_val          = 32'b0;
            trap_redirect     = 1'b1;
            trap_pc_target    = mtvec; // Jump to Machine trap handler

            if (external_irq) begin
                trap_cause = INT_M_EXTERNAL;
            end else if (timer_irq) begin
                trap_cause = INT_M_TIMER;
            end
        end

        // --------------------------------------------------------------------
        // 2. Synchronous Exceptions (ECALL, EBREAK, Illegal Instruction)
        // --------------------------------------------------------------------
        else if (illegal_instr) begin
            trap_enter        = 1'b1;
            trap_is_interrupt = 1'b0;
            trap_cause        = EXC_ILLEGAL_OP;
            trap_pc           = current_pc;
            trap_val          = instr; // Bad instruction word in mtval
            trap_redirect     = 1'b1;
            trap_pc_target    = mtvec;
        end else if (is_ecall) begin
            trap_enter        = 1'b1;
            trap_is_interrupt = 1'b0;
            trap_pc           = current_pc;
            trap_val          = 32'b0;
            trap_redirect     = 1'b1;
            trap_pc_target    = mtvec;

            case (priv_mode)
                PRIV_U:  trap_cause = EXC_ECALL_U;
                PRIV_S:  trap_cause = EXC_ECALL_S;
                default: trap_cause = EXC_ECALL_M;
            endcase
        end else if (is_ebreak) begin
            trap_enter        = 1'b1;
            trap_is_interrupt = 1'b0;
            trap_cause        = EXC_BREAKPOINT;
            trap_pc           = current_pc;
            trap_val          = current_pc;
            trap_redirect     = 1'b1;
            trap_pc_target    = mtvec;
        end

        // --------------------------------------------------------------------
        // 3. Trap Return Execution (MRET / SRET)
        // --------------------------------------------------------------------
        else if (is_mret) begin
            trap_redirect  = 1'b1;
            trap_pc_target = mepc;
        end else if (is_sret) begin
            trap_redirect  = 1'b1;
            trap_pc_target = sepc;
        end
    end

endmodule
