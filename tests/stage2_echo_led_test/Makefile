FORMAT = ihex
BUILD = build

# ECHO_TEST_SRC = ../../bios/init.asm ../../driver/serial_xr88c92.asm ../../driver/mmu.asm ../../driver/led.asm ../../driver/parallel_6522.asm ../../driver/irq.asm  echo_led_test.asm
ECHO_TEST_SRC =   echo_led_test.asm ../../driver/serial_xr88c92.asm
ECHO_TEST_OBJ = $(ECHO_TEST_SRC:.asm=.o)
ECHO_TEST_BIN = $(BUILD)/echo_led_test.$(FORMAT)

all: echo_led_test

build: 
	mkdir -p $(BUILD)

echo_led_test: build 
	# lwasm -3 -I ../../driver -f $(FORMAT) -o $(ECHO_TEST_BIN) $(ECHO_TEST_SRC)
	lwasm -3 -f $(FORMAT) -o $(ECHO_TEST_BIN) $(ECHO_TEST_SRC)

clean:
	rm -f $(ECHO_TEST_OBJ) $(ECHO_TEST_BIN)