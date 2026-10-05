// ============================================================================
// File:        verilator_main.cpp
// Project:     SPARK — SystemVerilog Processor Architecture for RISC-V Kernel-boot
// Description: Interactive Full-System Co-Simulation GUI & Hardware Virtual Platform.
//
//              Features:
//                1. Cycle-accurate dual-clock driving (100MHz CPU, 25MHz VGA)
//                2. Interactive SDL2 Graphical Desktop Window (640x480 scaled VGA)
//                3. Live Keyboard input routing into hardware 16550 UART RX
//                4. Live Mouse tracking (X, Y, buttons) into hardware registers
//                5. Non-blocking Terminal console I/O
//                6. Built-in TCP Bridge (Port 9999) for interactive Python automation
// ============================================================================

#include <iostream>
#include <iomanip>
#include <fstream>
#include <memory>
#include <chrono>
#include <queue>
#include <vector>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#include <algorithm>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "Vspark_soc_top.h"
#include "Vspark_soc_top___024root.h"
#include "verilated.h"

#if __has_include(<SDL.h>)
  #include <SDL.h>
  #define HAVE_SDL2 1
#elif __has_include(<SDL2/SDL.h>)
  #include <SDL2/SDL.h>
  #define HAVE_SDL2 1
#else
  #define HAVE_SDL2 0
#endif

// Terminal management
static struct termios orig_termios;
static bool term_raw_enabled = false;

void reset_terminal_mode() {
    if (term_raw_enabled) {
        tcsetattr(0, TCSANOW, &orig_termios);
        term_raw_enabled = false;
    }
}

void set_conio_terminal_mode() {
    if (!isatty(0)) return;
    tcgetattr(0, &orig_termios);
    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(0, TCSANOW, &raw);
    fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK);
    term_raw_enabled = true;
    atexit(reset_terminal_mode);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto top = std::make_unique<Vspark_soc_top>();

    std::cout << "===============================================================" << std::endl;
    std::cout << "  SPARK RISC-V SoC: Interactive Desktop GUI & OS Platform     " << std::endl;
    std::cout << "===============================================================" << std::endl;

    // Simulation configuration (0 = run indefinitely until GUI closed or Ctrl+C)
    uint64_t max_cycles = 0; 
    bool force_headless = false;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--headless" || arg == "--nogui") {
            force_headless = true;
        } else if (arg == "--cycles" && i + 1 < argc) {
            max_cycles = std::stoull(argv[++i]);
        } else if (arg == "--interactive") {
            max_cycles = 0;
        } else if (isdigit(arg[0])) {
            max_cycles = std::stoull(arg);
        }
    }

    // ------------------------------------------------------------------------
    // SDL2 Display & GUI Initialization
    // ------------------------------------------------------------------------
    bool gui_enabled = false;
#if HAVE_SDL2
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    SDL_Texture* texture = nullptr;

    const char* display_env = getenv("DISPLAY");
    const char* wayland_env = getenv("WAYLAND_DISPLAY");

    if (!force_headless && (display_env != nullptr || wayland_env != nullptr)) {
        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) == 0) {
            window = SDL_CreateWindow(
                "SPARK RISC-V SoC — MIT xv6 Live Operating System",
                SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                640, 480,
                SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
            );
            if (window) {
                renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
                if (!renderer) {
                    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
                }
                if (!renderer) {
                    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
                }
                if (renderer) {
                    texture = SDL_CreateTexture(
                        renderer,
                        SDL_PIXELFORMAT_ARGB8888,
                        SDL_TEXTUREACCESS_STREAMING,
                        320, 240
                    );
                    if (texture) {
                        gui_enabled = true;
                        std::cout << "[GUI] SDL2 Interactive Window initialized (640x480 Native VGA)." << std::endl;
                        SDL_StartTextInput();
                    }
                }
            }
        }
    }
