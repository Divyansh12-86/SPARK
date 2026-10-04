// ============================================================================
// File:        ramdisk.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Memory-Mapped Block Storage Device / RAMDisk Controller.
//              Provides high-speed persistent root filesystem storage for xv6.
//              Base Address: 0x4000_0000
//              Capacity:     Up to 2 MB (4096 blocks of 512 bytes each)
// ============================================================================


module ramdisk #(
    parameter int    SECTOR_SIZE = 512,
    parameter int    NUM_SECTORS = 512, // 256 KB default filesystem
    parameter string INIT_FILE   = ""
) (
    input  logic        clk,
    input  logic        rst_n,

    // Bus Interconnect Interface
    input  logic        cs,
    input  logic        read_en,
    input  logic        write_en,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);

    localparam int TOTAL_WORDS = (SECTOR_SIZE * NUM_SECTORS) / 4;
    localparam int ADDR_BITS   = $clog2(TOTAL_WORDS);

    // Storage memory array (word-addressable)
    logic [31:0] disk_mem [0:TOTAL_WORDS-1];

    wire [ADDR_BITS-1:0] word_idx = addr[ADDR_BITS+1:2];

    // Preload filesystem image if provided
    initial begin
        for (int i = 0; i < TOTAL_WORDS; i++) begin
            disk_mem[i] = 32'b0;
        end

        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, disk_mem);
        end
    end

    // Synchronous Write
    always @(posedge clk) begin
        if (cs && write_en) begin
            disk_mem[word_idx] <= write_data;
        end
    end

    // Combinational Read
    always_comb begin
        if (cs && read_en) begin
            read_data = disk_mem[word_idx];
        end else begin
            read_data = 32'b0;
        end
    end

endmodule
