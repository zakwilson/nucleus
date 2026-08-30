# Stage 16 — deferred and open register

An index, not a design document. Every item below was raised, measured or
filed by a Stage 16 document and deliberately not closed. Each entry names
what it is, where the full detail lives, why it stopped there, and what
closing it would actually take — the detail itself stays in the filing
document; this page exists so a reader does not have to re-derive "is this
still open?" from eighteen files.

Grouped by what a reader needs to do next:

- **Needs a decision** — the next step is a ruling, not code. Implementation
  is straightforward once someone picks.
- **Needs work** — the fix is understood (often down to the function and the
  approach), just not done.
- **Deliberately closed** — considered and left as-is, for a stated reason.
  Listed here so the reason stays visible, not because anyone expects to
  revisit it without a new trigger.

## Needs a decision

- **Variadic `set!` replacing `.set!`.** Filed in
  [overview.md](overview.md#replace-set-with-variadic-set) as a two-line stub,
  never evaluated. The user's own framing names the fork: "a simple variadic
  `set!` with an extra quoted symbol or variable resolving to symbol for
  struct field assignment, or a more generic mechanism allowing its extension
  to arbitrary scenarios." No design document exists because the two branches
  produce different surfaces — closing it means picking one before anything
  gets written down, let alone built.

- **Making a `(compile-time …)`-defined `defvar`/`defn` visible to the
  program module.** [repl-libraries.md](repl-libraries.md) (the D9a section):
  the two type prescans now descend into a `compile-time` body so a CT-defined
  *type* is nameable in a signature (D9a, done), but the two *value* prescans
  (`prescan-value-names`, `prescan-defn-signatures`) deliberately do not — a
  CT `defvar`'s `@g = global` and a CT `defn`'s `define` go to the CT module
  **alone**, and a backward reference to either already emits invalid IR
  today. Extending visibility needs "the ruling D9 took for types, taken again
  for values" — i.e. a decision that a CT `defvar`/`defn` is a **program**
  binding, the same call D9 made for CT `defstruct`. Once ruled, the fix is
  the same shape as D9a's descent.

- **`TY-FN` (a function pointer) in condition position.** [bool-truthiness.md
  ](bool-truthiness.md), "Deliberately not done": `(= hook null)` is a real
  idiom (Stage 15 W9 item 18), so `(when hook …)` is a plausible extension of
  Part 2's nil-punning. It is not on the Recommendation's list, and
  `is-ptr-like` deliberately excludes `TY-FN`, so admitting it means asking
  `is-ptr-repr` and deciding whether a function pointer counts as "nullable"
  for this purpose — a separate ruling, not an oversight. Today it reaches the
  generic `condition must be bool` diagnostic.

- **Unifying `--sysroot=` with `--link-arg=--sysroot=<path>`.**
  [cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md) §9.5:
  `--sysroot=` reaches the preprocessor only; the link step still needs the
  existing `--link-arg=` spelling. Two flags for one concept, but unifying
  them means deciding whether `--sysroot=` should also override the
  triple-keyed link-driver default — the question `context/conventions.md`'s
  "a triple-keyed toolchain default must ask whether the build is CROSS"
  section poses generally. Deferred deliberately, not overlooked.

- **Zero-is-false** (extending truthiness to any nonzero *number*, not just
  nullable pointers). [bool-truthiness.md](bool-truthiness.md)'s Recommendation
  and [overview.md](overview.md#broad-auto-cast-to-bool): explicitly separated
  from Part 2 and left available. The document already leans toward it — "the
  larger prize… and it matches this codebase's `(!= flag 0)` idiom, where C
  semantics fit and Lisp's do not" — but adopting it changes what `(when
  n:i32 …)` means for every existing program, which is exactly the kind of
  semantic fork this register exists to flag rather than pre-empt.

- **Adopting `&` in `src`/`lib`.** [ref-sigil.md](ref-sigil.md) §5: both
  spellings ship unadopted, so `ref:` still stands at ~1100 sites in the
  compiler's own sources and `(addr-of x)` at ~640. Adoption is a real
  trade-off (characters and a denser read against a pointer kind that is easier
  to miss when scanning) and costs a `make update-bootstrap` first, since the
  committed boot compiler knows neither rule. The two halves are separable —
  `&x` for `(addr-of x)` is a mechanical, unambiguous substitution, while the
  type sigil has the standalone-`&T` subtlety of §6 — so they can be taken one
  at a time. If taken, do each as one sweep verified against a pre-adoption
  `build/nucleusc.ll`.

## Needs work

- **`case` taking a list.** [overview.md](overview.md#case-taking-a-list): one
  line of raw request, no design document, never staged — `(case foo :bar 1
  (:baz :qux) 2 3)`, expanding a list of alternatives to individual
  comparisons at compile time. Small and fully specified by the one-line
  example; it simply never got a design pass.

- **The `intern-symbol` identity defect after `(import-use node)`.**
  [repl-jit-symbol-precedence.md](repl-jit-symbol-precedence.md) §5–6: once a
  REPL session imports `node`, the session defines its own `intern-symbol`, so
  a macro **first expanded after** the import mints symbols from a second
  intern table — and `emit-node` dispatches special forms by pointer identity,
  so `(mc 9)` (a macro expanding to `cond`) answers `unknown: cond`. Loud,
  confined to special-form heads (a function head resolves by spelling), and
  absent for a macro already expanded before the import. §5 names three
  routes and recommends the first: register-and-declare `lib/node.nuc` the
  way `repl-include-all-libc` already treats libc, since the compiler *is*
  the node runtime structurally, not incidentally. Needs a seventh
  ABI-lowered `declare` emitter.

- **`!T` pairs in the template-ref-equality slot-type rule.**
  [template-ref-equality.md](template-ref-equality.md), via the SE-1/SE-2
  closing note in [progress.md](../progress.md): `type-eq` has no `TY-ERR`
  arm, so two differently-erred `!T` types still compare equal at the new
  `slot-type-compat` chokepoint. Zero probe hits against the corpus — nothing
  observed to be wrong yet — and `TY-ERR` identity (what makes two error types
  "the same") is its own unresolved question, not a one-line fix.

- **Deduplicating the ~40 near-identical `vector_new_in` stamps.**
  [template-ref-equality.md](template-ref-equality.md) §"The rule was the
  easy half": SE-2 found that a generic whose type variable appears only in
  its *return* type was memoized and mangled on parameter types alone, so the
  compiler held one `vector-new-in` stamp that 59 call sites silently shared;
  fixing the correctness bug (wrong element type read back) was in scope, but
  collapsing the now-correctly-distinguished stamps back down to one-per-type
  (instead of leaving near-duplicates) is a follow-up cleanup, not done.

- **`$` in a stamp symbol is unexercised on Windows/Mach-O.**
  [template-ref-equality.md](template-ref-equality.md), "Residual risk": the
  `.$r.`-suffixed symbols SE-2 introduces are legal in an LLVM identifier on
  every object format and are covered on ELF (including `.text.<sym>` section
  names, via `make avr-test`), but no Windows or Mach-O link of a program
  containing one has actually been run. The Windows boot IRs were regenerated
  and do contain them, untested.

- **Adopting the condition-position sugar across `src/`'s own ~1,135 null
  tests.** [bool-truthiness.md](bool-truthiness.md), "Deliberately not done":
  Part 2's nil-punning (`(when raw-ptr …)` instead of `(when (!= p null) …)`)
  is mechanical to adopt in the compiler's own source, but doing so moves the
  compiler's own IR and needs its own `make update-bootstrap` cycle — kept as
  a separate item so Part 2 itself stayed a no-boot-refresh change.

- **The Windows boot IRs are cross-emitted from the host's C headers.**
  [c-header-layout.md](c-header-layout.md) §11.5: `src/repl_shim.c`'s removal
  means the compiler's IR now contains a `[1 x %__jmp_buf_tag]` alloca behind
  a real header type, and the Windows boot artifacts are built on this
  container, which has no Windows sysroot — so they carry **glibc's** 200-byte
  `jmp_buf` shape, not Windows's. Inert today (`build.ps1` only drives the boot
  binary in batch mode; self-hosted emission on real Windows reads the real
  headers), but latent. Passing `--sysroot` to `make windows-boot` closes it
  outright once a Windows sysroot is available in the build environment.

- **A `compile-time`/`defmacro` body under `--target=` sees the target's C
  declarations while running on the host.**
  [cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md) §9.5: the JIT
  module concatenates `g-decl-bufp`, which C4 made target-shaped, but the JIT
  itself always runs on the host — so a macro body calling an AVR-declared
  libc function during an AVR cross-compile now visibly disagrees with the
  host it runs on. Not new (it was host-shaped by luck before C4); inherent to
  one per-unit C-declaration set rather than one per module. Fixing it means a
  second header read under the host triple, just for the JIT's declare set.

- **`--emit-cheader` can export a signature naming a type it does not
  define.** [repl-libraries.md](repl-libraries.md) (the D9a section): a
  `defn` taking a `(compile-time …)`-defined struct by value now reaches this
  through one more path than before, but the hole predates D9a —
  `(defstruct- PrivS …)` + a public `defn` taking it produces the identical
  unusable header today. Closing it needs a "does this generated header
  define every type it names?" check, which private structs need first
  regardless of D9a.

- **The by-value C-struct `#include`.** [c-header-layout.md](c-header-layout.md)
  §9.3: a **tag** rendered `struct SDL_Rect` in a generated header gets no
  `#include`, correctly, since an incomplete tag is legal behind a pointer —
  but a *by-value* parameter of one parses and then cannot be called. The
  include would have to come from `StructDef`, whose `src-file` is the
  linemarker path (`/usr/include/…`), not an import spelling, so closing it
  needs a second provenance field written at `StructDef`'s four registration
  sites (the `CTypedef.hdr` shape, but four writers instead of one). Filed
  rather than fixed because nothing in `lib/` has a by-value C struct in a
  public signature today.

- **`(.& p field)` on a packed struct loses the packing.**
  [c-boundary-defects.md](c-boundary-defects.md) §14.5: the address-of yields
  an ordinary `(ref T)`, which carries no alignment record, so a load through
  *that* pointer re-claims the field type's natural alignment. C has the
  identical hole (`-Waddress-of-packed-member` exists because of it); closing
  it on the Nucleus side needs an alignment annotation on the pointer *type*
  itself, not just the struct.

- **A near-miss on `&` quotes the expanded atom.** [ref-sigil.md](ref-sigil.md)
  §4: `x:& (Vector T)` reports `binding name ends in ':' (x:ref:)`, naming a
  spelling the user did not type, because the sigil is gone by the time CP-3
  raises in `split-colon-segments`. The guidance in the message is still right;
  fixing the quotation means carrying an atom's original spelling as far as the
  desugar pass, which is a field on `Node` for one near-miss message.

## Deliberately closed

- **AVR enums follow clang, not avr-gcc.**
  [cheader-parser-vs-libclang.md](cheader-parser-vs-libclang.md) §9.2/§9.5: a
  C header enum imported on AVR is sized the way **clang** would size it;
  avr-gcc by default uses a narrower "short enum" convention. A C header enum
  passed by value through an avr-gcc-compiled object would disagree. Accepted
  as the cost of using clang as the parsing and layout oracle throughout —
  the same tradeoff every other AVR layout claim in Stage 16 makes.

- **A starred first declarator refuses a later one rather than guessing
  its pointer depth.** [c-header-layout.md](c-header-layout.md) §8 (CD-1):
  `c-parse-type` collapses pointer depth into a bare `ptr` with no pointee, so
  `int *p, q;` cannot tell whether `q` is `int` or `int*` from the collapsed
  type alone. CD-1 asks the question directly (`c-span-has-star`) and refuses
  the declaration with a located opaque-type error rather than guessing — the
  same "an unreadable body marks the enclosing declaration opaque, never
  silently wrong" discipline L1 established for struct members.

- **`zeroext` is not emitted on a `_Bool`/`bool` parameter or return.**
  [bool-type-plan.md](bool-type-plan.md)'s ruling table, restated in
  [progress.md](../progress.md)'s varargs-promotion entry: clang declares
  `zeroext i1`; Nucleus declares bare `i1`. Ranked "cheap insurance, not a
  fire" and left out of the Part 1 recommendation. Measured attempts to make
  the omission actually miscompile failed on both x86-64 (`setg %al`) and
  RISC-V (`sgtz a0,a0`) — it is a specification divergence with no observed
  live defect, not a deferred bug.

- **`%BF = type { i1, i32 }` where clang emits `{ i8, i32 }`.**
  [bool-truthiness.md](bool-truthiness.md) §"Part 1 and the C boundary" /
  [bool-type-plan.md](bool-type-plan.md)'s ruling table ("`_Bool` in memory as
  `i8`: out of scope"): size, alignment and field offsets agree (8 bytes,
  measured) so a struct crossing the C boundary is safe either way; the
  residue is that an `i1` load reads bit 0 only, so a `_Bool` byte holding `2`
  (already undefined behavior in C) reads as `false` rather than `true`.
  Design recommendation was to leave it — no observed defect justifies the
  in-memory-representation change.

