// ============================================================================
// File:        uart.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: 16550-Compatible UART Controller (Transmitter & Receiver)
//              with integrated Mouse Coordinate status registers.
//
//              Memory-Mapped Registers (Base 0x1000_0000):
//                Offset 0x00: RBR (Read, Receiver Buffer Register) /
//                             THR (Write, Transmitter Holding Register)
//                Offset 0x01: IER (Interrupt Enable Register)
//                               Bit 0 = Enable Received Data Available Interrupt
//                               Bit 1 = Enable Transmitter Holding Register Empty Interrupt
//                Offset 0x02: IIR (Interrupt Ident. Register) / FCR (FIFO Control)
//                Offset 0x03: LCR (Line Control Register)
//                Offset 0x04: MCR (Modem Control Register)
//                Offset 0x05: LSR (Line Status Register):
//                               Bit 0 = DR   (Data Ready in RBR)
//                               Bit 5 = THRE (Transmitter Holding Register Empty)
//                               Bit 6 = TEMT (Transmitter Empty)
//                Offset 0x06: MSR (Mouse Buttons: bit 0=left, 1=right, 2=middle)
//                Offset 0x07: SCR (Mouse Coordinates: [25:16]=mouse_x, [8:0]=mouse_y)
// ============================================================================

module uart #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115_200,
    parameter int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE
) (
    input  logic        clk,
    input  logic        rst_n,

    // Bus Interface
    input  logic        cs,         // Chip Select
    input  logic        read_en,    // Read Enable
    input  logic        write_en,   // Write Enable
    input  logic [2:0]  addr,       // Register offset (0..7)
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] write_data,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] read_data,

    // Serial Pins
    output logic        tx,
    input  logic        rx,

    // Host Mouse Input Interface (from GUI / Co-simulation)
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [9:0]  mouse_x,
    input  logic [8:0]  mouse_y,
    input  logic [2:0]  mouse_btn,
    /* verilator lint_on UNUSEDSIGNAL */

    // Interrupt
    output logic        uart_irq
);

    // ========================================================================
    // Internal Registers
    // ========================================================================
    /* verilator lint_off UNUSEDSIGNAL */
    logic [7:0] thr;         // Transmit Holding Register
    /* verilator lint_on UNUSEDSIGNAL */
    logic [7:0] ier;         // Interrupt Enable Register
    logic [7:0] lsr;         // Line Status Register

    // TX State Machine
    typedef enum logic [1:0] {
        TX_IDLE  = 2'b00,
        TX_START = 2'b01,
        TX_DATA  = 2'b10,
        TX_STOP  = 2'b11
    } tx_state_t;

    tx_state_t tx_state;
    int          tx_clk_count;
    logic [2:0]  tx_bit_idx;
    logic [7:0]  tx_shift_reg;
    logic        tx_busy;

    // RX State Machine
    typedef enum logic [1:0] {
        RX_IDLE  = 2'b00,
        RX_START = 2'b01,
        RX_DATA  = 2'b10,
        RX_STOP  = 2'b11
    } rx_state_t;

    rx_state_t rx_state;
    int         rx_clk_count;
    logic [2:0] rx_bit_idx;
    logic [7:0] rx_shift_reg;

    // 64-byte RX Hardware FIFO (16550 UART standard)
    logic [7:0] rx_fifo [0:63];
    logic [5:0] rx_fifo_wptr;
    logic [5:0] rx_fifo_rptr;
    logic [6:0] rx_fifo_count;
    logic       rx_fifo_push;
    logic       rx_fifo_pop;

    wire rx_byte_done = (rx_state == RX_STOP) && (rx_clk_count == CLKS_PER_BIT - 1);
    assign rx_fifo_push = rx_byte_done && (rx_fifo_count < 7'd64);
    logic prev_rbr_read;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            prev_rbr_read <= 1'b0;
        end else begin
            prev_rbr_read <= (cs && read_en && (addr == 3'h0));
        end
    end

    wire rbr_read_pulse = (cs && read_en && (addr == 3'h0)) && !prev_rbr_read;
    assign rx_fifo_pop  = rbr_read_pulse && (rx_fifo_count > 7'd0);

    logic [7:0] rbr;
    assign rbr = rx_fifo[rx_fifo_rptr];
    logic rx_data_ready;
    assign rx_data_ready = (rx_fifo_count > 7'd0);

    // Double flop synchronizer for rx pin
    logic rx_sync1, rx_sync2;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    // Line Status Register:
    assign lsr[7]   = 1'b0;
    assign lsr[6]   = !tx_busy;       // TEMT
    assign lsr[5]   = !tx_busy;       // THRE
    assign lsr[4:1] = 4'b0000;
    assign lsr[0]   = rx_data_ready;  // DR (Data ready)

    assign uart_irq = (ier[1] && !tx_busy) || (ier[0] && rx_data_ready);

    // ========================================================================
    // Bus Read
    // ========================================================================
    always_comb begin
        if (cs && read_en) begin
            case (addr)
                3'h0:    read_data = {24'b0, rbr};
                3'h1:    read_data = {24'b0, ier};
                3'h2:    read_data = rx_data_ready ? 32'h0000_0004 : (ier[1] ? 32'h0000_0002 : 32'h0000_0001);
                3'h5:    read_data = {24'b0, lsr};
                3'h6:    read_data = {29'b0, mouse_btn};
                3'h7:    read_data = {6'b0, mouse_x, 7'b0, mouse_y};
                default: read_data = 32'b0;
            endcase
        end else begin
            read_data = 32'b0;
        end
    end

    // ========================================================================
    // Transmitter & Receiver State Machine
    // ========================================================================
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx            <= 1'b1; // UART idle state is HIGH
            tx_state      <= TX_IDLE;
            tx_clk_count  <= 0;
            tx_bit_idx    <= 3'b0;
            tx_shift_reg  <= 8'b0;
            tx_busy       <= 1'b0;
            thr           <= 8'b0;
            ier           <= 8'b0;

            rx_state      <= RX_IDLE;
            rx_clk_count  <= 0;
            rx_bit_idx    <= 3'b0;
            rx_shift_reg  <= 8'b0;
            rx_fifo_wptr  <= 6'd0;
            rx_fifo_rptr  <= 6'd0;
            rx_fifo_count <= 7'd0;
        end else begin
            // FIFO management
            if (rx_fifo_push && !rx_fifo_pop) begin
                rx_fifo[rx_fifo_wptr] <= rx_shift_reg;
                rx_fifo_wptr          <= rx_fifo_wptr + 6'd1;
                rx_fifo_count         <= rx_fifo_count + 7'd1;
            end else if (!rx_fifo_push && rx_fifo_pop) begin
                rx_fifo_rptr          <= rx_fifo_rptr + 6'd1;
                rx_fifo_count         <= rx_fifo_count - 7'd1;
            end else if (rx_fifo_push && rx_fifo_pop) begin
                rx_fifo[rx_fifo_wptr] <= rx_shift_reg;
                rx_fifo_wptr          <= rx_fifo_wptr + 6'd1;
                rx_fifo_rptr          <= rx_fifo_rptr + 6'd1;
            end

            // Bus write handling
            if (cs && write_en) begin
                case (addr)
                    3'h0: begin // Write to THR initiates transmission
                        thr          <= write_data[7:0];
                        tx_shift_reg <= write_data[7:0];
                        tx_busy      <= 1'b1;
                    end
                    3'h1: ier <= write_data[7:0];
                    default: ;
                endcase
            end

            // ----------------------------------------------------------------
            // TX FSM
            // ----------------------------------------------------------------
            case (tx_state)
                TX_IDLE: begin
                    tx <= 1'b1;
                    if (tx_busy) begin
                        tx_state     <= TX_START;
                        tx_clk_count <= 0;
                    end
                end

                TX_START: begin
                    tx <= 1'b0; // Start bit is LOW
                    if (tx_clk_count < CLKS_PER_BIT - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        tx_state     <= TX_DATA;
                        tx_bit_idx   <= 3'b0;
                    end
                end

                TX_DATA: begin
                    tx <= tx_shift_reg[tx_bit_idx];
                    if (tx_clk_count < CLKS_PER_BIT - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        if (tx_bit_idx < 3'd7) begin
                            tx_bit_idx <= tx_bit_idx + 3'd1;
                        end else begin
                            tx_state <= TX_STOP;
                        end
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1; // Stop bit is HIGH
                    if (tx_clk_count < CLKS_PER_BIT - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        tx_state     <= TX_IDLE;
                        tx_busy      <= 1'b0; // Transmission complete!
                    end
                end
            endcase

            // ----------------------------------------------------------------
            // RX FSM (Samples at midpoint of each serial bit)
            // ----------------------------------------------------------------
            case (rx_state)
                RX_IDLE: begin
                    if (rx_sync2 == 1'b0) begin // Start bit falling edge
                        rx_state     <= RX_START;
                        rx_clk_count <= 0;
                    end
                end

                RX_START: begin
                    if (rx_clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx_sync2 == 1'b0) begin
                            rx_clk_count <= 0;
                            rx_state     <= RX_DATA;
                            rx_bit_idx   <= 3'b0;
                        end else begin
                            rx_state <= RX_IDLE; // False alarm glitch
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 1;
                    end
                end

                RX_DATA: begin
                    if (rx_clk_count < CLKS_PER_BIT - 1) begin
                        rx_clk_count <= rx_clk_count + 1;
                    end else begin
                        rx_clk_count <= 0;
                        rx_shift_reg[rx_bit_idx] <= rx_sync2;
                        if (rx_bit_idx < 3'd7) begin
                            rx_bit_idx <= rx_bit_idx + 3'd1;
                        end else begin
                            rx_state <= RX_STOP;
                        end
                    end
                end

                RX_STOP: begin
                    if (rx_clk_count < CLKS_PER_BIT - 1) begin
                        rx_clk_count <= rx_clk_count + 1;
                    end else begin
                        rx_clk_count <= 0;
                        rx_state     <= RX_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
