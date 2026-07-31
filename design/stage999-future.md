# Future plans

Nothing here is fleshed out. Some ideas may be bad. Things here may never be implemented, or may be impossible.

## Lispiness

Nucleus is a replacement for C, but it should bring in as much Lisp goodness as it can without compromising C interop or adding runtime overhead.

### Declarable blanket protocols

Stage 9 hardcodes the two blanket (auto-conforming) protocols `Any` (every type) and `Struct` (every struct) — see `design/stage9/polymorphism.md` §10.1. A general, *declarable* facility — letting a library define its own blanket protocol with a compiler-checkable conformance predicate — is deferred here. It would generalize the hardcoded pair into one mechanism, at the cost of a way to express "which types conform" in source.

### Gensym reader macro

Probably `#`, semantics like Clojure but not the postfix syntax

## Slices, bounds checking, and `const` pointers

Bounds-checked slices and `const`/read-only pointers, noted as adjacent
follow-ons from stage 10 (stage10/safety.md §3). Safe accessors for C
strings/arrays with runtime cost seem like a good idea, but it would be even
better if there are ways to improve safety with no runtime cost.
(stage14/unsafe-namespace.md separately defers a debug bounds-checked `aref`.)

## Editor integration

Local Emacs interaction landed in stage 7 (`design/stage7/interaction-mode.md`,
`docs/emacs.md`). Other editors (VS Code, neovim) and any network protocol are
deferred.

## Base features

* `addr-of` probably needs a reader macro; likewise a sigil/reader macro for `ref` in type signatures
* `defvar` inits are limited to literals (and `defconst`/`defenum` folds) — no constant-expression folding
* `set!` should take multiple pairs like `let` and/or be polymorphic
* `inc!`/`dec!` predate macros; they should probably become macros over `set!`

## macrolet

Lexically scoped macros are useful, especially when it's desirable to capture symbols from the enclosing scope. Toplevel macros also capture, but that's a footgun because their behavior will vary by call site.

## errata

`(Maybe StrView)` fails in JIT modules, `!void` unsupported, struct-in-Result
returns zeroed fields.

`make-vec`, and especially `cast` over `make-vec` shows a lack of proper constructors — designed: [stage14/target-typed-constructors.md](stage14/target-typed-constructors.md) (the want channel + `*-new` constructor families)

`doseq` with missing brackets around the binding form segfaults; a friendly error would be better

Having to perform operations on (addr-of entry) in a HashMapEntryIterator is icky


in `emit-get-with-callee` when branch A's (Self, ptr) probe misses and the callee type has a registered get, the selector should be re-emitted as a value and dispatched through branch B rather than fallback


Target-type widening: do we need to require `as` when the return-type is smaller than the target type?

Offset-based C struct reflection for Doom Dehacked patch support was reported as absent with no equivalent

Colon-typed defconst seems to have an issue

Fixed-size array fields in structs

Duplicate defmacro silently first-wins. 

Quoted symbols work for struct field access, but bare symbols are also allowed and can collide with callable values by shadowing variables. Globals aren't allowed and should be.