- **`_Complex` is out of scope.** [c-boundary-defects.md](c-boundary-defects.md)
  §10: a distinct type constructor with its own ABI classification and Annex G
  arithmetic, judged much easier to add *after* the FL-1…FL-7 float-width work
  than alongside it. Not attempted this stage.

- **Decimal float literals are not correctly rounded at `f80`/`f128`.**
  [../future/decimal-float-literals.md](../future/decimal-float-literals.md)
  (DL-1…DL-4), cross-referenced from [c-boundary-defects.md](c-boundary-defects.md):
  `float-literal-value` evaluates every decimal literal at host `f64`, so
  `(defvar x:f128 1.1)` gets `1.1`'s f64 value widened exactly rather than the
  f128-correct value. Hex-float literals (FL-3) are exact and mitigate the
  common case. Staged as its own future item deliberately: it adds no type,
  changes no ABI, moves no layout, and nothing in the tree depends on it —
  "a poor passenger on a larger change."

- **Demand-driven emission of an imported library's definitions.**
  [compile-time-imports.md](compile-time-imports.md) §4/§7, option (c): emit
  an imported `defn` only if something references it — the most general
  answer to the compile-time-import problem, and the largest change. Not
  chosen as the first step because it walks directly into the class
  `context/conventions.md` warns about twice: a pre-pass that mirrors an
  emitter must mirror its skips, and a non-emitting mode inherits none of the
  emitter's diagnoses. Options (a) `import-ct` and (b) the prelude split were
  built instead and close the same motivating case.

- **The quoted-symbol-in-selector-position wart.**
  [container-literal-elements.md](container-literal-elements.md) /
  [overview.md](overview.md#container-type-literals-should-take-more-element-types),
  "Deferred by decision": in head position, `(m 'count)` resolves as a field
  access on `m` and the quote is silently stripped, rather than looking up the
  symbol `'count`. Reaching a symbol lookup there requires the explicit
  `(invoke m 'k)` spelling. Held pending a larger rethink of field access in
  general; the constraint to carry into that rethink is stated already — an
  explicitly quoted symbol should be a value, never a selector.
