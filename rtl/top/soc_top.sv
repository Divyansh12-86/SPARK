// ============================================================================
// File:        soc_top.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Top-Level System-on-Chip (SoC) Integration.
//
//              Integrates:
//                - SPARK 5-Stage Pipelined RV32I Processor Core (cpu_pipe)
//                - Bus Interconnect & Address Decoder (bus_interconnect)
//                - 16550 UART Controller (uart)
//                - Core Local Interruptor (clint)
//                - Platform-Level Interrupt Controller (plic)
//                - Instruction Memory / Boot ROM
//                - Data Memory / RAM
// ============================================================================

module soc_top #(
    parameter logic [31:0] RESET_ADDR = 32'h0000_0000,
    parameter int          MEM_DEPTH  = 1024,
    parameter string       INIT_FILE  = ""
) (
    input  logic clk,
    input  logic rst_n,

    // Serial Communication
    output logic uart_tx,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic uart_rx,
    /* verilator lint_on UNUSEDSIGNAL */

    // Debug / Observation Ports
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_wb_data,
    output logic        dbg_reg_write
);

    // ========================================================================
    // Internal Interconnect Wires
    // ========================================================================
    logic [31:0] cpu_mem_addr;
    logic        cpu_mem_read;
    logic        cpu_mem_write;
    logic [31:0] cpu_mem_wdata;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] cpu_mem_rdata;

    // Peripheral Chip Selects
    logic cs_rom;
    logic cs_uart;
    logic cs_clint;
    logic cs_plic;
    logic cs_ram;

    // Peripheral Read Data
    logic [31:0] rdata_rom;
    logic [31:0] rdata_uart;
    logic [31:0] rdata_clint;
    logic [31:0] rdata_plic;
    logic [31:0] rdata_ram;

    // Interrupt Lines
    logic timer_irq;
    logic software_irq;
    logic uart_irq;
    logic external_irq;

    // Dummy debug wires
    logic [31:0] dbg_alu_result;
    logic        dbg_stall;
    logic        dbg_flush;
    /* verilator lint_on UNUSEDSIGNAL */

    // ========================================================================
    // 1. Processor Core
    // ========================================================================
    cpu_pipe #(
        .RESET_ADDR(RESET_ADDR),
        .MEM_DEPTH(MEM_DEPTH),
        .INIT_FILE(INIT_FILE)
    ) u_cpu (
        .clk           (clk),
        .rst_n         (rst_n),
        .dbg_pc        (dbg_pc),
        .dbg_instr     (dbg_instr),
        .dbg_alu_result(dbg_alu_result),
        .dbg_wb_data   (dbg_wb_data),
        .dbg_reg_write (dbg_reg_write),
        .dbg_stall     (dbg_stall),
        .dbg_flush     (dbg_flush)
    );

    // Tap memory bus from CPU Memory stage (aligned across all bus controls)
    assign cpu_mem_addr  = u_cpu.alu_result_mem;
    assign cpu_mem_write = u_cpu.mem_write_mem;
    assign cpu_mem_read  = u_cpu.mem_read_mem;
    assign cpu_mem_wdata = u_cpu.write_data_mem;

    // ========================================================================
    // 2. Bus Interconnect
    // ========================================================================
    bus_interconnect u_bus (
        .master_addr       (cpu_mem_addr),
        .master_read_en    (cpu_mem_read),
        .master_write_en   (cpu_mem_write),
        .master_write_data (cpu_mem_wdata),
        .master_read_data  (cpu_mem_rdata),

        .cs_rom            (cs_rom),
        .rdata_rom         (rdata_rom),

        .cs_uart           (cs_uart),
        .rdata_uart        (rdata_uart),

        .cs_clint          (cs_clint),
        .rdata_clint       (rdata_clint),

        .cs_plic           (cs_plic),
        .rdata_plic        (rdata_plic),

        .cs_ram            (cs_ram),
        .rdata_ram         (rdata_ram)
    );

    // ========================================================================
    // 3. 16550 UART (0x1000_0000)
    // ========================================================================
    uart #(
        .CLKS_PER_BIT(16) // Fast simulation rate
    ) u_uart (
        .clk        (clk),
        .rst_n      (rst_n),
        .cs         (cs_uart),
        .read_en    (cpu_mem_read),
        .write_en   (cpu_mem_write),
        .addr       (cpu_mem_addr[2:0]),
        .write_data (cpu_mem_wdata),
        .read_data  (rdata_uart),
        .tx         (uart_tx),
        .rx         (uart_rx),
        .uart_irq   (uart_irq)
    );

    // ========================================================================
    // 4. CLINT (0x2000_0000)
    // ========================================================================
    clint u_clint (
        .clk          (clk),
        .rst_n        (rst_n),
        .cs           (cs_clint),
        .read_en      (cpu_mem_read),
        .write_en     (cpu_mem_write),
        .addr         (cpu_mem_addr[15:0]),
        .write_data   (cpu_mem_wdata),
        .read_data    (rdata_clint),
        .timer_irq    (timer_irq),
        .software_irq (software_irq)
    );

    // ========================================================================
    // 5. PLIC (0xC000_0000)
    // ========================================================================
    plic #(
        .NUM_SOURCES(4)
    ) u_plic (
        .clk          (clk),
        .rst_n        (rst_n),
        .cs           (cs_plic),
        .read_en      (cpu_mem_read),
        .write_en     (cpu_mem_write),
        .addr         (cpu_mem_addr[23:0]),
        .write_data   (cpu_mem_wdata),
        .read_data    (rdata_plic),
        .irq_sources  ({2'b00, uart_irq}), // Source 1 = UART
        .external_irq (external_irq)
    );

    // Default tie-offs for unmapped memory responses
    assign rdata_rom = 32'b0;
    assign rdata_ram = 32'b0;

endmodule
