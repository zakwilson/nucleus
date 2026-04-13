CC           := clang
CFLAGS       := -std=c11 -Wall -Wextra -Wpedantic -O0 -g
LLVM_CFLAGS  := $(shell llvm-config --cflags 2>/dev/null)
LLVM_LDFLAGS := $(shell llvm-config --ldflags 2>/dev/null)
LLVM_LIBS    := $(shell llvm-config --libs orcjit core irreader 2>/dev/null)
BUILD        := build
BOOT         := $(BUILD)/nucleusc-boot
BIN          := $(BUILD)/nucleusc

# Bootstrap: C compiler builds the Nucleus compiler from source
$(BOOT): src/nucleusc.c | $(BUILD)
	$(CC) $(CFLAGS) $(LLVM_CFLAGS) -rdynamic -o $@ $< $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl

$(BIN): $(BOOT) src/nucleusc.nuc | $(BUILD)
	$(BOOT) src/nucleusc.nuc > $(BUILD)/nucleusc.ll
	clang $(BUILD)/nucleusc.ll $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o $@

$(BUILD) $(BUILD)/out:
	mkdir -p $@

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

clean:
	rm -rf $(BUILD)

.PHONY: test clean bootstrap
