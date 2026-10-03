// ============================================================================
// File:        icache.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: L1 Instruction Cache (2-Way Set-Associative, 4 KB, 32-Byte Lines).
//
//              Geometry:
//                - Capacity:  4 KB
//                - Line Size: 32 Bytes (8 Words)
//                - Ways:      2
//                - Sets:      64 Sets (Index: addr[10:5])
//                - Tag:       21 bits (addr[31:11])
//                - Offset:    5 bits  (addr[4:0], word = addr[4:2])
// ============================================================================

module icache (
    input  logic        clk,
    input  logic        rst_n,

    // CPU Instruction Fetch Interface
    input  logic        req_valid,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] rdata,
    output logic        hit,
    output logic        stall,

    // Refill Bus Interface (to Bus Interconnect / Main Memory)
    output logic        mem_req,
    output logic [31:0] mem_addr,
    input  logic [31:0] mem_rdata,
    input  logic        mem_valid
);

    localparam int NUM_SETS  = 64;
    localparam int LINE_SIZE = 32;

    wire [5:0]  set_idx     = addr[10:5];
    wire [20:0] tag         = addr[31:11];
    wire [2:0]  word_offset = addr[4:2];

    // Cache Tag & Valid Arrays (2 Ways)
    logic        way0_valid [0:NUM_SETS-1];
    logic [20:0] way0_tag   [0:NUM_SETS-1];
    logic [31:0] way0_data  [0:NUM_SETS-1][0:7];

    logic        way1_valid [0:NUM_SETS-1];
    logic [20:0] way1_tag   [0:NUM_SETS-1];
    logic [31:0] way1_data  [0:NUM_SETS-1][0:7];

    // LRU state per set (0 = replace Way 0, 1 = replace Way 1)
    logic lru [0:NUM_SETS-1];

    // Hit Logic
    wire way0_hit = way0_valid[set_idx] && (way0_tag[set_idx] == tag);
    wire way1_hit = way1_valid[set_idx] && (way1_tag[set_idx] == tag);
    assign hit    = (way0_hit || way1_hit) && req_valid;

    // Word Output Multiplexer
    always_comb begin
        if (way0_hit)      rdata = way0_data[set_idx][word_offset];
        else if (way1_hit) rdata = way1_data[set_idx][word_offset];
        else               rdata = 32'b0;
    end

    // Refill FSM
    typedef enum logic [1:0] {
        IDLE        = 2'b00,
        REFILL_BURST= 2'b01,
        FINISH      = 2'b10
    } state_t;

    state_t state;
    logic [2:0] refill_word_cnt;
    logic       victim_way;

    assign stall = req_valid && (!hit);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state           <= IDLE;
            mem_req         <= 1'b0;
            mem_addr        <= 32'b0;
            refill_word_cnt <= 3'b0;
            victim_way      <= 1'b0;

            for (int i = 0; i < NUM_SETS; i++) begin
                way0_valid[i] <= 1'b0;
                way1_valid[i] <= 1'b0;
                way0_tag[i]   <= 21'b0;
                way1_tag[i]   <= 21'b0;
                lru[i]        <= 1'b0;
                for (int w = 0; w < 8; w++) begin
                    way0_data[i][w] <= 32'b0;
                    way1_data[i][w] <= 32'b0;
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    mem_req <= 1'b0;
                    if (req_valid && !hit) begin
                        // Cache Miss -> Start Refill of line {addr[31:5], 5'b0}
                        victim_way      <= lru[set_idx];
                        mem_req         <= 1'b1;
                        mem_addr        <= {addr[31:5], 5'b0};
                        refill_word_cnt <= 3'b0;
                        state           <= REFILL_BURST;
                    end else if (hit) begin
                        // Update LRU on hit
                        if (way0_hit) lru[set_idx] <= 1'b1; // Way 1 is next victim
                        else          lru[set_idx] <= 1'b0; // Way 0 is next victim
                    end
                end

                REFILL_BURST: begin
                    if (mem_valid) begin
                        if (victim_way == 1'b0) begin
                            way0_data[set_idx][refill_word_cnt] <= mem_rdata;
                        end else begin
                            way1_data[set_idx][refill_word_cnt] <= mem_rdata;
                        end

                        if (refill_word_cnt == 3'd7) begin
                            mem_req <= 1'b0;
                            // Set Valid and Tag upon full line refill
                            if (victim_way == 1'b0) begin
                                way0_valid[set_idx] <= 1'b1;
                                way0_tag[set_idx]   <= tag;
                            end else begin
                                way1_valid[set_idx] <= 1'b1;
                                way1_tag[set_idx]   <= tag;
                            end
                            lru[set_idx] <= ~victim_way;
                            state        <= FINISH;
                        end else begin
                            refill_word_cnt <= refill_word_cnt + 3'd1;
                            mem_addr        <= mem_addr + 32'd4;
                        end
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
