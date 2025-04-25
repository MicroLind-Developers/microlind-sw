FORMAT = ihex
BUILD = build

BIOS_SRC = ../driver/init.asm ../driver/serial_xr88c92.asm ../driver/parallel_6522.asm ../driver/mmu.asm ../driver/led.asm wozmon6309.asm
BIOS_OBJ = $(BIOS_SRC:.asm=.o)
BIOS_BIN = $(BUILD)/bios.$(FORMAT)

all: bios

build: 
	mkdir -p $(BUILD)

bios: build 
	lwasm -3 -f $(FORMAT) -o $(BIOS_BIN) $(BIOS_SRC) 

clean:
	rm -f $(BIOS_OBJ) $(BIOS_BIN)