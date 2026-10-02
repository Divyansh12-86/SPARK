// ============================================================================
// File:        instr_mem.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Instruction Memory (ROM / RAM) for RV32I.
//
//              Single-cycle Harvard architecture instruction memory.
//              Pure combinational read: given word address addr[31:2], outputs
//              the 32-bit instruction word instantaneously within the clock cycle.
//              Supports pre-loading compiled binary hex files via $readmemh.
// ============================================================================

module instr_mem #(
    parameter int          DEPTH     = 1024,  // Number of 32-bit words (4 KB)
    parameter string       INIT_FILE = ""     // Optional hex file path for $readmemh
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,                 // Byte address from PC
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] instr                 // 32-bit instruction word out
);

    // 32-bit word array
    logic [31:0] mem [0:DEPTH-1];

    // Optional pre-load via hex file
    initial begin
        // Clear memory to NOP (addi x0, x0, 0 = 32'h00000013)
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = 32'h0000_0013;
        end

        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // Word-aligned access: addr[31:2] is word address.
    // We mask to the DEPTH-1 range using $clog2(DEPTH) bits.
    localparam int ADDR_BITS = $clog2(DEPTH);
    wire [ADDR_BITS-1:0] word_addr = addr[ADDR_BITS+1:2];

    assign instr = mem[word_addr];

endmodule
