FORMAT = ihex
BUILD = build

SERIAL_SRC = init.asm  ../driver/serial_xr88c92.asm ../driver/mmu.asm ../driver/led.asm ../driver/parallel_6522.asm ../driver/irq.asm memory.asm mlbios.asm
SERIAL_OBJ = $(SERIAL_SRC:.asm=.o)
SERIAL_BIN = $(BUILD)/bios.$(FORMAT)

all: serial

build: 
	mkdir -p $(BUILD)

serial: build 
	lwasm -3 -f -I../driver $(FORMAT) -o $(SERIAL_BIN) $(SERIAL_SRC) 

clean:
	rm -f $(SERIAL_OBJ) $(SERIAL_BIN)