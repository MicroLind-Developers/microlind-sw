FORMAT = ihex
BUILD = build

BLINK_SRC = blink.asm
BLINK_OBJ = $(BLINK_SRC:.asm=.o)
BLINK_BIN = $(BUILD)/blink.$(FORMAT)

all: blink

build: 
	mkdir -p $(BUILD)

blink: build 
	lwasm -3 -f $(FORMAT) -o $(BLINK_BIN) $(BLINK_SRC) 

clean:
	rm -f $(BLINK_OBJ) $(BLINK_BIN)