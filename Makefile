CC      := gcc
CFLAGS  := -std=c11 -Wall -Wextra -Wpedantic -O0 -g
BUILD   := build
BIN     := $(BUILD)/nucleusc

$(BIN): src/nucleusc.c | $(BUILD)
	$(CC) $(CFLAGS) -o $@ $<

$(BUILD):
	mkdir -p $(BUILD)

test: $(BIN)
	./tests/run-tests.sh

clean:
	rm -rf $(BUILD)

.PHONY: test clean
