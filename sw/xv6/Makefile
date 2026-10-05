CROSS_COMPILE ?= /home/divyansh/.platformio/packages/toolchain-riscv32-esp/bin/riscv32-esp-elf-
CC = $(CROSS_COMPILE)gcc
AS = $(CROSS_COMPILE)as
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
PYTHON = python3

CFLAGS = -Wall -Werror -O2 -fno-omit-frame-pointer \
         -march=rv32i_zicsr -mabi=ilp32 -mcmodel=medany \
         -ffreestanding -fno-common -nostdlib -mno-relax \
         -I.

OBJS = \
  entry.o \
  start.o \
  main.o \
  uart.o \
  printf.o \
  kalloc.o \
  vm.o \
  proc.o \
  swtch.o \
  trampoline.o \
  trap.o \
  kernelvec.o \
  ramdisk.o \
  bio.o \
  fs.o \
  plic.o \
  sh.o \
  string.o \
  div.o \
  vga_console.o \
  gui_gfx.o \
  gui_wm.o \
  gui_apps.o

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.s
	$(CC) $(CFLAGS) -c -o $@ $<

all: kernel.hex fs.hex

kernel.elf: $(OBJS) kernel.ld
	$(LD) -T kernel.ld -o kernel.elf $(OBJS)
	$(OBJDUMP) -S kernel.elf > kernel.asm
	$(OBJDUMP) -t kernel.elf | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernel.sym

kernel.bin: kernel.elf
	$(OBJCOPY) -O binary kernel.elf kernel.bin

kernel.hex: kernel.bin ../bin2hex.py
	$(PYTHON) ../bin2hex.py kernel.bin kernel.hex 65536

fs.img: mkfs.py
	$(PYTHON) mkfs.py fs.img

fs.hex: fs.img ../bin2hex.py
	$(PYTHON) ../bin2hex.py fs.img fs.hex

clean:
	rm -f *.o *.elf *.bin *.hex *.asm *.sym fs.img
