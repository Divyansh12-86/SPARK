// ============================================================================
// File:        csr_file.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Control and Status Register (CSR) File for RV32I Privileged Arch.
//
//              Implements Machine-mode and Supervisor-mode CSRs required
//              for exception handling, timer/external interrupts, and xv6 boot:
//                - Machine:    mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip, mcycle, mcycleh
//                - Supervisor: sstatus, sie, stvec, sscratch, sepc, scause, stval, sip, satp
//
//              Supports atomic CSR instructions (CSRRW, CSRRS, CSRRC, etc.)
//              and hardware trap enter/return hooks.
// ============================================================================

module csr_file
    import riscv_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Instruction Access Port
    input  logic [11:0] csr_addr,      // 12-bit CSR address from instruction
    input  logic [2:0]  csr_op,        // funct3 (CSRRW, CSRRS, CSRRC, etc.)
    input  logic        csr_we,        // 1 = write enable
    input  logic [31:0] csr_wdata,     // Data from rs1 or zero-extended zimm
    output logic [31:0] csr_rdata,     // Read value returned to rd

    // Hardware Trap Entry Hooks (from trap_ctrl)
    input  logic        trap_enter,
    input  logic        trap_is_interrupt,
    input  logic [30:0] trap_cause,
    input  logic [31:0] trap_pc,
    input  logic [31:0] trap_val,

    // Hardware Trap Return Hooks (MRET / SRET)
    input  logic        trap_return_m,
    input  logic        trap_return_s,

    // Hardware Interrupt Lines (from CLINT / PLIC)
    input  logic        timer_irq,     // Machine timer interrupt
    input  logic        external_irq,  // Machine external interrupt

    // Trap & Control Outputs
    output logic        irq_pending,   // Asserted when enabled interrupt is active
    output logic [31:0] mtvec_out,     // Machine trap handler address
    output logic [31:0] stvec_out,     // Supervisor trap handler address
    output logic [31:0] mepc_out,      // Saved exception PC for MRET
    output logic [31:0] sepc_out,      // Saved exception PC for SRET
    output logic [1:0]  priv_mode_out, // Current privilege mode (M, S, U)
    output logic [31:0] satp_out       // Page table base address (Sv32)
);

    // ========================================================================
    // Current Privilege Level
    // ========================================================================
    logic [1:0] priv_mode;
    assign priv_mode_out = priv_mode;

    // ========================================================================
    // Machine Mode CSR Registers
    // ========================================================================
    // mstatus fields:
    //   [3]:  MIE  (Machine Interrupt Enable)
    //   [7]:  MPIE (Machine Previous Interrupt Enable)
    //   [12:11]: MPP (Machine Previous Privilege Mode)
    logic [31:0] mstatus;
    logic [31:0] mie;
    logic [31:0] mtvec;
    logic [31:0] mscratch;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;
    logic [63:0] mcycle;

    // ========================================================================
    // Supervisor Mode CSR Registers
    // ========================================================================
    logic [31:0] stvec;
    logic [31:0] sscratch;
    logic [31:0] sepc;
    logic [31:0] scause;
    logic [31:0] stval;
    logic [31:0] satp;

    assign mtvec_out = mtvec;
    assign stvec_out = stvec;
    assign mepc_out  = mepc;
    assign sepc_out  = sepc;
    assign satp_out  = satp;

    // MIP reflects real-time hardware interrupt status:
    //   bit 7 = MTIP (Timer), bit 11 = MEIP (External)
    wire [31:0] mip = {20'b0, external_irq, 3'b0, timer_irq, 7'b0};

    // Global Interrupt Pending: enabled only if mstatus.MIE is 1
    // and matching bit in mie is set.
    wire m_timer_active    = mstatus[3] && mie[7]  && timer_irq;
    wire m_external_active = mstatus[3] && mie[11] && external_irq;
    assign irq_pending     = m_timer_active || m_external_active;

    // ========================================================================
    // Asynchronous CSR Read Port
    // ========================================================================
    always_comb begin
        case (csr_addr)
            CSR_MSTATUS:  csr_rdata = mstatus;
            CSR_MISA:     csr_rdata = 32'h4000_1100; // RV32I base (I + S modes)
            CSR_MIE:      csr_rdata = mie;
            CSR_MTVEC:    csr_rdata = mtvec;
            CSR_MSCRATCH: csr_rdata = mscratch;
            CSR_MEPC:     csr_rdata = mepc;
            CSR_MCAUSE:   csr_rdata = mcause;
            CSR_MTVAL:    csr_rdata = mtval;
            CSR_MIP:      csr_rdata = mip;
            CSR_MCYCLE:   csr_rdata = mcycle[31:0];
            CSR_MCYCLEH:  csr_rdata = mcycle[63:32];

            CSR_SSTATUS:  csr_rdata = mstatus & 32'h0000_0122; // Restricted S-view
            CSR_STVEC:    csr_rdata = stvec;
            CSR_SSCRATCH: csr_rdata = sscratch;
            CSR_SEPC:     csr_rdata = sepc;
            CSR_SCAUSE:   csr_rdata = scause;
            CSR_STVAL:    csr_rdata = stval;
            CSR_SATP:     csr_rdata = satp;
            default:      csr_rdata = 32'b0;
        endcase
    end

    // ========================================================================
    // Next Value Calculation for Instruction Writes
    // ========================================================================
    logic [31:0] csr_next_val;
    always_comb begin
        case (csr_op)
            CSR_OP_RW, CSR_OP_RWI: csr_next_val = csr_wdata;
            CSR_OP_RS, CSR_OP_RSI: csr_next_val = csr_rdata | csr_wdata;
            CSR_OP_RC, CSR_OP_RCI: csr_next_val = csr_rdata & (~csr_wdata);
            default:               csr_next_val = csr_wdata;
        endcase
    end

    // ========================================================================
    // Synchronous CSR State Updates
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            priv_mode <= PRIV_M; // Core starts in Machine mode on reset
            mstatus   <= 32'h0000_1800; // MPP = Machine mode
            mie       <= 32'b0;
            mtvec     <= 32'b0;
            mscratch  <= 32'b0;
            mepc      <= 32'b0;
            mcause    <= 32'b0;
            mtval     <= 32'b0;
            mcycle    <= 64'b0;

            stvec     <= 32'b0;
            sscratch  <= 32'b0;
            sepc      <= 32'b0;
            scause    <= 32'b0;
            stval     <= 32'b0;
            satp      <= 32'b0;
        end else begin
            // Free-running 64-bit cycle counter
            mcycle <= mcycle + 64'd1;

            // ----------------------------------------------------------------
            // 1. Hardware Trap Entry
            // ----------------------------------------------------------------
            if (trap_enter) begin
                priv_mode      <= PRIV_M;
                mstatus[7]     <= mstatus[3]; // MPIE <= MIE
                mstatus[3]     <= 1'b0;       // Disable interrupts (MIE <= 0)
                mstatus[12:11] <= priv_mode;  // MPP <= current privilege mode
                mepc           <= trap_pc;
                mcause         <= {trap_is_interrupt, trap_cause};
                mtval          <= trap_val;
            end

            // ----------------------------------------------------------------
            // 2. Hardware Trap Return (MRET)
            // ----------------------------------------------------------------
            else if (trap_return_m) begin
                priv_mode      <= mstatus[12:11]; // Restore privilege from MPP
                mstatus[3]     <= mstatus[7];     // MIE <= MPIE
                mstatus[7]     <= 1'b1;           // MPIE <= 1
                mstatus[12:11] <= PRIV_U;         // Default next MPP to User
            end

            // ----------------------------------------------------------------
            // 3. Hardware Trap Return (SRET)
            // ----------------------------------------------------------------
            else if (trap_return_s) begin
                priv_mode      <= {1'b0, mstatus[8]}; // Restore SPP
                mstatus[1]     <= mstatus[5];         // SIE <= SPIE
                mstatus[5]     <= 1'b1;               // SPIE <= 1
            end

            // ----------------------------------------------------------------
            // 4. Instruction Writes
            // ----------------------------------------------------------------
            else if (csr_we) begin
                case (csr_addr)
                    CSR_MSTATUS:  mstatus  <= csr_next_val;
                    CSR_MIE:      mie      <= csr_next_val;
                    CSR_MTVEC:    mtvec    <= csr_next_val;
                    CSR_MSCRATCH: mscratch <= csr_next_val;
                    CSR_MEPC:     mepc     <= csr_next_val;
                    CSR_MCAUSE:   mcause   <= csr_next_val;
                    CSR_MTVAL:    mtval    <= csr_next_val;

                    CSR_SSTATUS:  mstatus  <= (mstatus & ~32'h0000_0122) | (csr_next_val & 32'h0000_0122);
                    CSR_STVEC:    stvec    <= csr_next_val;
                    CSR_SSCRATCH: sscratch <= csr_next_val;
                    CSR_SEPC:     sepc     <= csr_next_val;
                    CSR_SCAUSE:   scause   <= csr_next_val;
                    CSR_STVAL:    stval    <= csr_next_val;
                    CSR_SATP:     satp     <= csr_next_val;
                    default: ;
                endcase
            end
        end
    end

endmodule
