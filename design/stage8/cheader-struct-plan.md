# C-header struct ingestion — follow-up plan

## State after this pass

**Live in `src/cheader.nuc`:**
- `c-parse-type` extended (cheader.nuc:184ff). When it encounters `struct`:
  - `*`-pointer to a struct: returns `ty-ptr` (preserved behavior).
  - Inline anonymous `struct { ... }`: parses body via `c-parse-struct-body`, returns a `TY-STRUCT` of the memoized anonymous `StructDef`.
  - Inline tagged `struct Tag { ... }`: same, registered by tag.
  - Bare `struct Tag` (no body): looks up the tag; falls back to `ty-ptr` on miss.
- `c-parse-struct-body` (defined just after `c-parse-type`): parses `{ ... }` field list. Skips bitfields, arrays, unions, function-pointer-typed fields (recorded as `ptr`). Registers anonymous bodies via `lookup-or-make-anon-struct`; tagged bodies via `register-struct`.

**Gated off (commented out in `emit-c-include`'s main dispatch ~line 651):**
- Top-level `typedef struct ...` / `struct Tag { ... };` recognition (`c-parse-struct-decl`). Re-enabling it currently corrupts the parse stream when libc headers (e.g. `__locale_struct` in `<string.h>`) are processed — strcmp's declaration ends up swallowed. All 38 tests fail with `unknown: strcmp` until the dispatcher is disabled.

## Root cause of the regression

Two bugs uncovered during debugging:

1. **c-parse-struct-decl forward-advance bug (FIXED).** The `struct`-keyword branch initially did `(set! pos pos)` instead of `(set! pos te)` — never advanced past the keyword. Then the next-token read treated "struct" itself as the tag. Fixed: advance to `te`.

2. **(or A B) inside cond corrupts unrelated extern decls (NOT FIXED).** Writing the dispatch as
   ```
   (or (= (strcmp tok "struct") 0) (= (strcmp tok "typedef") 0))
     (let (...) ...)
   ```
   causes the *next* `extern` declaration in the input stream to be lost. Confirmed by reducer: a header file with `extern int aaa(int); extern int bbb(int);` produces only `aaa` when the `or`-combined branch exists, and both when split into two separate cond branches matching `struct` and `typedef` independently. The bug is in how `cond` + `or` lower together; reproducer is in `/tmp/test2.{nuc,h}` from the debug session.

3. **c-parse-struct-body recovery (PARTIALLY FIXED).** The body parser now pre-scans the matching `}` and uses that as `out-end` regardless of success. But on failures inside the body (array/bitfield/union fields), it still doesn't always advance the outer parser to a coherent position. Real libc headers (string.h's `__locale_struct` chain) cause it to either hang or eat through `strcmp`'s declaration.

The contract `c-parse-struct-body` needs: **always consume up to and including the matching `}` and write that position to `out-end`**, regardless of success — partially in place via the pre-scan.

Same kind of fix needed in `c-parse-struct-decl` for the post-body `__attribute__`, alias name, and `;`.

## Plan to re-enable

1. **Investigate the `(or A B)` cond bug** — write a minimal Nucleus reproducer (cond with two strcmp comparisons under `or`) and trace through `emit-cond` + `or`'s macro expansion. The reducer is `/tmp/test2.{nuc,h}` from the debug session; the breakage appears in the *next* extern decl after the cond, not the cond itself. Possibly a phi-node misordering in `emit-cond` when a branch evaluates `(or ...)`.
2. **Fix recovery in `c-parse-struct-body`** so the outer loop always advances to the matching `}` regardless of failure mode. Drop accumulated fields, scan forward with brace-balancing, and set `out-end` past `}`. Some of this is in place via the pre-scan, but the in-body field loop still mis-advances on arrays/bitfields.
3. **Validate against libc.** Write `examples/cheader-struct-test.nuc` that does `(include string)` and verifies `strcmp` is callable — covers the regression case. Add a second test that uses a custom `tests/fixtures/test-struct.h` exercising:
   - Named struct used by value as a function param.
   - Anonymous nested struct in a struct body.
   - `typedef struct { ... } Foo` followed by use sites.
4. **Re-enable the dispatch path** in `emit-c-include` using *split branches* (one for `struct`, one for `typedef`) until the `or`-cond bug is fixed.
5. **Decide on lossy fields.** Today arrays and bitfields cause the whole struct to be skipped. Better: register the struct with the supported fields and a sentinel for the lossy ones (or omit them; document the layout-mismatch risk). Or punt: register only structs where every field is supported, and skip otherwise. Either is acceptable for the immediate task; pick one before re-enabling.
6. **Function-pointer fields with full signatures.** Designer item #8 in `types.md` (top of file). Today the c-parse-struct-body collapses function-pointer fields to opaque `ptr`. Use `c-parse-type` recursively on the inner signature once the basic struct path is stable.

## Out of scope for this follow-up

- Unions (separate stage-8 item; the Designer's `defunion` design).
- Bitfields (separate item; deferred to "match C" once defunion lands).
- Inline arrays as a Nucleus type (would need a new type kind, e.g. `TY-ARRAY`, or a `(array T N)` constructor — neither exists).
- `restrict` / `const` qualifier preservation (Deferred per types.md).

## Files touched in this pass

- `src/cheader.nuc` — c-parse-type struct branch extension; new `c-parse-struct-body` and `c-parse-struct-decl`; dispatcher hook (commented out).
- `src/nucleusc.nuc` — none in this sub-task (anonymous-struct landing was in the earlier commit).
