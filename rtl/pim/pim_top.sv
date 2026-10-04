// ============================================================================
// File:        pim_top.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Top-Level Processing-In-Memory (PIM) Subsystem.
//
//              Integrates:
//                - pim_ctrl: Master sequencer & FSM
//                - pim_simd_alu: 8-lane 32-bit parallel integer execution engine
//                - Buffer A (pim_buffer): 2KB scratchpad (Port A: SIMD, Port B: Bus)
//                - Buffer B (pim_buffer): 2KB scratchpad (Port A: SIMD, Port B: Bus)
//
//              Exposes:
//                - Direct CPU custom instruction interface (opcode 0101011)
//                - SoC Bus Slave Port (mapped to 0x3000_0000 - 0x3000_FFFF)
//                - Dedicated PIM interrupt line (pim_irq)
// ============================================================================

module pim_top
    import riscv_pkg::*;
#(
    parameter int BUFFER_LINES = 64
) (
    input  logic              clk,
    input  logic              rst_n,

    // ------------------------------------------------------------------------
    // CPU Direct Command Interface (Custom-1 Extension Hook)
    // ------------------------------------------------------------------------
    input  logic              cpu_cmd_valid,
    output logic              cpu_cmd_ready,
    input  pim_op_t           cpu_cmd_op,
    input  logic [31:0]       cpu_cmd_rs1,
    input  logic [31:0]       cpu_cmd_rs2,
    output logic [31:0]       cpu_cmd_rd,
    output logic              cpu_cmd_done,

    // ------------------------------------------------------------------------
    // SoC Memory Bus Slave Interface (MMIO & Buffer Access)
    //   Address mapping:
    //     0x000 - 0x7FC: Buffer A (512 words = 2KB)
    //     0x800 - 0xFFC: Buffer B (512 words = 2KB)
    //     0x1000: Control / Command Register
    //     0x1004: Status / Done Register
    //     0x1008: Operand 1 (rs1)
    //     0x100C: Operand 2 (rs2)
    //     0x1010: Result Low / Reduction Out
    //     0x1014: Performance Cycle Counter
    // ------------------------------------------------------------------------
    input  logic              bus_cs,
    input  logic              bus_we,
    input  logic              bus_re,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0]       bus_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0]       bus_wdata,
    output logic [31:0]       bus_rdata,

    // ------------------------------------------------------------------------
    // Interrupt & Status
    // ------------------------------------------------------------------------
    output logic              pim_busy,
    output logic              pim_irq
);

    localparam int ADDR_W = $clog2(BUFFER_LINES);

    // ------------------------------------------------------------------------
    // MMIO Registers
    // ------------------------------------------------------------------------
    logic        mmio_cmd_valid;
    pim_op_t     mmio_cmd_op;
    logic [31:0] mmio_cmd_rs1;
    logic [31:0] mmio_cmd_rs2;
    logic [31:0] mmio_result;
    logic [31:0] perf_cycle_cnt;

    // Command Mux (CPU direct takes priority if asserted)
    logic        effective_cmd_valid;
    pim_op_t     effective_cmd_op;
    logic [31:0] effective_cmd_rs1;
    logic [31:0] effective_cmd_rs2;
    logic [31:0] ctrl_cmd_rd;
    logic        ctrl_cmd_done;
    logic        ctrl_cmd_ready;

    assign effective_cmd_valid = cpu_cmd_valid | mmio_cmd_valid;
    assign effective_cmd_op    = cpu_cmd_valid ? cpu_cmd_op  : mmio_cmd_op;
    assign effective_cmd_rs1   = cpu_cmd_valid ? cpu_cmd_rs1 : mmio_cmd_rs1;
    assign effective_cmd_rs2   = cpu_cmd_valid ? cpu_cmd_rs2 : mmio_cmd_rs2;

    assign cpu_cmd_ready = ctrl_cmd_ready;
    assign cpu_cmd_rd    = ctrl_cmd_rd;
    assign cpu_cmd_done  = ctrl_cmd_done;

    // ------------------------------------------------------------------------
    // Buffer Internal Signals
    // ------------------------------------------------------------------------
    // Buffer A Port A (SIMD)
    logic                     buf_a_en;
    logic                     buf_a_we;
    logic [ADDR_W-1:0]        buf_a_addr;
    logic [7:0][31:0]         buf_a_wdata;
    logic [7:0][31:0]         buf_a_rdata;

    // Buffer A Port B (Bus)
    logic                     buf_a_b_en;
    logic                     buf_a_b_we;
    logic [ADDR_W+2:0]        buf_a_b_addr;
    logic [31:0]              buf_a_b_wdata;
    logic [31:0]              buf_a_b_rdata;

    // Buffer B Port A (SIMD)
    logic                     buf_b_en;
    logic                     buf_b_we;
    logic [ADDR_W-1:0]        buf_b_addr;
    logic [7:0][31:0]         buf_b_wdata;
    logic [7:0][31:0]         buf_b_rdata;

    // Buffer B Port B (Bus)
    logic                     buf_b_b_en;
    logic                     buf_b_b_we;
    logic [ADDR_W+2:0]        buf_b_b_addr;
    logic [31:0]              buf_b_b_wdata;
    logic [31:0]              buf_b_b_rdata;

    // ------------------------------------------------------------------------
    // SIMD ALU Signals
    // ------------------------------------------------------------------------
    logic                     alu_en;
    pim_op_t                  alu_op;
    logic [7:0][31:0]         alu_vec_a;
    logic [7:0][31:0]         alu_vec_b;
    logic [31:0]              alu_scalar_in;
    logic [7:0][31:0]         alu_result_vec;
    logic [31:0]              alu_reduction_out;

    // ------------------------------------------------------------------------
    // PIM Submodules Instantiation
    // ------------------------------------------------------------------------
    pim_buffer #(
        .DEPTH(BUFFER_LINES),
        .ADDR_WIDTH(ADDR_W)
    ) u_buf_a (
        .clk        (clk),
        .rst_n      (rst_n),
        .porta_en   (buf_a_en),
        .porta_we   (buf_a_we),
        .porta_addr (buf_a_addr),
        .porta_wdata(buf_a_wdata),
        .porta_rdata(buf_a_rdata),
        .portb_en   (buf_a_b_en),
        .portb_we   (buf_a_b_we),
        .portb_addr (buf_a_b_addr),
        .portb_wdata(buf_a_b_wdata),
        .portb_rdata(buf_a_b_rdata)
    );

    pim_buffer #(
        .DEPTH(BUFFER_LINES),
        .ADDR_WIDTH(ADDR_W)
    ) u_buf_b (
        .clk        (clk),
        .rst_n      (rst_n),
        .porta_en   (buf_b_en),
        .porta_we   (buf_b_we),
        .porta_addr (buf_b_addr),
        .porta_wdata(buf_b_wdata),
        .porta_rdata(buf_b_rdata),
        .portb_en   (buf_b_b_en),
        .portb_we   (buf_b_b_we),
        .portb_addr (buf_b_b_addr),
        .portb_wdata(buf_b_b_wdata),
        .portb_rdata(buf_b_b_rdata)
    );

    pim_simd_alu #(
        .LANES(8)
    ) u_simd_alu (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (alu_en),
        .op           (alu_op),
        .vec_a        (alu_vec_a),
        .vec_b        (alu_vec_b),
        .scalar_in    (alu_scalar_in),
        .result_vec   (alu_result_vec),
        .reduction_out(alu_reduction_out)
    );

    pim_ctrl #(
        .BUFFER_LINES(BUFFER_LINES)
    ) u_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .cmd_valid        (effective_cmd_valid),
        .cmd_ready        (ctrl_cmd_ready),
        .cmd_op           (effective_cmd_op),
        .cmd_rs1_val      (effective_cmd_rs1),
        .cmd_rs2_val      (effective_cmd_rs2),
        .cmd_rd_val       (ctrl_cmd_rd),
        .cmd_done         (ctrl_cmd_done),
        .buf_a_en         (buf_a_en),
        .buf_a_we         (buf_a_we),
        .buf_a_addr       (buf_a_addr),
        .buf_a_wdata      (buf_a_wdata),
        .buf_a_rdata      (buf_a_rdata),
        .buf_b_en         (buf_b_en),
        .buf_b_we         (buf_b_we),
        .buf_b_addr       (buf_b_addr),
        .buf_b_wdata      (buf_b_wdata),
        .buf_b_rdata      (buf_b_rdata),
        .alu_en           (alu_en),
        .alu_op           (alu_op),
        .alu_vec_a        (alu_vec_a),
        .alu_vec_b        (alu_vec_b),
        .alu_scalar_in    (alu_scalar_in),
        .alu_result_vec   (alu_result_vec),
        .alu_reduction_out(alu_reduction_out),
        .pim_busy         (pim_busy),
        .pim_irq          (pim_irq),
        .perf_cycle_cnt   (perf_cycle_cnt)
    );

    // ------------------------------------------------------------------------
    // Bus MMIO & Scratchpad Address Decoding
    // ------------------------------------------------------------------------
    // Offset bits: bus_addr[15:0]
    wire is_buf_a = bus_cs && (bus_addr[15:11] == 5'b00000); // 0x0000 - 0x07FF (2KB)
    wire is_buf_b = bus_cs && (bus_addr[15:11] == 5'b00001); // 0x0800 - 0x0FFF (2KB)
    wire is_regs  = bus_cs && (bus_addr[15:11] == 5'b00010); // 0x1000 - 0x17FF

    assign buf_a_b_en    = is_buf_a && (bus_re || bus_we);
    assign buf_a_b_we    = is_buf_a && bus_we;
    assign buf_a_b_addr  = bus_addr[10:2]; // 512 words = 9 bits
    assign buf_a_b_wdata = bus_wdata;

    assign buf_b_b_en    = is_buf_b && (bus_re || bus_we);
    assign buf_b_b_we    = is_buf_b && bus_we;
    assign buf_b_b_addr  = bus_addr[10:2]; // 512 words = 9 bits
    assign buf_b_b_wdata = bus_wdata;

    // MMIO Read Mux
    always_comb begin
        bus_rdata = 32'b0;
        if (is_buf_a) begin
            bus_rdata = buf_a_b_rdata;
        end else if (is_buf_b) begin
            bus_rdata = buf_b_b_rdata;
        end else if (is_regs) begin
            case (bus_addr[7:0])
                8'h00: bus_rdata = {29'b0, mmio_cmd_op};
                8'h04: bus_rdata = {30'b0, ctrl_cmd_done, pim_busy};
                8'h08: bus_rdata = mmio_cmd_rs1;
                8'h0C: bus_rdata = mmio_cmd_rs2;
                8'h10: bus_rdata = mmio_result;
                8'h14: bus_rdata = perf_cycle_cnt;
                default: bus_rdata = 32'b0;
            endcase
        end
    end

    // MMIO Write Handling
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mmio_cmd_valid <= 1'b0;
            mmio_cmd_op    <= PIM_VADD;
            mmio_cmd_rs1   <= 32'b0;
            mmio_cmd_rs2   <= 32'b0;
            mmio_result    <= 32'b0;
        end else begin
            if (ctrl_cmd_done) begin
                mmio_result    <= ctrl_cmd_rd;
                mmio_cmd_valid <= 1'b0;
            end

            if (is_regs && bus_we) begin
                case (bus_addr[7:0])
                    8'h00: begin
                        mmio_cmd_op    <= pim_op_t'(bus_wdata[2:0]);
                        mmio_cmd_valid <= 1'b1; // Trigger command on write to cmd register
                    end
                    8'h08: mmio_cmd_rs1 <= bus_wdata;
                    8'h0C: mmio_cmd_rs2 <= bus_wdata;
                    default: ;
                endcase
            end
        end
    end

endmodule