#endif

    if (!gui_enabled) {
        std::cout << "[INFO] Running in high-speed terminal mode." << std::endl;
    }

    // ------------------------------------------------------------------------
    // TCP Bridge Initialization (Port 9999 for Python automation)
    // ------------------------------------------------------------------------
    int server_fd = -1;
    std::vector<int> client_sockets;

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd >= 0) {
        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        fcntl(server_fd, F_SETFL, fcntl(server_fd, F_GETFL) | O_NONBLOCK);

        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        address.sin_port = htons(9999);

        if (bind(server_fd, (struct sockaddr*)&address, sizeof(address)) == 0) {
            if (listen(server_fd, 4) == 0) {
                std::cout << "[IPC] Python Interactive Bridge active on localhost:9999" << std::endl;
            }
        }
    }

    // Setup terminal raw mode for non-blocking stdin
    set_conio_terminal_mode();

    // ------------------------------------------------------------------------
    // Hardware Reset Sequence
    // ------------------------------------------------------------------------
    top->rst_n     = 0;
    top->clk       = 0;
    top->pixel_clk = 0;
    top->uart_rx   = 1;
    top->mouse_x   = 160;
    top->mouse_y   = 120;
    top->mouse_btn = 0;

    for (int i = 0; i < 30; i++) {
        top->clk = !top->clk;
        if (i % 4 == 0) top->pixel_clk = !top->pixel_clk;
        top->eval();
    }

    top->rst_n = 1;
    std::cout << "[INFO] Hardware Reset de-asserted. xv6 Boot Sequence beginning..." << std::endl;
    std::cout << "[INFO] You can now type directly into this terminal or the GUI window!\n" << std::endl;

    // ------------------------------------------------------------------------
    // State Tracking & Input Queues
    // ------------------------------------------------------------------------
    std::queue<uint8_t> uart_rx_queue;

    // UART RX Serializer state machine (Host -> SoC)
    const int BAUD_DIV = 16;
    enum UartTxFsm { TX_IDLE, TX_START, TX_BITS, TX_STOP } fsm_rx_to_soc = TX_IDLE;
    int fsm_rx_clk_cnt = 0;
    int fsm_rx_bit_idx = 0;
    uint8_t fsm_rx_cur_byte = 0;

    // UART TX Deserializer state machine (SoC -> Host)
    enum UartRxFsm { RX_IDLE, RX_START, RX_BITS, RX_STOP } fsm_tx_from_soc = RX_IDLE;
    int fsm_tx_clk_cnt = 0;
    int fsm_tx_bit_idx = 0;
    uint8_t fsm_tx_cur_byte = 0;
    int prev_tx = 1;

    // Framebuffer pixel buffer
    uint32_t fb_pixels[320 * 240];
    int cur_mouse_x = 160;
    int cur_mouse_y = 120;
    int cur_mouse_btn = 0;

    auto start_time = std::chrono::high_resolution_clock::now();
    auto last_render_time = std::chrono::steady_clock::now();
    uint64_t cycles = 0;
    uint64_t last_vram_write_cycle = 0;
    bool simulation_running = true;

    // ------------------------------------------------------------------------
    // Main Simulation Execution Loop
    // ------------------------------------------------------------------------
    while (!Verilated::gotFinish() && simulation_running && (max_cycles == 0 || cycles < max_cycles)) {
        // Toggle system clock (100MHz)
        top->clk = 0;
        top->eval();
        top->clk = 1;

        // Pixel clock 4x division (25MHz)
        if ((cycles & 3) == 0) {
            top->pixel_clk = !top->pixel_clk;
        }

        top->eval();

        // Track active VRAM writes by SoC to detect compositor busy state
        if (top->rootp->spark_soc_top__DOT__cs_vga) {
            last_vram_write_cycle = cycles;
        }

        // --------------------------------------------------------------------
        // 1. Check Terminal stdin for typed input
        // --------------------------------------------------------------------
        if ((cycles & 0x3FF) == 0) {
            char ch;
            while (read(0, &ch, 1) == 1) {
                if (ch == 3) { // Ctrl+C
                    simulation_running = false;
                    break;
                }
                uart_rx_queue.push((uint8_t)ch);
            }
        }

        // --------------------------------------------------------------------
        // 2. Check Python TCP Bridge for connections & commands
        // --------------------------------------------------------------------
        if (server_fd >= 0 && (cycles & 0x7FF) == 0) {
            sockaddr_in client_addr{};
            socklen_t addrlen = sizeof(client_addr);
            int new_sock = accept(server_fd, (struct sockaddr*)&client_addr, &addrlen);
            if (new_sock >= 0) {
                fcntl(new_sock, F_SETFL, fcntl(new_sock, F_GETFL) | O_NONBLOCK);
                client_sockets.push_back(new_sock);
                std::cout << "\n[IPC] Python client connected!" << std::endl;
            }

            // Receive from clients
            for (auto it = client_sockets.begin(); it != client_sockets.end();) {
                char buf[128];
                ssize_t n = recv(*it, buf, sizeof(buf) - 1, 0);
                if (n > 0) {
                    buf[n] = '\0';
                    // Check for mouse command: "MOUSE <x> <y> <btn>\n"
                    if (strncmp(buf, "MOUSE ", 6) == 0) {
                        int mx = 0, my = 0, mbtn = 0;
                        if (sscanf(buf + 6, "%d %d %d", &mx, &my, &mbtn) == 3) {
                            cur_mouse_x = std::clamp(mx, 0, 319);
                            cur_mouse_y = std::clamp(my, 0, 239);
                            cur_mouse_btn = mbtn;
                        }
                    } else {
                        // Regular text keystrokes
                        for (int k = 0; k < n; k++) {
                            uart_rx_queue.push((uint8_t)buf[k]);
                        }
                    }
                    ++it;
                } else if (n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK)) {
                    close(*it);
                    it = client_sockets.erase(it);
                } else {
                    ++it;
                }
            }
        }

        // --------------------------------------------------------------------
        // 3. SDL2 Event Handling & Display Refresh (~60 FPS)
        // --------------------------------------------------------------------
