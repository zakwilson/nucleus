CC           := clang
CFLAGS       := -std=c11 -Wall -Wextra -Wpedantic -O0 -g

# Native link flags for the compiler binary itself.
#
# `-ffast-math` USED to be here and was removed in Stage 15 W2d: on Linux/x86 it
# links crtfastmath.o, which sets FTZ/DAZ in MXCSR for the whole *compiler*
# process. Since W2d the compiler constant-folds float literals to their target
# width with host floating point (`f32-const-ir`, src/nucleusc.nuc), so a
# flush-to-zero process silently folded every denormal literal to 0 —
# `(defvar d:f32 1e-45)` emitted `float 0x0000000000000000` where clang emits
# `float 0x36A0000000000000`. The compiler performs no floating-point work of
# its own, so fast-math bought nothing and cost correctness. Do not add it back;
# a compiler must evaluate constants under strict IEEE semantics.
NATIVE_OPT   :=-O3

# LLVM detection: try llvm-config, then versioned names (Alpine: llvm21-config,
# Debian: llvm-config-19). Fall back to -lLLVM monolithic shared lib if no
# llvm-config is found (Alpine's llvm21 package may not ship llvm-config on PATH).
LLVM_CONFIG  := $(shell which llvm-config 2>/dev/null || \
                          which llvm-config-21 2>/dev/null || \
                          which llvm-config-20 2>/dev/null || \
                          which llvm-config-19 2>/dev/null || \
                          ls /usr/lib/llvm21/bin/llvm-config 2>/dev/null || \
                          ls /usr/lib/llvm19/bin/llvm-config 2>/dev/null || \
                          echo "")
ifneq ($(LLVM_CONFIG),)
  LLVM_CFLAGS  := $(shell $(LLVM_CONFIG) --cflags 2>/dev/null)
  LLVM_LDFLAGS := $(shell $(LLVM_CONFIG) --link-shared --ldflags 2>/dev/null)
  LLVM_LIBS    := $(shell $(LLVM_CONFIG) --link-shared --libs orcjit core irreader 2>/dev/null)
  LLVM_SYSLIBS := $(shell $(LLVM_CONFIG) --link-shared --system-libs 2>/dev/null)
  # If --link-shared produced nothing (static-only install), fall back to static libs.
  ifeq ($(LLVM_LIBS),)
    LLVM_LDFLAGS := $(shell $(LLVM_CONFIG) --ldflags 2>/dev/null)
    LLVM_LIBS    := $(shell $(LLVM_CONFIG) --libs orcjit core irreader 2>/dev/null)
    LLVM_SYSLIBS := $(shell $(LLVM_CONFIG) --system-libs 2>/dev/null)
  endif
  # If both shared and static produced nothing, fall back to monolithic shared lib.
  ifeq ($(LLVM_LIBS),)
    LLVM_LDFLAGS :=
    LLVM_LIBS    := -lLLVM
    LLVM_SYSLIBS :=
  endif
else
  # No llvm-config found — assume monolithic shared lib (Alpine, some distros).
  LLVM_CFLAGS  :=
  LLVM_LDFLAGS :=
  LLVM_LIBS    := -lLLVM
  LLVM_SYSLIBS :=
endif
$(info LLVM: config=$(LLVM_CONFIG) ldflags=$(LLVM_LDFLAGS) libs=$(LLVM_LIBS) syslibs=$(LLVM_SYSLIBS))
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
# compiler's own. src/reader.nuc was the gap that previously let reader edits
# go unrebuilt; lib/vector.nuc, lib/hash.nuc, lib/hashset.nuc,
# lib/hashmap.nuc, lib/list.nuc, lib/iterator.nuc, lib/allocator.nuc,
# lib/coll.nuc, and lib/seq.nuc (the full transitive closure pulled in via
# src/generics.nuc's `(import-use vector)`, src/nucleusc.nuc's `(import-use
# vector/hash/hashset)`, and src/type-mangle.nuc / src/nuch.nuc's
# `(import-use list/hashmap)`) were the same class of gap, found during
# LW-5 batch 2 (stage14): editing any of them changed `build/nucleusc.ll`
# but incremental `make` didn't detect it, silently reusing a stale binary.
COMPILER_DEPS := src/nucleusc.nuc src/compiler-types.nuc src/type-utils.nuc src/type-mangle.nuc src/scope.nuc src/abi.nuc src/union-registry.nuc src/generics.nuc src/union-emit.nuc src/repl.nuc src/cheader.nuc src/nuch.nuc \
                 src/format.nuc \
                 lib/prelude.nuc lib/macros.nuc lib/node.nuc lib/arena.nuc \
                 lib/error.nuc src/reader.nuc \
                 lib/vector.nuc lib/hash.nuc lib/hashset.nuc lib/hashmap.nuc \
                 lib/list.nuc lib/iterator.nuc lib/allocator.nuc lib/coll.nuc \
                 lib/seq.nuc

$(BIN): $(COMPILER_DEPS) $(REPL_SHIM_O) $(BUILD)/llvm-stamp | $(BUILD) ensure-boot
	$(BOOT) --emit-llvm src/nucleusc.nuc > $(BUILD)/nucleusc.ll
	clang $(BUILD)/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) $(LLVM_SYSLIBS) -ldl -rdynamic $(NATIVE_OPT) -o $@

