# Stage 12 Progress: Namespaces

Detailed task table for the N1–N9 namespace implementation.

| Task | Status | Summary |
|------|--------|---------|
| N1 — Namespace core | Done | `g-current-ns`, `ns`, first-interior-slash resolution, fully-qualified key storage; default `user` namespace uses bare keys (byte-identical to pre-namespace behavior) |
| N2 — Import forms | Done | `import`/`import-use`/`import-only`/`import-prefixed`/`unsafe-import-private`; old `import`/`include` aliases preserved during migration |
| N3 — Private definers | Done | `defn-`/`defvar-` (internal linkage) + `defconst-`/`defenum-`/`defstruct-`/`defunion-`/`defmacro-`/`defprotocol-` (compile-time private); 8 private keyword forms total |
| N4 — IR mangling | Done | `ns__name` mangling scheme, `set-ir-prefix` override, cross-namespace conformance, first IR-diverging task; 105 tests |
| N5 — `export` re-export | Done | Facade-library re-export form; alias entries added to module export table; no new IR emitted |
| N6 — `.nuch` round-trip | Done | Namespace-aware `--emit-cheader`; mangled link names in generated headers |
| N7 — Source migration | Done | All `include` → `import-use` / string-path; `import` semantics flipped to prefix-qualified default; `include` form removed from the language |
| N8 — Compiler split | Done | `nucleusc.nuc` reduced from ~14,477 to ~7,193 lines; 8+ files extracted as byte-identical code motion; 110 tests pass |
| N9 — Docs/examples | Done | `docs/toplevel.md` updated (`export`, private definers); `design/stage12/progress.md` (this file); `examples/namespaces.nuc` |