#if HAVE_SDL2
        if (gui_enabled) {
            // Poll SDL events every 512 cycles for ultra-responsive typing & mouse motion
            if ((cycles & 0x1FF) == 0) {
                SDL_Event event;
                while (SDL_PollEvent(&event)) {
                    if (event.type == SDL_QUIT) {
                        simulation_running = false;
                    } else if (event.type == SDL_KEYDOWN) {
                        SDL_Keycode sym = event.key.keysym.sym;
                        if (sym == SDLK_RETURN || sym == SDLK_KP_ENTER) {
                            uart_rx_queue.push('\n');
                        } else if (sym == SDLK_BACKSPACE) {
                            uart_rx_queue.push(0x08);
                        } else if (sym == SDLK_TAB) {
                            uart_rx_queue.push('\t');
                        } else if (sym == SDLK_ESCAPE) {
                            uart_rx_queue.push(0x1b);
                        }
                    } else if (event.type == SDL_TEXTINPUT) {
                        for (int k = 0; event.text.text[k] != '\0'; k++) {
                            uart_rx_queue.push((uint8_t)event.text.text[k]);
                        }
                    } else if (event.type == SDL_MOUSEMOTION) {
                        int win_w = 640, win_h = 480;
                        SDL_GetWindowSize(window, &win_w, &win_h);
                        cur_mouse_x = std::clamp(event.motion.x * 320 / win_w, 0, 319);
                        cur_mouse_y = std::clamp(event.motion.y * 240 / win_h, 0, 239);
                    } else if (event.button.button == SDL_BUTTON_LEFT || event.button.button == SDL_BUTTON_RIGHT || event.button.button == SDL_BUTTON_MIDDLE) {
                        if (event.type == SDL_MOUSEBUTTONDOWN || event.type == SDL_MOUSEBUTTONUP) {
                            bool down = (event.type == SDL_MOUSEBUTTONDOWN);
                            if (event.button.button == SDL_BUTTON_LEFT) {
                                if (down) cur_mouse_btn |= 1; else cur_mouse_btn &= ~1;
                            } else if (event.button.button == SDL_BUTTON_RIGHT) {
                                if (down) cur_mouse_btn |= 2; else cur_mouse_btn &= ~2;
                            } else if (event.button.button == SDL_BUTTON_MIDDLE) {
                                if (down) cur_mouse_btn |= 4; else cur_mouse_btn &= ~4;
                            }
                        }
                    }
                }
            }

            // Display refresh regulated to 60 FPS wall-clock time (every ~16.6ms)
            // If VRAM was modified recently by the CPU, defer presentation until compositor finishes
            if ((cycles & 0xFFF) == 0) {
                auto now = std::chrono::steady_clock::now();
                auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_render_time).count();
                bool vram_busy = (cycles - last_vram_write_cycle) < 40000;
                if (elapsed_ms >= 16 && (!vram_busy || elapsed_ms >= 500)) {
                    last_render_time = now;

                    // Copy VRAM pixels from simulated SoC
                    for (int p = 0; p < 320 * 240; p++) {
                        uint16_t vga_color = top->rootp->spark_soc_top__DOT__u_vga__DOT__vram[p];
                        uint8_t r = ((vga_color >> 8) & 0x0F) * 17;
                        uint8_t g = ((vga_color >> 4) & 0x0F) * 17;
                        uint8_t b = (vga_color & 0x0F) * 17;
                        fb_pixels[p] = (0xFFU << 24) | (r << 16) | (g << 8) | b;
                    }

                    // Draw sleek OS arrow mouse cursor (white with black border)
                    const int cursor_pattern[10][7] = {
                        {1, 0, 0, 0, 0, 0, 0},
                        {1, 1, 0, 0, 0, 0, 0},
                        {1, 2, 1, 0, 0, 0, 0},
                        {1, 2, 2, 1, 0, 0, 0},
                        {1, 2, 2, 2, 1, 0, 0},
                        {1, 2, 2, 2, 2, 1, 0},
                        {1, 2, 2, 1, 1, 1, 1},
                        {1, 2, 1, 0, 0, 0, 0},
                        {1, 1, 0, 0, 0, 0, 0},
                        {1, 0, 0, 0, 0, 0, 0}
                    };
                    for (int cy = 0; cy < 10; cy++) {
                        for (int cx = 0; cx < 7; cx++) {
                            int v = cursor_pattern[cy][cx];
                            if (v == 0) continue;
                            int px = cur_mouse_x + cx;
                            int py = cur_mouse_y + cy;
                            if (px >= 0 && px < 320 && py >= 0 && py < 240) {
                                fb_pixels[py * 320 + px] = (v == 1) ? 0xFF000000 : 0xFFFFFFFF;
                            }
                        }
                    }

                    SDL_UpdateTexture(texture, nullptr, fb_pixels, 320 * sizeof(uint32_t));
                    SDL_RenderCopy(renderer, texture, nullptr, nullptr);
                    SDL_RenderPresent(renderer);
                }
            }
        }