# Content stamp of the linked LLVM version. A build/nucleusc carried across an
# LLVM switch (e.g. a build dir shared between host and container) is linked
# against a libLLVM the loader can't find; timestamps alone would leave it
# stale-but-"up-to-date". The stamp only changes when the version string does,
# so it forces exactly one relink per toolchain change.
LLVM_VERSION := $(if $(LLVM_CONFIG),$(shell $(LLVM_CONFIG) --version 2>/dev/null),unknown)
$(BUILD)/llvm-stamp: FORCE | $(BUILD)
	@echo "$(LLVM_VERSION)" | cmp -s - $@ 2>/dev/null || echo "$(LLVM_VERSION)" > $@
FORCE:

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
		clang boot/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) $(LLVM_SYSLIBS) -ldl -rdynamic $(NATIVE_OPT) -o $(BOOT); \
	fi

# Force-rebuild the bootstrap binary from the committed IR (boot/nucleusc.ll).
boot-binary: $(REPL_SHIM_O) | $(BUILD)
	clang boot/nucleusc.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) $(LLVM_SYSLIBS) -ldl -rdynamic $(NATIVE_OPT) -o bin/nucleusc

test: $(BIN)
	@rm -rf $(BUILD)/out
	./tests/run-tests.sh

# Struct-ABI interop acceptance test (Phase C gate). Not part of `make test`
# until aggregate ABI lowering lands; see design/stage8/platform.md.
abi-test: $(BIN)
	NUCLEUSC=$(BIN) ./tests/run-abi-test.sh

# Struct-layout verification (Phase E gate): sizeof/offsetof vs the platform
# C compiler over the question-14 corpus. See design/stage8/platform.md.
layout-test: $(BIN)
	NUCLEUSC=$(BIN) ./tests/run-layout-test.sh

# AVR cross-compilation acceptance test (Stage 14 AVR-8 gate): compile+link
# the four AVR examples, assert avr-size flash/RAM budgets, and run the UART
# example under simavr. Not part of `make test`; see design/stage14/avr-
# targets.md and tests/run-avr-test.sh's header comment.
avr-test: $(BIN)
	NUCLEUSC=$(BIN) ./tests/run-avr-test.sh

# RISC-V compilation acceptance test (Stage 14 RV-2 gate): compile+link each
# example via the real compile-and-link path and run it, diffing
# tests/expected/. Two lanes keyed on `uname -m`: cross (riscv64-linux-gnu-gcc
# link driver, run under qemu-riscv64) or native riscv64 (clang, run directly).
# Not part of `make test`; see design/stage14/riscv-linux.md §5 and
# tests/run-riscv-test.sh's header comment.
riscv-test: $(BIN)
	NUCLEUSC=$(BIN) ./tests/run-riscv-test.sh

# RISC-V struct-ABI interop acceptance test (Stage 14 RV-3 gate): the three-
# direction aggregate-ABI interop (Nucleus<->C, Nucleus<->Nucleus) built for
# riscv64 — cross-compiled and run under qemu-riscv64, or built with clang and
# run directly on a native riscv64 host. Not part of `make test`/`make abi-test`;
# see design/stage14/riscv-linux.md §5 and tests/run-riscv-abi-test.sh's header.
riscv-abi-test: $(BIN)
	NUCLEUSC=$(BIN) ./tests/run-riscv-abi-test.sh

# Regenerate docs/stdlib.md's availability tables by probing $(BIN) (Stage 15
# W4e, design/stage15-stress-test/diagnostics.md §W4e) -- the doc is generated,
# not hand-curated, since the "no import needed" set is host/libc-dependent
# (see the doc's own framing paragraph and context/build.md's musl note). The
# regenerated-vs-committed check runs as part of `make test` (the
# `stdlib-table-generated` unit in tests/run-tests.sh); this target is the
# convenience entry point for actually updating the doc after a toolchain/libc
# change.
gen-stdlib-table: $(BIN)
	python3 scripts/gen-stdlib-table.py

bootstrap: $(BIN) | $(BUILD)/out
	@echo "=== Stage 2: self-hosted compiler -> nucleusc.nuc ==="
	$(BIN) --emit-llvm src/nucleusc.nuc > $(BUILD)/stage2.ll
	clang $(BUILD)/stage2.ll $(REPL_SHIM_O) $(LLVM_LDFLAGS) $(LLVM_LIBS) $(LLVM_SYSLIBS) -ldl -rdynamic $(NATIVE_OPT) -o $(BUILD)/nucleusc-stage2
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

# Verify the committed lib/*.nuch and lib/*.h still match what this compiler
# emits. They are generated-and-committed, and the build never reads the
# committed copies (the rules above overwrite them), so a change to src/nuch.nuc
# or src/cheader.nuc invalidates them silently. Runs as part of `make test` (the
# `headers-generated` unit in tests/run-tests.sh); this target is the convenience
# entry point. `scripts/check-headers.sh --fix` regenerates -- including
# lib/mapiterlib.nuch, which $(LIB_NUCHS) cannot reach because its source is
# tests/fixtures/mapiterlib.nuc.
check-headers: $(BIN)
	NUCLEUSC=$(BIN) ./scripts/check-headers.sh

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

.PHONY: test abi-test layout-test avr-test riscv-test riscv-abi-test gen-stdlib-table clean bootstrap boot-binary update-bootstrap windows-boot ensure-boot lib-headers lib-cheaders check-headers lib-objs lib-so lib install uninstall
