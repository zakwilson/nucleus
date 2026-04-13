CC           := clang
CFLAGS       := -std=c11 -Wall -Wextra -Wpedantic -O0 -g
LLVM_CFLAGS  := $(shell llvm-config --cflags 2>/dev/null)
LLVM_LDFLAGS := $(shell llvm-config --ldflags 2>/dev/null)
LLVM_LIBS    := $(shell llvm-config --libs orcjit core irreader 2>/dev/null)
BUILD        := build
BIN          := $(BUILD)/nucleusc

# Bootstrap binary: use the committed pre-built binary.
# To rebuild it from the committed IR:  make boot-binary
BOOT         := bin/nucleusc

$(BIN): $(BOOT) src/nucleusc.nuc | $(BUILD)
	$(BOOT) src/nucleusc.nuc > $(BUILD)/nucleusc.ll
	clang $(BUILD)/nucleusc.ll $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o $@

$(BUILD) $(BUILD)/out:
	mkdir -p $@

# Rebuild the bootstrap binary from the committed IR (boot/nucleusc.ll).
# Use this if bin/nucleusc is missing or stale on a clean checkout.
boot-binary: | $(BUILD)
	clang boot/nucleusc.ll $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o bin/nucleusc

test: $(BIN)
	./tests/run-tests.sh

bootstrap: $(BIN) | $(BUILD)/out
	@echo "=== Stage 2: self-hosted compiler -> nucleusc.nuc ==="
	$(BIN) src/nucleusc.nuc > $(BUILD)/stage2.ll
	clang $(BUILD)/stage2.ll $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o $(BUILD)/nucleusc-stage2
	@echo "=== Fixed-point test ==="
	diff $(BUILD)/nucleusc.ll $(BUILD)/stage2.ll
	@echo "PASS: stage1.ll == stage2.ll"
	@echo "=== Verify stage2 compiles hello.nuc ==="
	$(BUILD)/nucleusc-stage2 examples/hello.nuc > $(BUILD)/out/hello-bootstrap.ll
	clang $(BUILD)/out/hello-bootstrap.ll -o $(BUILD)/out/hello-bootstrap
	$(BUILD)/out/hello-bootstrap > $(BUILD)/out/hello-bootstrap.out
	diff tests/expected/hello.out $(BUILD)/out/hello-bootstrap.out
	@echo "PASS: bootstrap complete"

# Update committed bootstrap artifacts from the current self-hosted compiler.
# Only run this at a stable milestone (all tests passing, bootstrap verified).
update-bootstrap: $(BIN)
	@echo "=== Updating bootstrap artifacts ==="
	$(BIN) src/nucleusc.nuc > boot/nucleusc.ll
	cp $(BIN) bin/nucleusc
	@echo "DONE: boot/nucleusc.ll and bin/nucleusc updated"

clean:
	rm -rf $(BUILD)

.PHONY: test clean bootstrap boot-binary update-bootstrap
