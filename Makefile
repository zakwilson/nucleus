CC           := clang
CFLAGS       := -std=c11 -Wall -Wextra -Wpedantic -O0 -g
LLVM_CFLAGS  := $(shell llvm-config --cflags 2>/dev/null)
LLVM_LDFLAGS := $(shell llvm-config --ldflags 2>/dev/null)
LLVM_LIBS    := $(shell llvm-config --libs orcjit core irreader 2>/dev/null)
BUILD        := build
BIN          := $(BUILD)/nucleusc

# Bootstrap binary: use the committed pre-built binary.
# Auto-rebuilt from boot/nucleusc.ll if it can't execute (e.g. LLVM version mismatch).
BOOT         := bin/nucleusc

# REPL shim (setjmp/longjmp wrapper)
REPL_SHIM_O  := $(BUILD)/repl_shim.o

$(BIN): src/nucleusc.nuc src/repl.nuc src/cheader.nuc $(REPL_SHIM_O) | $(BUILD) ensure-boot
	$(BOOT) src/nucleusc.nuc > $(BUILD)/nucleusc.ll
	clang $(BUILD)/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o $@

$(REPL_SHIM_O): src/repl_shim.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD) $(BUILD)/out:
	mkdir -p $@

# Auto-rebuild boot binary if it can't run (wrong LLVM shared lib, etc.)
ensure-boot: $(REPL_SHIM_O) | $(BUILD)
	@if ! $(BOOT) /dev/null >/dev/null 2>&1; then \
		echo "bin/nucleusc: cannot execute, rebuilding from boot/nucleusc.ll ..."; \
		clang boot/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o $(BOOT); \
	fi

# Force-rebuild the bootstrap binary from the committed IR (boot/nucleusc.ll).
boot-binary: $(REPL_SHIM_O) | $(BUILD)
	clang boot/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o bin/nucleusc

test: $(BIN)
	./tests/run-tests.sh

bootstrap: $(BIN) | $(BUILD)/out
	@echo "=== Stage 2: self-hosted compiler -> nucleusc.nuc ==="
	$(BIN) src/nucleusc.nuc > $(BUILD)/stage2.ll
	clang $(BUILD)/stage2.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -o $(BUILD)/nucleusc-stage2
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

# ---- Library compilation ----

$(BUILD)/lib:
	mkdir -p $@

# Generate .nuch header from .nuc source
lib/%.nuch: lib/%.nuc $(BIN)
	$(BIN) --emit-nuch $< > $@

# Generate C header from .nuc source
lib/%.h: lib/%.nuc $(BIN)
	$(BIN) --emit-cheader $< > $@

# Compile library .nuc to .ll
$(BUILD)/lib/%.ll: lib/%.nuc $(BIN) | $(BUILD)/lib
	$(BIN) $< > $@

# Compile .ll to position-independent .o
$(BUILD)/lib/%.o: $(BUILD)/lib/%.ll
	llc -filetype=obj -relocation-model=pic $< -o $@

# Build all library headers
LIB_NUCS  := $(wildcard lib/*.nuc)
LIB_NUCHS := $(LIB_NUCS:.nuc=.nuch)
LIB_HS    := $(LIB_NUCS:.nuc=.h)
LIB_LLS   := $(patsubst lib/%.nuc,$(BUILD)/lib/%.ll,$(LIB_NUCS))
LIB_OBJS  := $(patsubst lib/%.nuc,$(BUILD)/lib/%.o,$(LIB_NUCS))

lib-headers: $(LIB_NUCHS)
lib-cheaders: $(LIB_HS)
lib-objs: $(LIB_OBJS)

# Build shared library from all library .o files
$(BUILD)/lib/libnucleus.so: $(LIB_OBJS)
	$(CC) -shared $^ -o $@

lib-so: $(BUILD)/lib/libnucleus.so
lib: lib-headers lib-objs

clean:
	rm -rf $(BUILD)

.PHONY: test clean bootstrap boot-binary update-bootstrap ensure-boot lib-headers lib-cheaders lib-objs lib-so lib
