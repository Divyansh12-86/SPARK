// ============================================================================
// File:        clint.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Core Local Interruptor (CLINT) for RISC-V.
//
//              Memory-Mapped Registers (Base 0x2000_0000):
//                Offset 0x0000: msip      (Machine Software Interrupt Pending, bit 0)
//                Offset 0x4000: mtimecmp  (Machine Timer Compare, bits [31:0])
//                Offset 0x4004: mtimecmph (Machine Timer Compare, bits [63:32])
//                Offset 0xBFF8: mtime     (Free-running Real-Time Counter, bits [31:0])
//                Offset 0xBFFC: mtimeh    (Free-running Real-Time Counter, bits [63:32])
//
//              Generates timer_irq whenever mtime >= mtimecmp.
//              Generates software_irq whenever msip[0] == 1.
// ============================================================================

module clint (
    input  logic        clk,
    input  logic        rst_n,

    // Bus Interface
    input  logic        cs,
    input  logic        read_en,
    input  logic        write_en,
    input  logic [15:0] addr,         // Lower 16-bit address offset
    input  logic [31:0] write_data,
    output logic [31:0] read_data,

    // Interrupt Outputs to CPU / CSR File
    output logic        timer_irq,    // MTIP
    output logic        software_irq  // MSIP
);

    logic [31:0] msip;
    logic [63:0] mtimecmp;
    logic [63:0] mtime;

    // Interrupt generation per RISC-V Privileged Specification:
    // Timer interrupt is level-triggered HIGH whenever mtime >= mtimecmp
    assign timer_irq    = (mtime >= mtimecmp);
    assign software_irq = msip[0];

    // ========================================================================
    // Bus Read
    // ========================================================================
    always_comb begin
        if (cs && read_en) begin
            case (addr)
                16'h0000: read_data = msip;
                16'h4000: read_data = mtimecmp[31:0];
                16'h4004: read_data = mtimecmp[63:32];
                16'hBFF8: read_data = mtime[31:0];
                16'hBFFC: read_data = mtime[63:32];
                default:  read_data = 32'b0;
            endcase
        end else begin
            read_data = 32'b0;
        end
    end

    // ========================================================================
    // Synchronous Register Updates
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            msip     <= 32'b0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; // Start with max compare value
            mtime    <= 64'b0;
        end else begin
            // Free-running 64-bit real-time counter
            mtime <= mtime + 64'd1;

            if (cs && write_en) begin
                case (addr)
                    16'h0000: msip               <= {31'b0, write_data[0]};
                    16'h4000: mtimecmp[31:0]     <= write_data;
                    16'h4004: mtimecmp[63:32]    <= write_data;
                    16'hBFF8: mtime[31:0]        <= write_data;
                    16'hBFFC: mtime[63:32]       <= write_data;
                    default: ;
                endcase
            end
        end
    end

endmodule
