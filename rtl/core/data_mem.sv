// ============================================================================
// File:        data_mem.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Data Memory with byte, halfword, and word access for RV32I.
//
//              Single-cycle Harvard architecture data memory.
//              Combinational read: outputs read_data combinationally when mem_read=1.
//              Synchronous write: writes on rising clock edge when mem_write=1.
//              Supports LB, LH, LW, LBU, LHU (Loads) and SB, SH, SW (Stores).
// ============================================================================

module data_mem #(
    parameter int DEPTH = 1024  // Number of 32-bit words (4 KB)
) (
    input  logic        clk,
    input  logic        mem_read,
    input  logic        mem_write,
    input  logic [2:0]  funct3,      // Specifies access size (byte, half, word, signed/unsigned)
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,        // Byte address
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] write_data,  // Data to store
    output logic [31:0] read_data    // Loaded data out
);

    localparam int ADDR_BITS = $clog2(DEPTH);

    // 4 byte lanes per word for precise byte-level writing
    logic [7:0] mem [0:DEPTH-1][0:3];

    wire [ADDR_BITS-1:0] word_addr   = addr[ADDR_BITS+1:2];
    wire [1:0]           byte_offset = addr[1:0];
    wire                 half_offset = addr[1];

    // ------------------------------------------------------------------------
    // Synchronous Writes (SB, SH, SW)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB - Store Byte
                    mem[word_addr][byte_offset] <= write_data[7:0];
                end
                3'b001: begin // SH - Store Halfword (16 bits)
                    mem[word_addr][{half_offset, 1'b0}] <= write_data[7:0];
                    mem[word_addr][{half_offset, 1'b1}] <= write_data[15:8];
                end
                3'b010: begin // SW - Store Word (32 bits)
                    mem[word_addr][0] <= write_data[7:0];
                    mem[word_addr][1] <= write_data[15:8];
                    mem[word_addr][2] <= write_data[23:16];
                    mem[word_addr][3] <= write_data[31:24];
                end
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Combinational Reads (LB, LH, LW, LBU, LHU)
    // ------------------------------------------------------------------------
    logic [7:0]  read_byte;
    logic [15:0] read_half;
    logic [31:0] read_word;

    always_comb begin
        read_byte = mem[word_addr][byte_offset];
        read_half = half_offset ? {mem[word_addr][3], mem[word_addr][2]}
                                : {mem[word_addr][1], mem[word_addr][0]};
        read_word = {mem[word_addr][3], mem[word_addr][2], mem[word_addr][1], mem[word_addr][0]};

        if (mem_read) begin
            case (funct3)
                3'b000:  read_data = {{24{read_byte[7]}}, read_byte}; // LB  (signed byte)
                3'b001:  read_data = {{16{read_half[15]}}, read_half}; // LH  (signed halfword)
                3'b010:  read_data = read_word;                       // LW  (word)
                3'b100:  read_data = {24'b0, read_byte};              // LBU (unsigned byte)
                3'b101:  read_data = {16'b0, read_half};              // LHU (unsigned halfword)
                default: read_data = 32'b0;
            endcase
        end else begin
            read_data = 32'b0;
        end
    end

endmodule
