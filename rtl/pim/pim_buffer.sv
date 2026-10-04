// ============================================================================
// File:        pim_buffer.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Dual-Ported 256-bit Wide Near-Memory Scratchpad SRAM Buffer.
//
//              Capacity: 64 lines x 256 bits = 2048 Bytes (2 KB).
//              Can hold 512 single-precision 32-bit words / integers.
//
//              Port A: 256-bit SIMD Execution Port (Single-cycle read/write)
//                - Reads 8 parallel 32-bit elements simultaneously in 1 cycle
//                - Writes 8 parallel 32-bit results back into buffer in 1 cycle
//
//              Port B: Refill/Writeback Memory/Bus Port
//                - 32-bit word access (addressable per 32-bit word) or 256-bit wide
//                - Supports concurrent read/write with Port A
// ============================================================================

module pim_buffer
#(
    parameter int DEPTH = 64,          // 64 lines = 2KB
    parameter int ADDR_WIDTH = 6       // $clog2(64) = 6
) (
    input  logic                     clk,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic                     rst_n,
    /* verilator lint_on UNUSEDSIGNAL */

    // ------------------------------------------------------------------------
    // Port A: SIMD Compute Engine Interface (256-bit wide)
    // ------------------------------------------------------------------------
    input  logic                     porta_en,
    input  logic                     porta_we,
    input  logic [ADDR_WIDTH-1:0]    porta_addr,
    input  logic [7:0][31:0]         porta_wdata,
    output logic [7:0][31:0]         porta_rdata,

    // ------------------------------------------------------------------------
    // Port B: SoC Bus / DMA / Refill Interface (32-bit word interface)
    //         Address format: [ADDR_WIDTH-1:0] line_addr, [2:0] word_idx
    // ------------------------------------------------------------------------
    input  logic                     portb_en,
    input  logic                     portb_we,
    input  logic [ADDR_WIDTH+2:0]    portb_addr, // 6 bits line + 3 bits word = 9 bits
    input  logic [31:0]              portb_wdata,
    output logic [31:0]              portb_rdata
);

    // 64 entries of 8x 32-bit words
    logic [7:0][31:0] mem [DEPTH-1:0];

    // ------------------------------------------------------------------------
    // Port A synchronous read and write
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (porta_en) begin
            if (porta_we) begin
                mem[porta_addr] <= porta_wdata;
                porta_rdata     <= porta_wdata;
            end else begin
                porta_rdata     <= mem[porta_addr];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Port B synchronous read and write (32-bit word level)
    // ------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] portb_line = portb_addr[ADDR_WIDTH+2:3];
    wire [2:0]            portb_word = portb_addr[2:0];

    always_ff @(posedge clk) begin
        if (portb_en) begin
            if (portb_we) begin
                mem[portb_line][portb_word] <= portb_wdata;
                portb_rdata                 <= portb_wdata;
            end else begin
                portb_rdata                 <= mem[portb_line][portb_word];
            end
        end
    end

endmodule
