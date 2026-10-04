// ============================================================================
// File:        spark_soc_top.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Full Unified System-on-Chip (SoC) Integration.
//
//              Unifies:
//                1. 5-Stage Pipelined RV32I Processor Core (cpu_pipe)
//                2. Custom Instruction Decoder (custom_decoder) with PIM Hook
//                3. Processing-In-Memory (PIM) Subsystem (pim_top)
//                4. Software-Rendered VGA Controller & Framebuffer (vga_ctrl)
//                5. 16550 UART Serial Controller (uart)
//                6. Core Local Interruptor (clint)
//                7. Platform-Level Interrupt Controller (plic)
//                8. SoC 7-Port Bus Interconnect (bus_interconnect)
//                9. Boot ROM & Main RAM (128 MB space)
// ============================================================================

module spark_soc_top #(
    parameter logic [31:0] RESET_ADDR     = 32'h0000_0000,
    parameter int          MEM_DEPTH      = 2048,
    parameter string       INIT_FILE      = "sw/bootrom/bootrom.hex",
    parameter int          RAM_DEPTH      = 65536,
    parameter string       RAM_INIT_FILE  = "sw/xv6/kernel.hex",
    parameter string       DISK_INIT_FILE = "sw/xv6/fs.hex"
) (
    input  logic        clk,
    input  logic        pixel_clk,
    input  logic        rst_n,

    // Serial Communication
    output logic        uart_tx,
    input  logic        uart_rx,

    // Mouse / User Interface
    input  logic [9:0]  mouse_x,
    input  logic [8:0]  mouse_y,
    input  logic [2:0]  mouse_btn,

    // Video Output Interface
    output logic        vga_hsync,
    output logic        vga_vsync,
    output logic        vga_display_on,
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,

    // Debug / Observation Ports
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_wb_data,
    output logic        dbg_reg_write,
    output logic        pim_busy,
    output logic        pim_irq
);

    import riscv_pkg::*;

    // ========================================================================
    // Internal Bus & Memory Wires
    // ========================================================================
    logic [31:0] cpu_mem_addr;
    logic        cpu_mem_read;
    logic        cpu_mem_write;
    logic [31:0] cpu_mem_wdata;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] cpu_mem_rdata;
    /* verilator lint_on UNUSEDSIGNAL */

    // Peripheral Chip Selects
    logic cs_rom;
    logic cs_uart;
    logic cs_clint;
    logic cs_plic;
    logic cs_ram;
    logic cs_pim;
    logic cs_vga;
    logic cs_disk;

    // Peripheral Read Data
    logic [31:0] rdata_rom;
    logic [31:0] rdata_uart;
    logic [31:0] rdata_clint;
    logic [31:0] rdata_plic;
    logic [31:0] rdata_ram;
    logic [31:0] rdata_pim;
    logic [31:0] rdata_vga;
    logic [31:0] rdata_disk;
    logic [31:0] ram_instr_rdata;

    // Interrupts
    logic timer_irq;
    logic software_irq;
    logic uart_irq;
    logic external_irq;

    // Custom Instruction & PIM Interface
    logic        cpu_pim_valid;
    logic        cpu_pim_ready;
    pim_op_t     cpu_pim_op;
    logic [31:0] cpu_pim_rs1;
    logic [31:0] cpu_pim_rs2;
    logic [31:0] cpu_pim_rd;
    logic        cpu_pim_done;

    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] dbg_alu_result;
    logic        dbg_stall;
    logic        dbg_flush;
    logic [19:0] vga_pixel_addr;
    /* verilator lint_on UNUSEDSIGNAL */

    // ========================================================================
    // 1. Processor Core (5-Stage Pipelined RV32I)
    // ========================================================================
    // Privileged architecture wires
    /* verilator lint_off UNUSEDSIGNAL */
    logic [1:0]  cpu_priv_mode;
    logic [31:0] cpu_satp;
    /* verilator lint_on UNUSEDSIGNAL */

    cpu_pipe #(
        .RESET_ADDR(RESET_ADDR),
        .MEM_DEPTH(MEM_DEPTH),
        .INIT_FILE(INIT_FILE)
    ) u_cpu (
        .clk           (clk),
        .rst_n         (rst_n),
        .timer_irq     (timer_irq),
        .external_irq  (external_irq),
        .priv_mode_out  (cpu_priv_mode),
        .satp_out       (cpu_satp),
        .ext_mem_rdata  (cpu_mem_rdata),
        .ext_instr_rdata(ram_instr_rdata),
        .dbg_pc         (dbg_pc),
        .dbg_instr     (dbg_instr),
        .dbg_alu_result(dbg_alu_result),
        .dbg_wb_data   (dbg_wb_data),
        .dbg_reg_write (dbg_reg_write),
        .dbg_stall     (dbg_stall),
        .dbg_flush     (dbg_flush)
    );

    // Memory stage connections
    assign cpu_mem_addr  = u_cpu.alu_result_mem;
    assign cpu_mem_write = u_cpu.mem_write_mem;
    assign cpu_mem_read  = u_cpu.mem_read_mem;
    assign cpu_mem_wdata = u_cpu.write_data_mem;

    // ========================================================================
    // 2. Custom Instruction Decoder Hook (Decode Stage)
    // ========================================================================
    custom_decoder u_custom_decoder (
        .instr         (dbg_instr),
        .is_custom     (cpu_pim_valid),
        .pim_op        (cpu_pim_op),
        .pim_valid     (),
        .illegal_custom()
    );

    assign cpu_pim_rs1 = u_cpu.rs1_data_id;
    assign cpu_pim_rs2 = u_cpu.rs2_data_id;

    // ========================================================================
    // 3. Bus Interconnect
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
        .rdata_ram         (rdata_ram),

        .cs_pim            (cs_pim),
        .rdata_pim         (rdata_pim),

        .cs_vga            (cs_vga),
        .rdata_vga         (rdata_vga),

        .cs_disk           (cs_disk),
        .rdata_disk        (rdata_disk)
    );

    // ========================================================================
    // 4. Processing-In-Memory (PIM) Subsystem (0x3000_0000)
    // ========================================================================
    pim_top #(
        .BUFFER_LINES(64)
    ) u_pim (
        .clk          (clk),
        .rst_n        (rst_n),
        .cpu_cmd_valid(cpu_pim_valid),
        .cpu_cmd_ready(cpu_pim_ready),
        .cpu_cmd_op   (cpu_pim_op),
        .cpu_cmd_rs1  (cpu_pim_rs1),
        .cpu_cmd_rs2  (cpu_pim_rs2),
        .cpu_cmd_rd   (cpu_pim_rd),
        .cpu_cmd_done (cpu_pim_done),
        .bus_cs       (cs_pim),
        .bus_we       (cpu_mem_write),
        .bus_re       (cpu_mem_read),
        .bus_addr     (cpu_mem_addr),
        .bus_wdata    (cpu_mem_wdata),
        .bus_rdata    (rdata_pim),
        .pim_busy     (pim_busy),
        .pim_irq      (pim_irq)
    );

    // ========================================================================
    // 5. Software-Rendered Display Controller (0xF000_0000)
    // ========================================================================
    vga_ctrl #(
        .H_DISPLAY    (640),
        .H_FRONT_PORCH(16),
        .H_SYNC_PULSE (96),
        .H_BACK_PORCH (48),
        .H_TOTAL      (800),
        .V_DISPLAY    (480),
        .V_FRONT_PORCH(10),
        .V_SYNC_PULSE (2),
        .V_BACK_PORCH (33),
        .V_TOTAL      (525),
        .FB_WIDTH     (320),
        .FB_HEIGHT    (240),
        .FB_SIZE      (320 * 240)
    ) u_vga (
        .clk       (clk),
        .rst_n     (rst_n),
        .bus_cs    (cs_vga),
        .bus_we    (cpu_mem_write),
        .bus_re    (cpu_mem_read),
        .bus_addr  (cpu_mem_addr),
        .bus_wdata (cpu_mem_wdata),
        .bus_rdata (rdata_vga),
        .pixel_clk (pixel_clk),
        .hsync     (vga_hsync),
        .vsync     (vga_vsync),
        .display_on(vga_display_on),
        .vga_r     (vga_r),
        .vga_g     (vga_g),
        .vga_b     (vga_b),
        .pixel_addr(vga_pixel_addr)
    );

    // ========================================================================
    // 6. 16550 UART (0x1000_0000)
    // ========================================================================
    uart #(
        .CLKS_PER_BIT(16)
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
        .mouse_x    (mouse_x),
        .mouse_y    (mouse_y),
        .mouse_btn  (mouse_btn),
        .uart_irq   (uart_irq)
    );

    // ========================================================================
    // 7. CLINT (0x2000_0000)
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
    // 8. PLIC (0xC000_0000)
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
        .irq_sources  ({pim_irq, 1'b0, uart_irq}), // Source 3=PIM, Source 2=Reserved, Source 1=UART
        .external_irq (external_irq)
    );

    // ========================================================================
    // 9. Main System RAM (0x8000_0000 - 0x87FF_FFFF)
    // ========================================================================
    main_ram #(
        .DEPTH    (RAM_DEPTH),
        .INIT_FILE(RAM_INIT_FILE)
    ) u_ram (
        .clk        (clk),
        .rst_n      (rst_n),
        .bus_cs     (cs_ram),
        .bus_re     (cpu_mem_read),
        .bus_we     (cpu_mem_write),
        .bus_funct3 (u_cpu.funct3_mem),
        .bus_addr   (cpu_mem_addr),
        .bus_wdata  (cpu_mem_wdata),
        .bus_rdata  (rdata_ram),
        .instr_addr (dbg_pc),
        .instr_rdata(ram_instr_rdata)
    );

    // ========================================================================
    // 10. RAMDisk Storage Controller (0x4000_0000 - 0x4FFF_FFFF)
    // ========================================================================
    ramdisk #(
        .SECTOR_SIZE(512),
        .NUM_SECTORS(512),
        .INIT_FILE  (DISK_INIT_FILE)
    ) u_ramdisk (
        .clk       (clk),
        .rst_n     (rst_n),
        .cs        (cs_disk),
        .read_en   (cpu_mem_read),
        .write_en  (cpu_mem_write),
        .addr      (cpu_mem_addr),
        .write_data(cpu_mem_wdata),
        .read_data (rdata_disk)
    );

    // Unmapped memory response default
    assign rdata_rom = 32'b0;

endmodule
