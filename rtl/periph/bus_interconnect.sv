// ============================================================================
// File:        bus_interconnect.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: SoC Bus Interconnect and Address Decoder.
//
//              Decodes master physical addresses per the SPARK Memory Map:
//                0x0000_0000 - 0x0FFF_FFFF: Boot ROM (Instruction ROM)
//                0x1000_0000 - 0x10FF_FFFF: 16550 UART
//                0x2000_0000 - 0x20FF_FFFF: CLINT (Core Local Interruptor)
//                0x3000_0000 - 0x30FF_FFFF: PIM Subsystem (Phase 6/8)
//                0x8000_0000 - 0x87FF_FFFF: Main RAM (128 MB)
//                0xC000_0000 - 0xCFFF_FFFF: PLIC (Platform-Level Interrupt Controller)
//                0xF000_0000 - 0xF001_FFFF: VGA Display Framebuffer (Phase 7/8)
//
//              Routes memory requests to peripherals and multiplexes read data.
// ============================================================================

module bus_interconnect (
    // Master Port (from CPU)
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] master_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        master_read_en,
    input  logic        master_write_en,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] master_write_data,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] master_read_data,

    // Slave 0: Boot ROM
    output logic        cs_rom,
    input  logic [31:0] rdata_rom,

    // Slave 1: UART (0x1000_0000)
    output logic        cs_uart,
    input  logic [31:0] rdata_uart,

    // Slave 2: CLINT (0x2000_0000)
    output logic        cs_clint,
    input  logic [31:0] rdata_clint,

    // Slave 3: PLIC (0xC000_0000)
    output logic        cs_plic,
    input  logic [31:0] rdata_plic,

    // Slave 4: Main RAM (0x8000_0000)
    output logic        cs_ram,
    input  logic [31:0] rdata_ram,

    // Slave 5: PIM Subsystem (0x3000_0000)
    output logic        cs_pim,
    input  logic [31:0] rdata_pim,

    // Slave 6: VGA Display Controller (0xF000_0000)
    output logic        cs_vga,
    input  logic [31:0] rdata_vga,

    // Slave 7: RAMDisk Block Storage (0x4000_0000)
    output logic        cs_disk,
    input  logic [31:0] rdata_disk
);

    // ------------------------------------------------------------------------
    // Address Decoding
    // ------------------------------------------------------------------------
    always_comb begin
        cs_rom   = 1'b0;
        cs_uart  = 1'b0;
        cs_clint = 1'b0;
        cs_plic  = 1'b0;
        cs_ram   = 1'b0;
        cs_pim   = 1'b0;
        cs_vga   = 1'b0;
        cs_disk  = 1'b0;

        if (master_addr[31:28] == 4'h0) begin
            // 0x0000_0000 - 0x0FFF_FFFF: Boot ROM
            cs_rom = master_read_en || master_write_en;
        end else if (master_addr[31:24] == 8'h10) begin
            // 0x1000_0000 - 0x10FF_FFFF: UART
            cs_uart = master_read_en || master_write_en;
        end else if (master_addr[31:24] == 8'h20) begin
            // 0x2000_0000 - 0x20FF_FFFF: CLINT
            cs_clint = master_read_en || master_write_en;
        end else if (master_addr[31:24] == 8'h30) begin
            // 0x3000_0000 - 0x30FF_FFFF: PIM
            cs_pim = master_read_en || master_write_en;
        end else if (master_addr[31:28] == 4'h4) begin
            // 0x4000_0000 - 0x4FFF_FFFF: RAMDisk Block Storage
            cs_disk = master_read_en || master_write_en;
        end else if (master_addr[31:28] == 4'h8) begin
            // 0x8000_0000 - 0x8FFF_FFFF: Main RAM
            cs_ram = master_read_en || master_write_en;
        end else if (master_addr[31:28] == 4'hC) begin
            // 0xC000_0000 - 0xCFFF_FFFF: PLIC
            cs_plic = master_read_en || master_write_en;
        end else if (master_addr[31:28] == 4'hF) begin
            // 0xF000_0000 - 0xFFFF_FFFF: Framebuffer Display
            cs_vga = master_read_en || master_write_en;
        end
    end

    // ------------------------------------------------------------------------
    // Read Data Multiplexing
    // ------------------------------------------------------------------------
    always_comb begin
        if (cs_uart)        master_read_data = rdata_uart;
        else if (cs_clint)  master_read_data = rdata_clint;
        else if (cs_pim)    master_read_data = rdata_pim;
        else if (cs_disk)   master_read_data = rdata_disk;
        else if (cs_plic)   master_read_data = rdata_plic;
        else if (cs_ram)    master_read_data = rdata_ram;
        else if (cs_vga)    master_read_data = rdata_vga;
        else if (cs_rom)    master_read_data = rdata_rom;
        else                master_read_data = 32'b0;
    end

endmodule
