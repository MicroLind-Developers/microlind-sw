FORMAT = ihex
BUILD = build

PARALLELL_SRC = ../../bios/init.asm  ../../driver/serial_xr88c92.asm ../../driver/mmu.asm ../../driver/led.asm ../../driver/parallel_6522.asm ../../bios/memory.asm  parallell.asm
PARALLELL_OBJ = $(PARALLELL_SRC:.asm=.o)
PARALLELL_BIN = $(BUILD)/parallell.$(FORMAT)

all: parallell

build: 
	mkdir -p $(BUILD)

parallell: build 
	lwasm -3 -f $(FORMAT) -o $(PARALLELL_BIN) $(PARALLELL_SRC) 

clean:
	rm -f $(PARALLELL_OBJ) $(PARALLELL_BIN)