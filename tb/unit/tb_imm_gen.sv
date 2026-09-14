// ============================================================================
// File:        tb_imm_gen.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Self-checking testbench for the RV32I Immediate Generator.
//
//              Tests all 6 instruction formats (I, S, B, U, J, R) with both
//              positive and negative immediates to verify sign extension.
//              Each test uses a hand-assembled 32-bit instruction word with
//              known bit patterns.
// ============================================================================

`timescale 1ns / 1ps

module tb_imm_gen;

    logic [31:0] tb_instr;
    logic [31:0] tb_imm;

    integer pass_count;
    integer fail_count;
    integer test_num;

    imm_gen dut (
        .instr (tb_instr),
        .imm   (tb_imm)
    );

    task check(
        input string       test_name,
        input logic [31:0] expected
    );
        test_num++;
        if (tb_imm !== expected) begin
            $display("  [FAIL] Test %0d: %s", test_num, test_name);
            $display("         instr    = 0x%08h", tb_instr);
            $display("         Expected = 0x%08h", expected);
            $display("         Actual   = 0x%08h", tb_imm);
            fail_count++;
        end else begin
            $display("  [PASS] Test %0d: %s", test_num, test_name);
            pass_count++;
        end
    endtask

    task apply_and_check(
        input logic [31:0] instr_val,
        input string       test_name,
        input logic [31:0] expected
    );
        tb_instr = instr_val;
        #10;
        check(test_name, expected);
    endtask

    initial begin
        $dumpfile("imm_gen_tb.vcd");
        $dumpvars(0, tb_imm_gen);

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        $display("");
        $display("==========================================================");
        $display("  SPARK Immediate Generator Testbench");
        $display("==========================================================");

        // ================================================================
        // I-type Tests (opcode = 0010011 for ALU-immediate)
        // Format: [31:20]=imm[11:0] [19:15]=rs1 [14:12]=funct3 [11:7]=rd [6:0]=opcode
        // ================================================================
        $display("");
        $display("--- I-type (ALU Immediate) ---");

        // ADDI x1, x0, 5  =>  imm=5, rs1=0, funct3=000, rd=1, opcode=0010011
        // instr[31:20] = 000000000101 = 5
        // Full: 000000000101_00000_000_00001_0010011
        apply_and_check(32'b000000000101_00000_000_00001_0010011,
                        "I-type: ADDI x1,x0,5 => imm=5",
                        32'd5);

        // ADDI x1, x0, -1  =>  imm=0xFFF = -1 (12-bit signed)
        // instr[31:20] = 111111111111
        // Sign-extend bit 31 (=1) across [31:12] => 0xFFFFFFFF
        apply_and_check(32'b111111111111_00000_000_00001_0010011,
                        "I-type: ADDI x1,x0,-1 => imm=0xFFFFFFFF",
                        32'hFFFF_FFFF);

        // ADDI with imm = 0x7FF (max positive 12-bit = 2047)
        apply_and_check(32'b011111111111_00000_000_00001_0010011,
                        "I-type: imm=0x7FF (2047, max positive 12-bit)",
                        32'h0000_07FF);

        // ADDI with imm = 0x800 (-2048, most negative 12-bit)
        apply_and_check(32'b100000000000_00000_000_00001_0010011,
                        "I-type: imm=0x800 (-2048, sign-extended)",
                        32'hFFFF_F800);

        // ================================================================
        // I-type Load (opcode = 0000011)
        // ================================================================
        $display("");
        $display("--- I-type (Load) ---");

        // LW x2, 16(x3)  =>  imm=16
        apply_and_check(32'b000000010000_00011_010_00010_0000011,
                        "I-type Load: LW x2,16(x3) => imm=16",
                        32'd16);

        // LW with negative offset: -4
        apply_and_check(32'b111111111100_00011_010_00010_0000011,
                        "I-type Load: LW x2,-4(x3) => imm=0xFFFFFFFC",
                        32'hFFFF_FFFC);

        // ================================================================
        // S-type Tests (opcode = 0100011)
        // Format: [31:25]=imm[11:5] [24:20]=rs2 [19:15]=rs1 [14:12]=funct3 [11:7]=imm[4:0] [6:0]=opcode
        // ================================================================
        $display("");
        $display("--- S-type (Store) ---");

        // SW x2, 32(x3)  =>  imm=32=0x20
        // imm[11:5] = 0000001, imm[4:0] = 00000
        // Full: 0000001_00010_00011_010_00000_0100011
        apply_and_check(32'b0000001_00010_00011_010_00000_0100011,
                        "S-type: SW x2,32(x3) => imm=32",
                        32'd32);

        // SW with negative offset: -8 = 0xFFFFFFF8
        // -8 in 12 bits = 111111111000
        // imm[11:5] = 1111111, imm[4:0] = 11000
        apply_and_check(32'b1111111_00010_00011_010_11000_0100011,
                        "S-type: SW x2,-8(x3) => imm=0xFFFFFFF8",
                        32'hFFFF_FFF8);

        // SW with imm=0x7FF (max positive)
        // imm[11:5]=0111111, imm[4:0]=11111
        apply_and_check(32'b0111111_00010_00011_010_11111_0100011,
                        "S-type: imm=0x7FF (max positive 12-bit)",
                        32'h0000_07FF);

        // ================================================================
        // B-type Tests (opcode = 1100011)
        // Format: [31]=imm[12] [30:25]=imm[10:5] [24:20]=rs2 [19:15]=rs1
        //         [14:12]=funct3 [11:8]=imm[4:1] [7]=imm[11] [6:0]=opcode
        // Note: imm[0] is always 0 (2-byte aligned branch targets)
        // ================================================================
        $display("");
        $display("--- B-type (Branch) ---");

        // BEQ x1, x2, +8
        // imm = 8 = 0b0_0000000_1000_0 (13 bits, bit 0 always 0)
        // imm[12]=0, imm[11]=0, imm[10:5]=000000, imm[4:1]=0100
        // [31]=0 [30:25]=000000 [24:20]=rs2 [19:15]=rs1 [14:12]=000 [11:8]=0100 [7]=0 [6:0]=1100011
        apply_and_check(32'b0_000000_00010_00001_000_0100_0_1100011,
                        "B-type: BEQ x1,x2,+8 => imm=8",
                        32'd8);

        // BEQ x1, x2, -8
        // imm = -8 = 0xFFFFFFF8 (13-bit signed, bit 0 = 0)
        // -8 in 13 bits = 1_1111111_1000_0
        // imm[12]=1, imm[11]=1, imm[10:5]=111111, imm[4:1]=1100
        apply_and_check(32'b1_111111_00010_00001_000_1100_1_1100011,
                        "B-type: BEQ x1,x2,-8 => imm=0xFFFFFFF8",
                        32'hFFFF_FFF8);

        // BEQ with large positive offset: +4094 (max B-type positive)
        // 4094 = 0b0_1111111_1111_0
        // imm[12]=0, imm[11]=1, imm[10:5]=111111, imm[4:1]=1111
        apply_and_check(32'b0_111111_00010_00001_000_1111_1_1100011,
                        "B-type: +4094 (max positive branch offset)",
                        32'h0000_0FFE);

        // ================================================================
        // U-type Tests (opcode = 0110111 for LUI)
        // Format: [31:12]=imm[31:12] [11:7]=rd [6:0]=opcode
        // ================================================================
        $display("");
        $display("--- U-type (LUI/AUIPC) ---");

        // LUI x1, 0xDEADB  =>  imm = 0xDEADB000
        apply_and_check(32'b11011110101011011011_00001_0110111,
                        "U-type: LUI x1,0xDEADB => imm=0xDEADB000",
                        32'hDEAD_B000);

        // LUI x1, 0x00001  =>  imm = 0x00001000
        apply_and_check(32'b00000000000000000001_00001_0110111,
                        "U-type: LUI x1,0x00001 => imm=0x00001000",
                        32'h0000_1000);

        // AUIPC x1, 0xFFFFF  =>  imm = 0xFFFFF000
        apply_and_check(32'b11111111111111111111_00001_0010111,
                        "U-type: AUIPC x1,0xFFFFF => imm=0xFFFFF000",
                        32'hFFFF_F000);

        // ================================================================
        // J-type Tests (opcode = 1101111 for JAL)
        // Format: [31]=imm[20] [30:21]=imm[10:1] [20]=imm[11]
        //         [19:12]=imm[19:12] [11:7]=rd [6:0]=opcode
        // Note: imm[0] is always 0 (2-byte aligned)
        // ================================================================
        $display("");
        $display("--- J-type (JAL) ---");

        // JAL x1, +8
        // imm = 8 = 0b0_00000000_0_0000000100_0 (21 bits, bit 0 = 0)
        // imm[20]=0, imm[19:12]=00000000, imm[11]=0, imm[10:1]=0000000100
        apply_and_check(32'b0_0000000100_0_00000000_00001_1101111,
                        "J-type: JAL x1,+8 => imm=8",
                        32'd8);

        // JAL x1, -4
        // imm = -4 = 0xFFFFFFFC (21-bit signed, bit 0 = 0)
        // -4 in 21 bits: 1_11111111_1_1111111110_0
        // imm[20]=1, imm[19:12]=11111111, imm[11]=1, imm[10:1]=1111111110
        apply_and_check(32'b1_1111111110_1_11111111_00001_1101111,
                        "J-type: JAL x1,-4 => imm=0xFFFFFFFC",
                        32'hFFFF_FFFC);

        // JAL with large positive: +1048574 (max positive J-type = 2^20 - 2)
        // 1048574 = 0b0_11111111_1_1111111111_0
        apply_and_check(32'b0_1111111111_1_11111111_00001_1101111,
                        "J-type: +1048574 (max positive jump offset)",
                        32'h000F_FFFE);

        // ================================================================
        // R-type (opcode = 0110011) — No immediate, output must be 0
        // ================================================================
        $display("");
        $display("--- R-type (no immediate) ---");

        // ADD x1, x2, x3
        apply_and_check(32'b0000000_00011_00010_000_00001_0110011,
                        "R-type: ADD x1,x2,x3 => imm=0 (no immediate)",
                        32'd0);

        // ================================================================
        // Summary
        // ================================================================
        $display("");
        $display("==========================================================");
        $display("  RESULTS: %0d / %0d tests passed", pass_count, pass_count + fail_count);

        if (fail_count == 0)
            $display("  STATUS:  ALL TESTS PASSED");
        else
            $display("  STATUS:  %0d TEST(S) FAILED", fail_count);

        $display("==========================================================");
        $display("");

        $finish;
    end

endmodule
