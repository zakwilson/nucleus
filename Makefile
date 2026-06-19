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

# Source-inlined dependencies of the compiler. `src/nucleusc.nuc` `(import)`s
# these as `.nuc` files, which the importer inlines into the same translation
# unit — so editing any of them changes the compiler's emitted IR and must
# trigger a rebuild. (Header `.nuch` imports like src/llvm.nuch only emit
# `declare`s, resolved at link time.) The prelude chain (prelude -> macros,
# node -> arena) is auto-prepended into every batch compile, including the
# compiler's own. lib/reader.nuc was the gap that previously let reader edits
# go unrebuilt.
COMPILER_DEPS := src/nucleusc.nuc src/repl.nuc src/cheader.nuc src/format.nuc \
                 lib/prelude.nuc lib/macros.nuc lib/node.nuc lib/arena.nuc \
                 lib/error.nuc lib/reader.nuc

$(BIN): $(COMPILER_DEPS) $(REPL_SHIM_O) | $(BUILD) ensure-boot
	$(BOOT) --emit-llvm src/nucleusc.nuc > $(BUILD)/nucleusc.ll
	clang $(BUILD)/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -ffast-math -march=native -O3 -o $@

$(REPL_SHIM_O): src/repl_shim.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD) $(BUILD)/out:
	mkdir -p $@

# Auto-rebuild boot binary if it can't run (wrong LLVM shared lib, etc.)
# Check exec/loader failure only (exit 126/127), not arbitrary compiler errors.
ensure-boot: $(REPL_SHIM_O) | $(BUILD)
	@$(BOOT) --help >/dev/null 2>&1; ec=$$?; \
	if [ $$ec -eq 126 ] || [ $$ec -eq 127 ]; then \
		echo "bin/nucleusc: cannot execute (exit $$ec), rebuilding from boot/nucleusc.ll ..."; \
		clang boot/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -O3 -o $(BOOT); \
	fi

# Force-rebuild the bootstrap binary from the committed IR (boot/nucleusc.ll).
boot-binary: $(REPL_SHIM_O) | $(BUILD)
	clang boot/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -ffast-math -march=native -O3 -o bin/nucleusc

test: $(BIN)
	./tests/run-tests.sh

# Struct-ABI interop acceptance test (Phase C gate). Not part of `make test`
# until aggregate ABI lowering lands; see design/stage8/platform.md.
abi-test: $(BIN)
	NUCLEUSC=$(BIN) ./tests/run-abi-test.sh

# Struct-layout verification (Phase E gate): sizeof/offsetof vs the platform
# C compiler over the question-14 corpus. See design/stage8/platform.md.
layout-test: $(BIN)
	NUCLEUSC=$(BIN) ./tests/run-layout-test.sh

bootstrap: $(BIN) | $(BUILD)/out
	@echo "=== Stage 2: self-hosted compiler -> nucleusc.nuc ==="
	$(BIN) --emit-llvm src/nucleusc.nuc > $(BUILD)/stage2.ll
	clang $(BUILD)/stage2.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) -ldl -rdynamic -ffast-math -march=native -ffast-math -march=native -O3 -o $(BUILD)/nucleusc-stage2
	@echo "=== Fixed-point test ==="
	diff $(BUILD)/nucleusc.ll $(BUILD)/stage2.ll
	@echo "PASS: stage1.ll == stage2.ll"
	@echo "=== Verify stage2 compiles hello.nuc ==="
	$(BUILD)/nucleusc-stage2 examples/hello.nuc -o $(BUILD)/out/hello-bootstrap
	$(BUILD)/out/hello-bootstrap > $(BUILD)/out/hello-bootstrap.out
	diff tests/expected/hello.out $(BUILD)/out/hello-bootstrap.out
	@echo "PASS: bootstrap complete"

# Windows boot IR (Phase F): cross-emitted on this host so a fresh Windows
# checkout can build its first nucleusc.exe via build.ps1 (which has no prior
# compiler to bootstrap from). The compiler's own IR has no aggregate-by-value,
# so these are ABI-clean on Win64. Regenerated alongside the Linux boot IR at
# each milestone (see update-bootstrap) to keep all flavors in lock-step.
WIN_BOOT_IRS := boot/nucleusc-x86_64-windows-gnu.ll boot/nucleusc-x86_64-windows-msvc.ll

windows-boot: $(BIN)
	$(BIN) --target=x86_64-pc-windows-gnu  --emit-llvm src/nucleusc.nuc > boot/nucleusc-x86_64-windows-gnu.ll
	$(BIN) --target=x86_64-pc-windows-msvc --emit-llvm src/nucleusc.nuc > boot/nucleusc-x86_64-windows-msvc.ll
	@echo "DONE: Windows boot IRs updated"

# Update committed bootstrap artifacts from the current self-hosted compiler.
# Only run this at a stable milestone (all tests passing, bootstrap verified).
update-bootstrap: $(BIN)
	@echo "=== Updating bootstrap artifacts ==="
	$(BIN) --emit-llvm src/nucleusc.nuc > boot/nucleusc.ll
	cp $(BIN) bin/nucleusc
	$(MAKE) windows-boot
	@echo "DONE: boot/nucleusc.ll, bin/nucleusc, and Windows boot IRs updated"

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
	$(BIN) --emit-llvm $< > $@

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

# ---- Install ----
#
# Installs the compiler binary plus the lib/ source files needed at import
# time (macros, prelude, etc.). The compiler searches for imports in:
#   1. directory of current source file
#   2. ./lib relative to cwd
#   3. -I paths
#   4. $NUCLEUS_LIB
#   5. /usr/local/share/nucleus/lib   (compiled-in default)
#
# So a default-prefix install just works; for a custom PREFIX, set
# NUCLEUS_LIB=$(PREFIX)/share/nucleus/lib in the environment.

PREFIX  ?= /usr/local
DESTDIR ?=
BINDIR  := $(DESTDIR)$(PREFIX)/bin
LIBDIR  := $(DESTDIR)$(PREFIX)/share/nucleus/lib

install: $(BIN)
	install -d $(BINDIR) $(LIBDIR)
	install -m 755 $(BIN) $(BINDIR)/nucleusc
	install -m 644 lib/*.nuc $(LIBDIR)/
	@echo "Installed nucleusc to $(BINDIR)/nucleusc"
	@echo "Installed lib files to $(LIBDIR)/"
	@if [ "$(PREFIX)" != "/usr/local" ]; then \
		echo "Note: PREFIX != /usr/local — set NUCLEUS_LIB=$(PREFIX)/share/nucleus/lib"; \
	fi

uninstall:
	rm -f $(BINDIR)/nucleusc
	rm -rf $(DESTDIR)$(PREFIX)/share/nucleus

.PHONY: test abi-test layout-test clean bootstrap boot-binary update-bootstrap windows-boot ensure-boot lib-headers lib-cheaders lib-objs lib-so lib install uninstall
