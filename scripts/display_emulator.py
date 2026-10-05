# -*- coding: utf-8 -*-
"""
SPARK VGA Display Emulator (Pygame Virtual Monitor)
Adapted from display-controller/scripts/display_emulator.py for SPARK SoC.

Parses cycle-by-cycle simulated VGA signals (hsync, vsync, display_on, r, g, b)
dumped from tb_vga_ctrl.sv or tb_spark_soc_top.sv and renders the live display window.
"""
import pygame
import sys
import os

VGA_SIGNALS_FILE = sys.argv[1] if len(sys.argv) > 1 else '../sim/vga_signals.txt'
SCREEN_WIDTH = 640
SCREEN_HEIGHT = 480
PIXEL_SCALE = 1
WINDOW_TITLE = "SPARK VGA Display Emulator"

H_TOTAL = 800
V_TOTAL = 525

def main():
    pygame.init()
    window_size = (SCREEN_WIDTH * PIXEL_SCALE, SCREEN_HEIGHT * PIXEL_SCALE)
    screen = pygame.display.set_mode(window_size)
    pygame.display.set_caption(WINDOW_TITLE)

    display_surface = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT))
    display_surface.fill((0, 0, 0))

    if not os.path.exists(VGA_SIGNALS_FILE):
        print(f"Error: Signal file '{VGA_SIGNALS_FILE}' not found.")
        print("Run the QuestaSim simulation to generate it first.")
        sys.exit(1)

    print(f"Loading VGA signals from '{VGA_SIGNALS_FILE}'...")
    with open(VGA_SIGNALS_FILE, 'r') as f:
        vga_signals = f.readlines()

    print(f"Loaded {len(vga_signals)} clock cycles. Rendering display...")

    running = True
    x, y = 0, 0
    frame_count = 0

    for line in vga_signals:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit()
                sys.exit(0)

        parts = line.strip().split()
        if len(parts) != 6:
            continue

        hsync, vsync, display_on, r, g, b = [int(p) for p in parts]

        if display_on and 0 <= x < SCREEN_WIDTH and 0 <= y < SCREEN_HEIGHT:
            color = (r * 17, g * 17, b * 17) # 4-bit to 8-bit scale
            display_surface.set_at((x, y), color)

        x += 1
        if x >= H_TOTAL:
            x = 0
            y += 1
            if y >= V_TOTAL:
                y = 0
                frame_count += 1
                scaled = pygame.transform.scale(display_surface, window_size)
                screen.blit(scaled, (0, 0))
                pygame.display.flip()

    print(f"Rendered {frame_count} frames. Displaying window (close window to exit)...")
    scaled = pygame.transform.scale(display_surface, window_size)
    screen.blit(scaled, (0, 0))
    pygame.display.flip()

    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False

    pygame.quit()

if __name__ == '__main__':
    main()