#endif

        // Drive mouse inputs into hardware registers
        top->mouse_x   = cur_mouse_x;
        top->mouse_y   = cur_mouse_y;
        top->mouse_btn = cur_mouse_btn;

        // --------------------------------------------------------------------
        // 4. Hardware UART RX Bit Serializer (Host -> SoC)
        // --------------------------------------------------------------------
        if (fsm_rx_to_soc == TX_IDLE) {
            top->uart_rx = 1;
            if (!uart_rx_queue.empty()) {
                fsm_rx_cur_byte = uart_rx_queue.front();
                uart_rx_queue.pop();
                fsm_rx_to_soc = TX_START;
                fsm_rx_clk_cnt = 0;
            }
        } else if (fsm_rx_to_soc == TX_START) {
            top->uart_rx = 0; // Start bit
            if (++fsm_rx_clk_cnt >= BAUD_DIV) {
                fsm_rx_clk_cnt = 0;
                fsm_rx_to_soc = TX_BITS;
                fsm_rx_bit_idx = 0;
            }
        } else if (fsm_rx_to_soc == TX_BITS) {
            top->uart_rx = (fsm_rx_cur_byte >> fsm_rx_bit_idx) & 1;
            if (++fsm_rx_clk_cnt >= BAUD_DIV) {
                fsm_rx_clk_cnt = 0;
                if (++fsm_rx_bit_idx >= 8) {
                    fsm_rx_to_soc = TX_STOP;
                }
            }
        } else if (fsm_rx_to_soc == TX_STOP) {
            top->uart_rx = 1; // Stop bit + guard band
            if (++fsm_rx_clk_cnt >= BAUD_DIV * 4) {
                fsm_rx_clk_cnt = 0;
                fsm_rx_to_soc = TX_IDLE;
            }
        }

        // --------------------------------------------------------------------
        // 5. Hardware UART TX Deserializer (SoC -> Host Output)
        // --------------------------------------------------------------------
        int tx = top->uart_tx;
        if (fsm_tx_from_soc == RX_IDLE) {
            if (prev_tx == 1 && tx == 0) {
                fsm_tx_from_soc = RX_START;
                fsm_tx_clk_cnt = BAUD_DIV / 2;
            }
        } else if (fsm_tx_from_soc == RX_START) {
            if (++fsm_tx_clk_cnt >= BAUD_DIV) {
                fsm_tx_clk_cnt = 0;
                fsm_tx_from_soc = RX_BITS;
                fsm_tx_bit_idx = 0;
                fsm_tx_cur_byte = 0;
            }
        } else if (fsm_tx_from_soc == RX_BITS) {
            if (++fsm_tx_clk_cnt >= BAUD_DIV) {
                fsm_tx_clk_cnt = 0;
                fsm_tx_cur_byte |= (tx << fsm_tx_bit_idx);
                if (++fsm_tx_bit_idx >= 8) {
                    fsm_tx_from_soc = RX_STOP;
                }
            }
        } else if (fsm_tx_from_soc == RX_STOP) {
            if (++fsm_tx_clk_cnt >= BAUD_DIV) {
                fsm_tx_clk_cnt = 0;
                fsm_tx_from_soc = RX_IDLE;

                // Output to terminal stdout
                std::cout << (char)fsm_tx_cur_byte << std::flush;

                // Broadcast to connected Python clients
                for (int csock : client_sockets) {
                    send(csock, &fsm_tx_cur_byte, 1, MSG_NOSIGNAL);
                }
            }
        }
        prev_tx = tx;

        cycles++;
    }

    // ------------------------------------------------------------------------
    // Cleanup & Summary
    // ------------------------------------------------------------------------
    reset_terminal_mode();

