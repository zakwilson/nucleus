# C-header struct ingestion — landed

## Status: complete for stage 8

Headers consumed via `(include foo)` / `(import "foo.h")` now register their `struct Foo { ... };` and `typedef struct { ... } Bar;` definitions into the Nucleus struct registry. Anonymous inline `struct { ... }` fields are registered as memoized anonymous structs (content-hashed). Pass-by-value C struct parameters in `extern` declarations type correctly.

Exercised by `examples/cheader-struct.nuc` + `tests/expected/cheader-struct.out` + `tests/fixtures/cheader-struct.h`. All 39 tests pass.

## What's in

**`src/cheader.nuc`:**

- `c-parse-type` (extended): when it encounters `struct`, peeks for a `{`. Inline `struct { ... }` and `struct Tag { ... }` are parsed as definitions via `c-parse-struct-body`. Bare `struct Tag` references look up the tag; falls back to `ty-ptr` on miss. `struct Tag *` (pointer) collapses to `ty-ptr` as before.
- `c-parse-struct-body` (new): pre-scans the matching `}` and writes `out-end` *once*, so the caller's position is always correct regardless of which branch the body parser exits through. Per-field loop is flat and bails on any anomaly. Handles function-pointer fields (collapsed to `ptr`); rejects arrays, bitfields, unions, and multi-declarator lines by abandoning the whole struct.
- `c-parse-struct-decl` (new): recognizes top-level `struct Tag { ... };` and `typedef struct [Tag] { ... } Name;`. For typedef, registers an alias `StructDef` under the typedef name sharing the inner shape.
- Dispatch in `emit-c-include`: split branches for `struct` and `typedef` tokens. (The `(or A B)` form also works after the body bug was fixed — the earlier reducer was a symptom of broken position recovery, not an actual `or`/`cond` bug.)

## Bugs fixed during this pass

1. **c-parse-struct-decl "struct" branch never advanced past the keyword.** Previously did `(set! pos pos)`; now `(set! pos te)`. Without this, the parser re-read "struct" as the struct's tag name.
2. **c-parse-struct-body did not robustly set `out-end` on failure.** Restructured to pre-scan the matching `}` at entry and write `out-end` exactly once. Every failure path is now a simple `(return null)` and the caller resumes correctly past the struct body.
3. **Per-field loop deep nesting led to mis-advances.** Flattened the loop body to a sequence of `(when (= done 0) ...)` guards. Setting `bad=1 done=1` cleanly exits without leaking pos.

## Known scope limits (deferred, separate stage-8 items)

- **Unions** — Designer's `defunion` work. C-header parser still abandons the containing struct if a `union { ... }` member appears.
- **Bitfields** — Designer item (deferred to "match C"). Abandon containing struct.
- **Inline arrays as struct field type** — Nucleus has no `(array T N)` type kind. Abandon containing struct if a `[N]` field appears. Adding it is a separate stage-8 task; unblocks all libc structs with fixed-size buffer fields.
- **Function-pointer fields with full signatures** — currently collapsed to `ptr`. Designer item #8 in `types.md`. Use `c-parse-type` recursively once needed.
- **Multi-declarator lines** (`int a, b;`) — abandon. Splitting into multiple fields is mechanical; do when needed.
- **`__attribute__((packed))` and `__attribute__((aligned(N)))`** — Designer's `&attributes` item.

When any of these limitations is hit, the struct is silently registered as opaque — calling code that doesn't use the struct's fields is unaffected. This matches the prior behavior (everything was opaque) and is safer than registering a half-built struct with the wrong layout.

## Files touched

- `src/cheader.nuc` — new functions and dispatch.
- `src/nucleusc.nuc` — none in this sub-task.
- `examples/cheader-struct.nuc` — new test.
- `tests/expected/cheader-struct.out` — new.
- `tests/fixtures/cheader-struct.h` — new fixture (named struct, typedef struct, nested-by-value, anonymous inline struct).
- `docs/builtins.md` — section on C-header struct ingestion.
- `design/stage8/types.md` — marked anonymous + nested as done (covers both Nucleus side and C-header side).
