// ============================================================================
// File:        dcache.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: L1 Data Cache (4-Way Set-Associative, 4 KB, Write-Back, Write-Allocate).
//
//              Geometry:
//                - Capacity:       4 KB
//                - Line Size:      32 Bytes (8 Words)
//                - Ways:           4
//                - Sets:           32 Sets (Index: addr[9:5])
//                - Tag:            22 bits (addr[31:10])
//                - Offset:         5 bits  (addr[4:0])
//
//              Policies:
//                - Write-Back:     Dirty lines written to memory only on eviction
//                - Write-Allocate: Write misses fetch line first
//                - MMIO Bypass:    Peripheral spaces (UART, CLINT, PLIC) bypass cache
// ============================================================================

module dcache (
    input  logic        clk,
    input  logic        rst_n,

    // CPU Interface
    input  logic        req_valid,
    input  logic        we,             // 1 = write, 0 = read
    input  logic [2:0]  funct3,         // Access width & sign (SB, SH, SW, LB, LH, LW, etc.)
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic        hit,
    output logic        stall,

    // Bus / Main Memory Interface
    output logic        mem_req,
    output logic        mem_we,         // 1 = write-back, 0 = refill
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    input  logic        mem_valid,
    input  logic        mem_ready
);

    localparam int NUM_SETS = 32;
    localparam int NUM_WAYS = 4;

    wire [4:0]  set_idx     = addr[9:5];
    wire [21:0] tag         = addr[31:10];
    wire [2:0]  word_offset = addr[4:2];
    wire [1:0]  byte_offset = addr[1:0];

    // Detect MMIO uncached peripheral access:
    //   0x1000_0000: UART
    //   0x2000_0000: CLINT
    //   0xC000_0000: PLIC
    wire is_mmio = (addr[31:24] == 8'h10) || (addr[31:24] == 8'h20) || (addr[31:28] == 4'hC);

    // Cache Arrays: 4 Ways
    logic        valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic        dirty_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic [21:0] tag_array   [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic [31:0] data_array  [0:NUM_SETS-1][0:NUM_WAYS-1][0:7];

    // Simple replacement counter per set
    logic [1:0] replace_ptr [0:NUM_SETS-1];

    // Hit Detection across 4 ways
    logic [NUM_WAYS-1:0] way_hit;
    always_comb begin
        for (int w = 0; w < NUM_WAYS; w++) begin
            way_hit[w] = valid_array[set_idx][w] && (tag_array[set_idx][w] == tag);
        end
    end

    wire cache_hit = (|way_hit) && req_valid && (!is_mmio);
    assign hit     = cache_hit;

    // Word read multiplexer
    logic [31:0] raw_cache_word;
    always_comb begin
        raw_cache_word = 32'b0;
        for (int w = 0; w < NUM_WAYS; w++) begin
            if (way_hit[w]) raw_cache_word = data_array[set_idx][w][word_offset];
        end
    end

    // Format read data based on funct3 (LB, LH, LW, LBU, LHU)
    logic [7:0]  sel_byte;
    logic [15:0] sel_half;
    always_comb begin
        sel_byte = raw_cache_word[byte_offset*8 +: 8];
        sel_half = byte_offset[1] ? raw_cache_word[31:16] : raw_cache_word[15:0];

        case (funct3)
            3'b000:  rdata = {{24{sel_byte[7]}}, sel_byte}; // LB
            3'b001:  rdata = {{16{sel_half[15]}}, sel_half}; // LH
            3'b010:  rdata = raw_cache_word;                // LW
            3'b100:  rdata = {24'b0, sel_byte};             // LBU
            3'b101:  rdata = {16'b0, sel_half};             // LHU
            default: rdata = raw_cache_word;
        endcase
    end

    // FSM States
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        WRITEBACK   = 3'b001,
        REFILL      = 3'b010,
        MMIO_WAIT   = 3'b011,
        FINISH      = 3'b100
    } state_t;

    state_t state;
    logic [2:0] burst_cnt;
    logic [1:0] victim_way;

    assign stall = req_valid && (!cache_hit);

    // Compute updated word for sub-word store writes
    function automatic logic [31:0] apply_store(
        input logic [31:0] orig,
        input logic [31:0] val,
        input logic [2:0]  f3,
        input logic [1:0]  boff
    );
        logic [31:0] res;
        res = orig;
        case (f3)
            3'b000: res[boff*8 +: 8] = val[7:0]; // SB
            3'b001: begin                       // SH
                if (boff[1]) res[31:16] = val[15:0];
                else         res[15:0]  = val[15:0];
            end
            default: res = val;                 // SW
        endcase
        return res;
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state      <= IDLE;
            mem_req    <= 1'b0;
            mem_we     <= 1'b0;
            mem_addr   <= 32'b0;
            mem_wdata  <= 32'b0;
            burst_cnt  <= 3'b0;
            victim_way <= 2'b0;

            for (int s = 0; s < NUM_SETS; s++) begin
                replace_ptr[s] <= 2'b0;
                for (int w = 0; w < NUM_WAYS; w++) begin
                    valid_array[s][w] <= 1'b0;
                    dirty_array[s][w] <= 1'b0;
                    tag_array[s][w]   <= 22'b0;
                    for (int i = 0; i < 8; i++) begin
                        data_array[s][w][i] <= 32'b0;
                    end
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    mem_req <= 1'b0;

                    if (req_valid) begin
                        if (is_mmio) begin
                            // Bypass cache directly to bus for MMIO peripherals
                            mem_req   <= 1'b1;
                            mem_we    <= we;
                            mem_addr  <= addr;
                            mem_wdata <= wdata;
                            state     <= MMIO_WAIT;
                        end else if (cache_hit) begin
                            if (we) begin
                                // Write Hit: update word and mark line dirty
                                for (int w = 0; w < NUM_WAYS; w++) begin
                                    if (way_hit[w]) begin
                                        data_array[set_idx][w][word_offset] <=
                                            apply_store(data_array[set_idx][w][word_offset], wdata, funct3, byte_offset);
                                        dirty_array[set_idx][w] <= 1'b1;
                                    end
                                end
                            end
                        end else begin
                            // Cache Miss
                            victim_way <= replace_ptr[set_idx];
                            if (valid_array[set_idx][replace_ptr[set_idx]] &&
                                dirty_array[set_idx][replace_ptr[set_idx]]) begin
                                // Victim is dirty -> must write back to memory first
                                state     <= WRITEBACK;
                                mem_req   <= 1'b1;
                                mem_we    <= 1'b1;
                                mem_addr  <= {tag_array[set_idx][replace_ptr[set_idx]], set_idx, 5'b0};
                                mem_wdata <= data_array[set_idx][replace_ptr[set_idx]][0];
                                burst_cnt <= 3'b0;
                            end else begin
                                // Victim clean or invalid -> start refill
                                state     <= REFILL;
                                mem_req   <= 1'b1;
                                mem_we    <= 1'b0;
                                mem_addr  <= {addr[31:5], 5'b0};
                                burst_cnt <= 3'b0;
                            end
                        end
                    end
                end

                WRITEBACK: begin
                    if (mem_ready) begin
                        if (burst_cnt == 3'd7) begin
                            // Writeback finished -> start refill
                            state     <= REFILL;
                            mem_we    <= 1'b0;
                            mem_addr  <= {addr[31:5], 5'b0};
                            burst_cnt <= 3'b0;
                        end else begin
                            burst_cnt <= burst_cnt + 3'd1;
                            mem_addr  <= mem_addr + 32'd4;
                            mem_wdata <= data_array[set_idx][victim_way][burst_cnt + 3'd1];
                        end
                    end
                end

                REFILL: begin
                    if (mem_valid) begin
                        data_array[set_idx][victim_way][burst_cnt] <= mem_rdata;

                        if (burst_cnt == 3'd7) begin
                            mem_req <= 1'b0;
                            valid_array[set_idx][victim_way] <= 1'b1;
                            tag_array[set_idx][victim_way]   <= tag;
                            dirty_array[set_idx][victim_way] <= 1'b0;
                            replace_ptr[set_idx]             <= replace_ptr[set_idx] + 2'd1;

                            // If this miss was caused by a store, apply the write immediately
                            if (we) begin
                                data_array[set_idx][victim_way][word_offset] <=
                                    apply_store(mem_rdata, wdata, funct3, byte_offset);
                                dirty_array[set_idx][victim_way] <= 1'b1;
                            end

                            state <= FINISH;
                        end else begin
                            burst_cnt <= burst_cnt + 3'd1;
                            mem_addr  <= mem_addr + 32'd4;
                        end
                    end
                end

                MMIO_WAIT: begin
                    if (mem_ready || mem_valid) begin
                        mem_req <= 1'b0;
                        state   <= FINISH;
                    end
                end

                FINISH: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
