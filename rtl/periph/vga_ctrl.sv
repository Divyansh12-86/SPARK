// ============================================================================
// File:        vga_ctrl.sv
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Software-Rendered Display Controller & Memory-Mapped Framebuffer.
//
//              Adapted from display-controller (duplicate with SPARK integration).
//              Zero changes made to the external display-controller repo.
//
//              Features:
//                - Dual-Ported VRAM:
//                    Port A: Read-only video rasterizer (pixel_clk domain)
//                    Port B: Read/Write SoC memory bus (clk domain, 0xF000_0000)
//                - Configurable Resolution:
//                    Default: 320x240 @ 60Hz (76,800 pixels = 75 KB VRAM)
//                    Standard 640x480 VGA raster timing (scaled 2x per pixel)
//                - 12-bit RGB Video Output (vga_r[3:0], vga_g[3:0], vga_b[3:0])
//                - Precise VGA timing signals: hsync, vsync, display_on
//                - Supports PIM pim.vfill accelerated bulk framebuffer clears
// ============================================================================

module vga_ctrl #(
    parameter int H_DISPLAY     = 640,
    parameter int H_FRONT_PORCH = 16,
    parameter int H_SYNC_PULSE  = 96,
    parameter int H_BACK_PORCH  = 48,
    parameter int H_TOTAL       = 800,

    parameter int V_DISPLAY     = 480,
    parameter int V_FRONT_PORCH = 10,
    parameter int V_SYNC_PULSE  = 2,
    parameter int V_BACK_PORCH  = 33,
    parameter int V_TOTAL       = 525,

    // Internal resolution (320x240 scaled to 640x480)
    parameter int FB_WIDTH      = 320,
    parameter int FB_HEIGHT     = 240,
    parameter int FB_SIZE       = FB_WIDTH * FB_HEIGHT // 76,800 words/pixels
) (
    // System Bus Interface (clk domain)
    input  logic        clk,
    input  logic        rst_n,
    input  logic        bus_cs,
    input  logic        bus_we,
    input  logic        bus_re,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] bus_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] bus_wdata,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] bus_rdata,

    // Video Display Interface (pixel_clk domain)
    input  logic        pixel_clk,
    output logic        hsync,
    output logic        vsync,
    output logic        display_on,
    output logic [3:0]  vga_r,
    output logic [3:0]  vga_g,
    output logic [3:0]  vga_b,
    output logic [19:0] pixel_addr
);

    // ------------------------------------------------------------------------
    // Dual-Ported Video RAM (VRAM)
    // ------------------------------------------------------------------------
    // Stores 12-bit color per pixel (RGB 4:4:4)
    logic [11:0] vram [0:FB_SIZE-1];

    // Bus Port B (32-bit word/pixel write and read)
    wire [31:0] bus_pixel_idx = {15'b0, bus_addr[18:2]}; // 32-bit index

    always_ff @(posedge clk) begin
        if (bus_cs && bus_we) begin
            if (bus_pixel_idx < 32'(FB_SIZE)) begin
                vram[bus_pixel_idx[16:0]] <= bus_wdata[11:0];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bus_rdata <= 32'b0;
        end else if (bus_cs && bus_re) begin
            if (bus_pixel_idx < 32'(FB_SIZE)) begin
                bus_rdata <= {20'b0, vram[bus_pixel_idx[16:0]]};
            end else begin
                bus_rdata <= 32'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // VGA Raster Timing Generator (pixel_clk domain)
    // ------------------------------------------------------------------------
    logic [9:0] h_count;
    logic [9:0] v_count;
    logic       display_on_raw;
    logic       display_on_d1;
    logic [11:0] pixel_data_raster;

    // Horizontal & Vertical Position Counters (Synchronous reset)
    always_ff @(posedge pixel_clk) begin
        if (!rst_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count < 10'(H_TOTAL - 1)) begin
                h_count <= h_count + 1'b1;
            end else begin
                h_count <= 10'd0;
                if (v_count < 10'(V_TOTAL - 1)) begin
                    v_count <= v_count + 1'b1;
                end else begin
                    v_count <= 10'd0;
                end
            end
        end
    end

    // Horizontal Sync (active low)
    always_ff @(posedge pixel_clk) begin
        if (!rst_n) begin
            hsync <= 1'b1;
        end else begin
            if ((h_count >= 10'(H_DISPLAY + H_FRONT_PORCH)) && 
                (h_count < 10'(H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE))) begin
                hsync <= 1'b0;
            end else begin
                hsync <= 1'b1;
            end
        end
    end

    // Vertical Sync (active low)
    always_ff @(posedge pixel_clk) begin
        if (!rst_n) begin
            vsync <= 1'b1;
        end else begin
            if ((v_count >= 10'(V_DISPLAY + V_FRONT_PORCH)) && 
                (v_count < 10'(V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE))) begin
                vsync <= 1'b0;
            end else begin
                vsync <= 1'b1;
            end
        end
    end

    // Active Display Period
    always_ff @(posedge pixel_clk) begin
        if (!rst_n) begin
            display_on_raw <= 1'b0;
            display_on_d1  <= 1'b0;
        end else begin
            display_on_raw <= (h_count < 10'(H_DISPLAY)) && (v_count < 10'(V_DISPLAY));
            display_on_d1  <= display_on_raw;
        end
    end

    assign display_on = display_on_raw;

    // 2x Scaling: (h_count >> 1) and (v_count >> 1) maps 640x480 raster to 320x240 VRAM
    wire [16:0] fb_x = {8'b0, h_count[9:1]}; // 0 to 319
    wire [16:0] fb_y = {9'b0, v_count[8:1]}; // 0 to 239
    /* verilator lint_off WIDTHTRUNC */
    wire [16:0] vram_addr = (display_on_raw) ? 17'((fb_y * 17'(FB_WIDTH)) + fb_x) : 17'd0;
    /* verilator lint_on WIDTHTRUNC */
    assign pixel_addr = {3'b0, vram_addr};

    // Synchronous VRAM read on pixel_clk
    always_ff @(posedge pixel_clk) begin
        if (display_on_raw) begin
            pixel_data_raster <= vram[vram_addr];
        end else begin
            pixel_data_raster <= 12'h000;
        end
    end

    // RGB Output (1-cycle pipeline aligned with display_on_d1)
    assign vga_r = display_on_d1 ? pixel_data_raster[11:8] : 4'h0;
    assign vga_g = display_on_d1 ? pixel_data_raster[7:4]  : 4'h0;
    assign vga_b = display_on_d1 ? pixel_data_raster[3:0]  : 4'h0;

endmodule
