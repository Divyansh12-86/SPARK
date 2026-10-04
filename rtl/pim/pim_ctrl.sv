// ============================================================================
// File:        pim_ctrl.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Master Execution Controller for Processing-In-Memory (PIM).
//
//              Orchestrates PIM acceleration workloads:
//                - Receives commands from CPU custom-1 decoded instructions or MMIO
//                - Manages vector configuration (vector length, source/dest buffers)
//                - Directs 8-lane SIMD ALU operations across scratchpad memory
//                - Tracks execution cycles and asserts pim_done / pim_irq
//                - Provides status and performance counter registers
// ============================================================================

module pim_ctrl
    import riscv_pkg::*;
#(
    parameter int BUFFER_LINES = 64
) (
    input  logic                     clk,
    input  logic                     rst_n,

    // ------------------------------------------------------------------------
    // CPU Custom Instruction Command Interface
    // ------------------------------------------------------------------------
    input  logic                     cmd_valid,
    output logic                     cmd_ready,
    input  pim_op_t                  cmd_op,
    input  logic [31:0]              cmd_rs1_val,  // e.g. length or scalar immediate
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0]              cmd_rs2_val,  // e.g. base addresses/ptrs or cfg
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0]              cmd_rd_val,   // e.g. reduction result / status
    output logic                     cmd_done,

    // ------------------------------------------------------------------------
    // Buffer A Control Interface
    // ------------------------------------------------------------------------
    output logic                     buf_a_en,
    output logic                     buf_a_we,
    output logic [$clog2(BUFFER_LINES)-1:0] buf_a_addr,
    output logic [7:0][31:0]         buf_a_wdata,
    input  logic [7:0][31:0]         buf_a_rdata,

    // ------------------------------------------------------------------------
    // Buffer B Control Interface
    // ------------------------------------------------------------------------
    output logic                     buf_b_en,
    output logic                     buf_b_we,
    output logic [$clog2(BUFFER_LINES)-1:0] buf_b_addr,
    output logic [7:0][31:0]         buf_b_wdata,
    input  logic [7:0][31:0]         buf_b_rdata,

    // ------------------------------------------------------------------------
    // SIMD ALU Control & Data Interface
    // ------------------------------------------------------------------------
    output logic                     alu_en,
    output pim_op_t                  alu_op,
    output logic [7:0][31:0]         alu_vec_a,
    output logic [7:0][31:0]         alu_vec_b,
    output logic [31:0]              alu_scalar_in,
    input  logic [7:0][31:0]         alu_result_vec,
    input  logic [31:0]              alu_reduction_out,

    // ------------------------------------------------------------------------
    // SoC / Interrupt Interface
    // ------------------------------------------------------------------------
    output logic                     pim_busy,
    output logic                     pim_irq,
    output logic [31:0]              perf_cycle_cnt
);

    localparam int ADDR_W = $clog2(BUFFER_LINES);

    // ------------------------------------------------------------------------
    // FSM State Encoding
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        CONFIG      = 3'b001,
        READ_WAIT   = 3'b010,
        EXECUTE     = 3'b011,
        WRITE_BACK  = 3'b100,
        ACCUM_WAIT  = 3'b101,
        FINISH      = 3'b110
    } pim_state_t;

    pim_state_t state, next_state;

    // ------------------------------------------------------------------------
    // Internal Registers
    // ------------------------------------------------------------------------
    logic [15:0]        vlen_reg;           // Number of 32-bit elements (default 8)
    logic [15:0]        line_count;         // Number of 256-bit lines (vlen / 8)
    logic [15:0]        curr_line;          // Current line pointer
    pim_op_t            active_op;          // Active operation
    logic [31:0]        active_scalar;      // Active scalar/broadcast operand
    logic [31:0]        accum_reg;          // Total accumulator for reduction / VMAC
    logic [31:0]        cycles;             // Hardware cycle counter
    logic [ADDR_W-1:0]  src_a_line;
    logic [ADDR_W-1:0]  src_b_line;
    logic [ADDR_W-1:0]  dst_line;

    // Outputs driven combinationally / registered
    assign buf_a_wdata   = alu_result_vec;
    assign buf_b_wdata   = alu_result_vec;
    assign alu_vec_a     = buf_a_rdata;
    assign alu_vec_b     = buf_b_rdata;
    assign alu_op        = active_op;
    assign alu_scalar_in = active_scalar;
    assign perf_cycle_cnt = cycles;

    // ------------------------------------------------------------------------
    // Next State Logic
    // ------------------------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cmd_valid) begin
                    if (cmd_op == PIM_CFG)
                        next_state = CONFIG;
                    else
                        next_state = READ_WAIT;
                end
            end

            CONFIG: begin
                next_state = FINISH;
            end

            READ_WAIT: begin
                // Synchronous SRAM read takes 1 cycle
                next_state = EXECUTE;
            end

            EXECUTE: begin
                // ALU computes result.
                // Depending on op, write back to buffer or accumulate
                if (active_op == PIM_VSUM) begin
                    if (curr_line + 1 >= line_count)
                        next_state = ACCUM_WAIT;
                    else
                        next_state = READ_WAIT;
                end else if (active_op == PIM_VMAC) begin
                    // VMAC does parallel multiply + reduction
                    if (curr_line + 1 >= line_count)
                        next_state = ACCUM_WAIT;
                    else
                        next_state = READ_WAIT;
                end else begin
                    // Vector ops (VADD, VAND, VFILL) write back to buffer
                    next_state = WRITE_BACK;
                end
            end

            WRITE_BACK: begin
                if (curr_line + 1 >= line_count)
                    next_state = FINISH;
                else
                    next_state = READ_WAIT;
            end

            ACCUM_WAIT: begin
                next_state = FINISH;
            end

            FINISH: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    // Datapath & FSM Control
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= IDLE;
            vlen_reg       <= 16'd8;
            line_count     <= 16'd1;
            curr_line      <= 16'd0;
            active_op      <= PIM_VADD;
            active_scalar  <= 32'b0;
            accum_reg      <= 32'b0;
            cycles         <= 32'b0;
            cmd_rd_val     <= 32'b0;
            cmd_done       <= 1'b0;
            cmd_ready      <= 1'b1;
            pim_busy       <= 1'b0;
            pim_irq        <= 1'b0;
            buf_a_en       <= 1'b0;
            buf_a_we       <= 1'b0;
            buf_a_addr     <= '0;
            buf_b_en       <= 1'b0;
            buf_b_we       <= 1'b0;
            buf_b_addr     <= '0;
            alu_en         <= 1'b0;
            src_a_line     <= '0;
            src_b_line     <= '0;
            dst_line       <= '0;
        end else begin
            state <= next_state;

            // Cycle Counter
            if (state != IDLE) begin
                cycles <= cycles + 1;
            end

            case (state)
                IDLE: begin
                    cmd_done <= 1'b0;
                    pim_irq  <= 1'b0;
                    if (cmd_valid) begin
                        pim_busy   <= 1'b1;
                        cmd_ready  <= 1'b0;
                        active_op  <= cmd_op;
                        curr_line  <= 16'd0;

                        if (cmd_op == PIM_CFG) begin
                            // cmd_rs1_val = vector length in words
                            // cmd_rs2_val[ADDR_W-1:0] = base buffer index
                            vlen_reg   <= (cmd_rs1_val[15:0] == 0) ? 16'd8 : cmd_rs1_val[15:0];
                            line_count <= (cmd_rs1_val[15:0] + 7) / 8;
                            src_a_line <= cmd_rs2_val[ADDR_W-1:0];
                            src_b_line <= cmd_rs2_val[ADDR_W+15:16];
                            dst_line   <= cmd_rs2_val[ADDR_W-1:0];
                        end else begin
                            active_scalar <= cmd_rs1_val; // for VFILL or scalar factor
                            accum_reg     <= 32'b0;

                            // Kick off first read
                            buf_a_en   <= 1'b1;
                            buf_a_we   <= 1'b0;
                            buf_a_addr <= src_a_line;

                            buf_b_en   <= 1'b1;
                            buf_b_we   <= 1'b0;
                            buf_b_addr <= src_b_line;
                        end
                    end else begin
                        pim_busy  <= 1'b0;
                        cmd_ready <= 1'b1;
                    end
                end

                CONFIG: begin
                    cmd_rd_val <= {16'b0, vlen_reg};
                end

                READ_WAIT: begin
                    // Memory read latency wait state; buffer data available next edge
                    alu_en <= 1'b1;
                end

                EXECUTE: begin
                    if (active_op == PIM_VSUM || active_op == PIM_VMAC) begin
                        accum_reg <= accum_reg + alu_reduction_out;
                        if (curr_line + 1 < line_count) begin
                            curr_line  <= curr_line + 1;
                            buf_a_en   <= 1'b1;
                            buf_a_we   <= 1'b0;
                            buf_a_addr <= src_a_line + (curr_line[ADDR_W-1:0] + 1'b1);

                            buf_b_en   <= 1'b1;
                            buf_b_we   <= 1'b0;
                            buf_b_addr <= src_b_line + (curr_line[ADDR_W-1:0] + 1'b1);
                        end
                    end else begin
                        // Vector result is ready to write back to Buffer A at current line
                        buf_a_en   <= 1'b1;
                        buf_a_we   <= 1'b1;
                        buf_a_addr <= dst_line + curr_line[ADDR_W-1:0];
                    end
                end

                WRITE_BACK: begin
                    buf_a_we <= 1'b0;
                    if (curr_line + 1 < line_count) begin
                        curr_line  <= curr_line + 1;
                        // Setup read for next line
                        buf_a_en   <= 1'b1;
                        buf_a_we   <= 1'b0;
                        buf_a_addr <= src_a_line + (curr_line[ADDR_W-1:0] + 1'b1);

                        buf_b_en   <= 1'b1;
                        buf_b_we   <= 1'b0;
                        buf_b_addr <= src_b_line + (curr_line[ADDR_W-1:0] + 1'b1);
                    end
                end

                ACCUM_WAIT: begin
                    cmd_rd_val <= accum_reg;
                end

                FINISH: begin
                    buf_a_en  <= 1'b0;
                    buf_b_en  <= 1'b0;
                    alu_en    <= 1'b0;
                    pim_busy  <= 1'b0;
                    pim_irq   <= 1'b1;
                    cmd_done  <= 1'b1;
                    cmd_ready <= 1'b1;
                    if (active_op == PIM_VSUM || active_op == PIM_VMAC) begin
                        cmd_rd_val <= accum_reg;
                    end else if (active_op == PIM_CFG) begin
                        cmd_rd_val <= {16'b0, vlen_reg};
                    end else begin
                        cmd_rd_val <= 32'h0000_0001; // Success flag
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
