# Stage 9 cleanup

#### Designer

Several minor issues came to light during stage 9 and they should be cleaned up now.

## case

Add a `case` macro. It takes a single form followed by an arbitrary number of value/result pairs. An single value as the last argument is the default if unmatched (required). Use the `case` macro to replace  in the following:

* emit-nuch-header
* emit-nuch-import-forms
* fprint-node
* emit-toplevel-forms

## error attribution

A recent failed compile reported a malformed `cond` but not its location. The compiler should try to track the location of compile errors wherever practical.

## Name (non) shadowing

A symbol should only name one kind of thing (special form, type, function, value, etc...)

## i64 hardcoding

Despite previous work to make Nucleus able to target platforms other than Linux AMD64, parts of the compiler still hardcode the assumption that a pointer is i64. Nucleus must be able to target other platforms, including microcontrollers, and the compiler should at least be able to run on a 32-bit CPU in theory.

---

## Implementation status (landed)

All four items are implemented; `make test` (39 examples + REPL) and `make bootstrap` (fixed-point) pass.

### case — done
`case` macro added to `lib/macros.nuc`: `(case form v1 r1 … default)` → `(cond (= form v1) r1 … true default)`. `form` is re-evaluated per arm (no temp binding, since plain `let` requires a type annotation and the macro can't know the form's type — all four call sites pass a pure expression). Applied to `emit-nuch-header`, `emit-nuch-import-forms`, `fprint-node` (outer kind dispatch **and** the inner char-escape `cond`), and `emit-toplevel-forms`. Example + expected output in `examples/case.nuc` / `tests/expected/case.out`.

### error attribution — done
Root cause: quasiquote-built cons cells (`__cons`/`__append`) carry `line 0`, so a malformed `cond` produced by a macro (`if`/`when`/`case`/…) reported line 0. `expand-macro-call` now calls `stamp-macro-lines`, which stamps the macro **call-site** line onto every synthesized (line-0) node while leaving spliced user arguments (non-zero line) untouched. Also: top-level definer errors referenced *interned symbol* nodes (shared singletons → line 0); the shadowing guard reports the enclosing **form-cell** line instead.

### name (non-)shadowing — done
A symbol may name only one kind of thing (special form, built-in type, struct type, protocol, macro, function, value). `name-existing-kind` (content/`strcmp`-based, interning-independent) + `guard-name-kind` are called from every top-level definer; same-kind reuse (overloads, redefinition) is allowed. Found and fixed two real violations: `(defn i64 …)` in `src/format.nuc` (shadowed the `i64` type — replaced its ~55 call sites with `(cast i64 …)` and deleted the helper) and `(defn double …)` in `examples/implicit-return.nuc` (renamed to `dbl`).

### i64 hardcoding — done
Introduced a target descriptor: `g-target-triple` + `g-target-ptr-bytes` (emitted triple, pointer/`CStr`/struct type sizes & alignments, and `sizeof`'s `size_t` width all route through it), plus `g-host-ptr-bytes`/`ptr-bytes` for the compiler's own arrays-of-pointers (was a literal `8` in ~47 allocations). Defaults reproduce x86_64 byte-for-byte. **Remaining:** the hand-written `__cons`/`__append` IR templates in `emit-qq-helpers` still assume the 64-bit Node ABI (size 40, `align 8` on pointer fields) — documented inline as the next 32-bit step, since just the malloc size without fixing the pointer-field alignment would be an incorrect half-measure.
