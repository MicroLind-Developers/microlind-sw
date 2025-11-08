FORMAT = ihex
BUILD = build

BANKING_SRC = ../../bios/init.asm  ../../driver/serial_xr88c92.asm ../../driver/mmu.asm ../../driver/led.asm ../../driver/parallel_6522.asm ../../bios/memory.asm banking.asm
BANKING_OBJ = $(BANKING_SRC:.asm=.o)
BANKING_BIN = $(BUILD)/banking.$(FORMAT)

all: banking

build: 
	mkdir -p $(BUILD)

banking: build 
	lwasm -3 -f $(FORMAT) -o $(BANKING_BIN) $(BANKING_SRC) 

clean:
	rm -f $(BANKING_OBJ) $(BANKING_BIN)