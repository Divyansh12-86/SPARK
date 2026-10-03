// ============================================================================
// File:        main_ram.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Main System RAM Subsystem (Mapped at 0x8000_0000).
//              Provides dual-ported access:
//                - Port A: Data Memory access via SoC Bus (Loads/Stores)
//                - Port B: Instruction Fetch access (Kernel code execution)
//              Supports sub-word writes (SB, SH, SW) and pre-loading kernel images.
// ============================================================================


module main_ram #(
    parameter int    DEPTH     = 65536, // 64K words = 256 KB RAM default
    parameter string INIT_FILE = ""
) (
    input  logic        clk,
    input  logic        rst_n,

    // ------------------------------------------------------------------------
    // Port A: Bus Slave Interface (CPU Data Loads / Stores)
    // ------------------------------------------------------------------------
    input  logic        bus_cs,
    input  logic        bus_re,
    input  logic        bus_we,
    input  logic [2:0]  bus_funct3,      // SB, SH, SW, LB, LH, LW, LBU, LHU
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] bus_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] bus_wdata,
    output logic [31:0] bus_rdata,

    // ------------------------------------------------------------------------
    // Port B: Direct Instruction Fetch Interface (CPU IF Stage)
    // ------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] instr_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] instr_rdata
);

    localparam int ADDR_BITS = $clog2(DEPTH);

    // 4 byte lanes per word for precise byte/halfword writes
    logic [7:0] ram [0:DEPTH-1][0:3];

    wire [ADDR_BITS-1:0] data_word_idx = bus_addr[ADDR_BITS+1:2];
    wire [1:0]           byte_offset   = bus_addr[1:0];
    wire                 half_offset   = bus_addr[1];

    wire [ADDR_BITS-1:0] instr_word_idx = instr_addr[ADDR_BITS+1:2];

    // Preload kernel image if specified
    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            ram[i][0] = 8'h13; // NOP (addi x0, x0, 0 = 0x00000013)
            ram[i][1] = 8'h00;
            ram[i][2] = 8'h00;
            ram[i][3] = 8'h00;
        end

        if (INIT_FILE != "") begin
            // Temporary 32-bit buffer for loading 32-bit hex words
            logic [31:0] temp_mem [0:DEPTH-1];
            $readmemh(INIT_FILE, temp_mem);
            for (int i = 0; i < DEPTH; i++) begin
                ram[i][0] = temp_mem[i][7:0];
                ram[i][1] = temp_mem[i][15:8];
                ram[i][2] = temp_mem[i][23:16];
                ram[i][3] = temp_mem[i][31:24];
            end
        end
    end

    // ------------------------------------------------------------------------
    // Port A: Synchronous Writes
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (bus_cs && bus_we) begin
            case (bus_funct3)
                3'b000: begin // SB - Store Byte
                    ram[data_word_idx][byte_offset] <= bus_wdata[7:0];
                end
                3'b001: begin // SH - Store Halfword
                    ram[data_word_idx][{half_offset, 1'b0}] <= bus_wdata[7:0];
                    ram[data_word_idx][{half_offset, 1'b1}] <= bus_wdata[15:8];
                end
                3'b010: begin // SW - Store Word
                    ram[data_word_idx][0] <= bus_wdata[7:0];
                    ram[data_word_idx][1] <= bus_wdata[15:8];
                    ram[data_word_idx][2] <= bus_wdata[23:16];
                    ram[data_word_idx][3] <= bus_wdata[31:24];
                end
                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Port A: Combinational Reads (LB, LH, LW, LBU, LHU)
    // ------------------------------------------------------------------------
    logic [7:0]  read_byte;
    logic [15:0] read_half;
    logic [31:0] read_word;

    always_comb begin
        read_byte = ram[data_word_idx][byte_offset];
        read_half = half_offset ? {ram[data_word_idx][3], ram[data_word_idx][2]}
                                : {ram[data_word_idx][1], ram[data_word_idx][0]};
        read_word = {ram[data_word_idx][3], ram[data_word_idx][2], ram[data_word_idx][1], ram[data_word_idx][0]};

        if (bus_cs && bus_re) begin
            case (bus_funct3)
                3'b000:  bus_rdata = {{24{read_byte[7]}}, read_byte}; // LB
                3'b001:  bus_rdata = {{16{read_half[15]}}, read_half}; // LH
                3'b010:  bus_rdata = read_word;                       // LW
                3'b100:  bus_rdata = {24'b0, read_byte};              // LBU
                3'b101:  bus_rdata = {16'b0, read_half};              // LHU
                default: bus_rdata = read_word;
            endcase
        end else begin
            bus_rdata = 32'b0;
        end
    end

    // ------------------------------------------------------------------------
    // Port B: Instruction Fetch Combinational Read
    // ------------------------------------------------------------------------
    assign instr_rdata = {ram[instr_word_idx][3],
                          ram[instr_word_idx][2],
                          ram[instr_word_idx][1],
                          ram[instr_word_idx][0]};

endmodule