#if HAVE_SDL2
    if (gui_enabled) {
        SDL_DestroyTexture(texture);
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
        SDL_Quit();
    }
#endif

    for (int csock : client_sockets) close(csock);
    if (server_fd >= 0) close(server_fd);

    auto end_time = std::chrono::high_resolution_clock::now();
    double elapsed_sec = std::chrono::duration<double>(end_time - start_time).count();
    double freq_mhz = (double)cycles / (elapsed_sec * 1000000.0);

    std::cout << "\n===============================================================" << std::endl;
    std::cout << "   INTERACTIVE SIMULATION SESSION FINISHED                     " << std::endl;
    std::cout << "===============================================================" << std::endl;
    std::cout << " Executed Cycles : " << cycles << std::endl;
    std::cout << " Wallclock Time  : " << std::fixed << std::setprecision(4) << elapsed_sec << " s" << std::endl;
    std::cout << " Simulation Rate : " << std::fixed << std::setprecision(2) << freq_mhz << " MHz ("
              << (uint64_t)(cycles / elapsed_sec) << " cycles/sec)" << std::endl;
    std::cout << " Final PC        : 0x" << std::hex << std::setw(8) << std::setfill('0') << top->dbg_pc << std::endl;
    std::cout << " PIM Subsystem   : " << (top->pim_busy ? "BUSY" : "READY") << std::endl;
    std::cout << "===============================================================" << std::endl;

    return 0;
}
