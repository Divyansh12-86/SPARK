// ============================================================================
// File:        tb_bus_interconnect.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for SoC Bus Interconnect and Address Decoder.
// ============================================================================

`timescale 1ns / 1ps

module tb_bus_interconnect;

    logic [31:0] master_addr;
    logic        master_read_en;
    logic        master_write_en;
    logic [31:0] master_write_data;
    logic [31:0] master_read_data;

    logic        cs_rom;
    logic [31:0] rdata_rom;

    logic        cs_uart;
    logic [31:0] rdata_uart;

    logic        cs_clint;
    logic [31:0] rdata_clint;

    logic        cs_plic;
    logic [31:0] rdata_plic;

    logic        cs_ram;
    logic [31:0] rdata_ram;

    integer pass_count;
    integer fail_count;
    integer test_num;

    bus_interconnect dut (
        .master_addr       (master_addr),
        .master_read_en    (master_read_en),
        .master_write_en   (master_write_en),
        .master_write_data (master_write_data),
        .master_read_data  (master_read_data),

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

    task check_decode(
        input string test_name,
        input logic  exp_rom,
        input logic  exp_uart,
        input logic  exp_clint,
        input logic  exp_plic,
        input logic  exp_ram,
        input logic [31:0] exp_rdata
    );
        test_num++;
        if (cs_rom !== exp_rom || cs_uart !== exp_uart ||
            cs_clint !== exp_clint || cs_plic !== exp_plic ||
            cs_ram !== exp_ram || master_read_data !== exp_rdata) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         ROM=%0b UART=%0b CLINT=%0b PLIC=%0b RAM=%0b RData=0x%08h",
                     cs_rom, cs_uart, cs_clint, cs_plic, cs_ram, master_read_data);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s (RData=0x%08h)", test_num, test_name, master_read_data);
            pass_count++;
        end
    endtask

    initial begin
        pass_count        = 0;
        fail_count        = 0;
        test_num          = 0;

        master_addr       = 32'b0;
        master_read_en    = 1'b1;
        master_write_en   = 1'b0;
        master_write_data = 32'b0;

        rdata_rom         = 32'hAAAA_0000;
        rdata_uart        = 32'hBBBB_1111;
        rdata_clint       = 32'hCCCC_2222;
        rdata_ram         = 32'hDDDD_8888;
        rdata_plic        = 32'hEEEE_CCCC;

        $display("");
        $display("==========================================================");
        $display("  SPARK Bus Interconnect Address Decode Testbench");
        $display("==========================================================");

        // 1. Boot ROM (0x0000_0000)
        master_addr = 32'h0000_0000;
        #5;
        check_decode("Address 0x00000000 maps to Boot ROM", 1, 0, 0, 0, 0, 32'hAAAA_0000);

        // 2. UART (0x1000_0000)
        master_addr = 32'h1000_0000;
        #5;
        check_decode("Address 0x10000000 maps to UART", 0, 1, 0, 0, 0, 32'hBBBB_1111);

        // 3. CLINT (0x2000_0000)
        master_addr = 32'h2000_0000;
        #5;
        check_decode("Address 0x20000000 maps to CLINT", 0, 0, 1, 0, 0, 32'hCCCC_2222);

        // 4. Main RAM (0x8000_0000)
        master_addr = 32'h8000_0000;
        #5;
        check_decode("Address 0x80000000 maps to Main RAM", 0, 0, 0, 0, 1, 32'hDDDD_8888);

        // 5. PLIC (0xC000_0000)
        master_addr = 32'hC000_0000;
        #5;
        check_decode("Address 0xC0000000 maps to PLIC", 0, 0, 0, 1, 0, 32'hEEEE_CCCC);

        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) $display("  STATUS:  ALL TESTS PASSED");
        else $display("  STATUS:  %0d TEST(S) FAILED", fail_count);
        $display("==========================================================");
        $finish;
    end

endmodule
