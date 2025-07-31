FORMAT = ihex
BUILD = build

MEM_DUMP_SRC = ../../driver/serial_xr88c92.asm	../../driver/led.asm ../../driver/mmu.asm ../../bios/memory.asm mem_dump.asm ../../bios/init.asm

MEM_DUMP_OBJ = $(MEM_DUMP_SRC:.asm=.o)
MEM_DUMP_BIN = $(BUILD)/mem_dump.$(FORMAT)
MEM_DUMP_INC = ../../driver/

all: mem_dump

build: 
	mkdir -p $(BUILD)

mem_dump: build 
	lwasm -3 -f $(FORMAT) -I $(MEM_DUMP_INC) -o $(MEM_DUMP_BIN) $(MEM_DUMP_SRC) 

clean:
	rm -f $(MEM_DUMP_OBJ) $(MEM_DUMP_BIN)