FORMAT = srec
BUILD = build

APP_ORIGIN = 0xEF00
APP_DATA = 0xC000

TEST_SRC = 	./main.c
			
TEST_BIN = $(BUILD)/test.$(FORMAT)
TEST_HEADER = ../../include/

build: 
	mkdir -p $(BUILD)

serial: build
	cmoc -I $(TEST_HEADER) --$(FORMAT) -o $(TEST_BIN) --org=$(APP_ORIGIN) --data=$(APP_DATA) -i $(TEST_SRC)  

clean:
	rm -f $(TEST_BIN)