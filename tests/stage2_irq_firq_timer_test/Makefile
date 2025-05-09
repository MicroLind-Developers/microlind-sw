FORMAT = ihex
BUILD = build

TIMER_TEST_SRC = ../../bios/init.asm ../../driver/serial_xr88c92.asm ../../driver/mmu.asm ../../driver/led.asm ../../driver/parallel_6522.asm ../../driver/irq.asm  timer_test.asm
TIMER_TEST_OBJ = $(TIMER_TEST_SRC:.asm=.o)
TIMER_TEST_BIN = $(BUILD)/timer_test.$(FORMAT)

all: timer_test

build: 
	mkdir -p $(BUILD)

timer_test: build 
	lwasm -3 -I ../../driver -f $(FORMAT) -o $(TIMER_TEST_BIN) $(TIMER_TEST_SRC) 

clean:
	rm -f $(TIMER_TEST_OBJ) $(TIMER_TEST_BIN)