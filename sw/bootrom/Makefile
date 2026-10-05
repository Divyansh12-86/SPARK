CROSS_COMPILE ?= /home/divyansh/.platformio/packages/toolchain-riscv32-esp/bin/riscv32-esp-elf-
CC = $(CROSS_COMPILE)gcc
AS = $(CROSS_COMPILE)as
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
PYTHON = python3

CFLAGS = -march=rv32i -mabi=ilp32 -nostdlib -fno-builtin -O2

all: bootrom.hex

bootrom.elf: bootrom.s bootrom.ld
	$(CC) $(CFLAGS) -T bootrom.ld -o bootrom.elf bootrom.s

bootrom.bin: bootrom.elf
	$(OBJCOPY) -O binary bootrom.elf bootrom.bin

bootrom.hex: bootrom.bin ../bin2hex.py
	$(PYTHON) ../bin2hex.py bootrom.bin bootrom.hex

clean:
	rm -f bootrom.elf bootrom.bin bootrom.hex
