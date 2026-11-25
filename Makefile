CROSS   = riscv64-unknown-elf-
CC      = $(CROSS)gcc
OBJCOPY = $(CROSS)objcopy
OBJDUMP = $(CROSS)objdump

CFLAGS  = -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib -Wall -Wextra
LDFLAGS = -T link.ld

all: run

firmware.elf: start.S firmware.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S firmware.c
	$(OBJDUMP) -d -M no-aliases $@ > firmware.dis

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.hex: firmware.bin
	python3 -c 'import sys, struct; data = open(sys.argv[1], "rb").read(); data += b"\x00" * ((4 - len(data) % 4) % 4); print("\n".join(f"{w:08x}" for (w,) in struct.iter_unpack("<I", data)))' $< > $@

sim.vvp: rv32i_cpu.v tb_rv32i.v
	iverilog -g2012 -o $@ rv32i_cpu.v tb_rv32i.v

run: sim.vvp firmware.hex
	vvp sim.vvp +firmware=firmware.hex

trace: sim.vvp firmware.hex
	vvp sim.vvp +firmware=firmware.hex +trace

wave: run
	gtkwave rv32i_wave.vcd wave.gtkw &

.DELETE_ON_ERROR:
.PHONY: all run trace wave
