# Global initialization — combining declaration with initialization

**Status: design, 2026-08-01; IMPLEMENTED — all six steps G-0 through G-5
landed 2026-08-01/2026-08-02 (§5), plus one regression-fix interlude between
G-3 and G-4. G-2's `g-arena-alloc` conversion, deliberately split out at the
time (see the G-2 as-built record), landed as part of G-5. Acceptance
criteria (A) `compiler-init` eliminated and (B) the no-initializer flip are
both met — see the G-5 as-built record.** Written against `stage15-stress-test`
at `591deba`. Every number below
is measured against `build/nucleusc` at that commit; probes are recorded inline so
they can be re-run. §2.5's four probes have since been fixed by G-0 and carry a
box saying so.

**Filed as Stage 15 W8** ([stage15-stress-test/overview.md](stage15-stress-test/overview.md)).
This document is its specification; the stage docs reference it rather than
restating it. §7's defects (grown from six to twelve as G-2/G-3/G-5 surfaced
more) are filed separately as **W9**; the stage's own
[progress.md](stage15-stress-test/progress.md) reconciles §7 against its own
independently-found defects into one twenty-item list, two of them now fixed.

**Provenance.** Stage 15's W6 closed the `(defvar g:ptr:T null)` half of the
§3.4 nullability hole and *deliberately left the no-initializer half open* —
`(defvar g:ptr:T)` still emits the identical unsound `global ptr null`. See
[stage15-stress-test/nullability.md](stage15-stress-test/nullability.md) §1.5
for that triage; this document does not restate or contradict it. W6 parked the
hole because closing it needs *a way to express deferred initialization of a
non-null global*, which the language does not have. That is the subject here.

## Revised 2026-08-01 — the four rulings, and what they changed

The first draft of this document left several questions open and argued
positions that have since been decided. The decisions, and the sections they
rewrote:

1. **Order may matter, and reordering the compiler's own source to make an
   initializer expressible is sanctioned.** As a *last resort* it is also
   acceptable to initialize to a placeholder and substitute the real value
   later — explicitly a code smell. → §4.1 restated as settled policy, not a
   defence; §3's new **Option 7**.
2. **A startup call is acceptable, but it must be zero-cost when unused.** A
   program with no runtime initializer must emit **nothing**: no
   `@__nucleus_init`, no `llvm.global_ctors` entry, no synthesized `main`.
   Stated reason: microcontroller binary size. → new **§4.8**, and §4.6/G-3
   rewritten against it.
3. **The compiler is the priority, not the Doom port.** The goal is to
   **eliminate `compiler-init`, or reduce it to a few genuinely special
   cases**; globals that should not be nullable are declared and initialized in
   one operation. → new **§2.12**, the action-by-action analysis of
   `compiler-init`, which is now the most important measurement in this
   document; §4.4 and §5's G-5 rewritten around it; §8 settled.
4. **Do not convert the Doom port yet** unless a test needs it. → the port
   stays as evidence (§2.7 is a real finding and still justifies shipping the
   static half first) but is no longer a decision gate; G-2's "stop and
   re-measure" step is **removed**.

**Two conclusions of the first draft are corrected by this revision**, both
found by reading the source §2.12 required:

* **§2.10's `g-arena-alloc` blocker dissolves.** It is not "a fourth bucket no
  initializer expression can express" — `AllocHandle` is `{kind:i32, data:ptr}`
  and the arena handle is `{ALLOC-ARENA, null}`, a **compile-time constant
  struct**. It falls in bucket 1b, needs only G-2, needs no ordering rule, no
  value-returning constructor and no placeholder. The arena is lazily
  initialized by `arena-alloc` itself (`lib/arena.nuc:41`), so there is no
  "arena must be live first" constraint either. It also *fixes* a live
  latent inconsistency rather than creating one (§2.10).
* **A synthesized `main` wrapper is incompatible with zero-cost-when-unused as
  stated**, because the rename must happen in `emit-defn` long before the
  queue's emptiness is known. §4.8 resolves this; the effect is to *simplify*
  the per-triple split rather than complicate it.

**Acceptance criteria.** The headline goal is (A); (B) is the language rule
that (A)'s machinery makes possible, and is what W6 §1.5 parked.

* **(A) `compiler-init` is eliminated, or reduced to a few genuinely special
  cases**, with every global that should not be nullable declared and
  initialized in one operation. §2.12 says exactly which of its 51 statements
  reach that and which are the residue.
* **(B)** `(defvar g:ptr:T (make-thing))` typechecks with `g` reading as
  **non-null**, so the no-init spelling `(defvar g:ptr:T)` can be **rejected**
  and W6 §1.5's hole closes in both spellings.

---

## 0. Summary, and five corrections to the brief

*(The first four were made by the original investigation; the fifth was added by
the 2026-08-01 revision. Corrections this document made to **its own** first
draft are listed above, in the Revised section.)*

1. **The "single translation unit" premise is false for one real, supported
   mode.** A whole-program compile (`--emit-llvm` / `-c` / `-o` from an entry
   `.nuc`) is one LLVM module, as claimed. But `--emit-nuch` + a separately
   compiled `.o` is a genuine multi-TU route — `make lib`, `make lib-so` and
   `make install` exist for it, and `--emit-cheader` targets C consumers by
   definition. Measured: a library's `defvar` becomes `@gb = external global
   ptr` in the consumer, and the two objects link and run (§2.4). **A design
   whose initializers are reachable only from the consumer's `main` cannot
   initialize a library.**
2. **`llvm.global_ctors` is silently a no-op on AVR** with the link driver the
   compiler already uses. LLVM emits `.init_array` into *RAM* while avr-libc's
   `__do_global_ctors` walks `__ctors_start`..`__ctors_end`, which the linker
   leaves empty. Measured, against an avr-gcc reference build that differs
   (§2.6). This is the strongest single argument against Option 2 standing
   alone.
3. **The brief's cost framing is 95% off-target for the external evidence.** Of
   the Doom port's 21 hand-rolled `ensure-*` lazy initializers, **20 need no
   runtime initialization at all** — 9 are constant tables, 11 are fixed-size
   zero-filled buffers (§2.7). What they want is a *static aggregate global*,
   which is C's `T name[N] = {…};` and needs no entry point, no constructors and
   no ordering rule. Only **1** of 21 is genuinely runtime-dependent.

   *Revised reading (2026-08-01).* The finding stands and still justifies
   shipping the static half first. It is **no longer decisive**, because the
   deciding corpus is now the compiler's own source, not the port's — see
   correction 5 and §8. The first draft's inference from it ("the compiler
   already has `compiler-init` and is not suffering") was the wrong conclusion
   from the right measurement: `compiler-init` *is* the thing to remove.
4. Minor: the brief's line citations have drifted. `defvar-init-ir` is at
   `src/nucleusc.nuc:8607` (not 8283); W6's `pkind-flow-check` call is at
   `:8720` (not 8395); `emit-compile-time` at `:9719` is correct. The `defvar`
   census is **174** forms in `src/`+`lib/` (164 + 10), not 254; the load-bearing
   figures — 114 no-init, 53 non-null element-typed — reproduce exactly.
5. **(Added by this revision.) `compiler-init` is 51 statements, and exactly one
   of them is genuinely special.** §2.12 classifies every one: **30 statements
   become combined declaration+initialization, covering 48 globals** (3 of them
   constant, so they need only the static half); **20 statements are dead** and
   simply delete — they restate the `defvar` zero default, and `compiler-init`
   runs exactly once per process, so no per-unit reset is load-bearing; and the
   residue is **`target-init` alone**, because it reads argv, which no
   initializer can see. Two further live inconsistencies fell out of the same
   read: three type-erasure registries are declared non-null and are *never*
   initialized (lazily built behind a `= null` guard, i.e. the same unsoundness
   in a third spelling), and `add-include-path`/`add-link-arg` run **before**
   `compiler-init` and therefore silently get libc-backed vectors.

**Recommendation, in one line:** ship the *static* half first — constant
expressions and constant aggregates in `defvar-init-ir` plus an `(array T N)`
type — because it has no ordering semantics at all, is additively
byte-identical, and already covers the sharpest migration blocker
(`g-arena-alloc`, §2.10) as well as all the external evidence; then ship the
runtime half as a single synthesized `@__nucleus_init`, emitted at exactly one
point and only when non-empty (§4.8), registered by `llvm.global_ctors` on
hosted triples and refused with a located error on a triple that has no
working mechanism; then eliminate `compiler-init` (§2.12) and flip. §5 stages
it.

---

## 1. The problem, stated precisely

Three things are currently conflated under "`defvar` can't allocate".

### 1a — a global whose initializer is a *runtime* expression

The value is not a compile-time constant: it is an address returned by an
allocator, or the result of a call. Nothing static can express it.

```lisp
(defvar g-mobjinfo:ptr:MobjInfo (malloc-table))   ; rejected: "init must be a literal"
(defvar g-structs (vector-new-in (addr-of g-arena-alloc)))
```

**Measured population.** In `src/`+`lib/`: 53 sites (§2.2), all of them
process-lifetime singletons filled by `types-init` / `compiler-init` — and **45
of the 48 globals `compiler-init` initializes are in this bucket** (§2.12, the
deciding measurement). In the port: **1** site (`s_sound.nuc:229`, whose channel
count is runtime-configured).

### 1b — a global that is non-null but *constant*, and merely not expressible

The value *is* a compile-time constant — a fixed-size aggregate, an address of
another global, an arithmetic expression over `defconst`s, an `(as CStr "…")` —
but `defvar-init-ir` renders only five shapes and has no folding.

```lisp
(defvar g-mobjinfo:ptr:MobjInfo (array MobjInfo (deref (MobjInfo …)) …))  ; rejected
(defvar g-players:ptr:Player   (array Player 4))                          ; no such type
(defvar g-name:CStr            (as CStr "doom"))                          ; rejected (W5c note)
```

**Measured population.** The port: **20 of 21** `ensure-*` initializers
(§2.7) — 9 constant tables, 11 zero-filled fixed buffers. The compiler: 0
(its registries are genuinely runtime). This bucket is *entirely disjoint*
from 1a and needs none of the same machinery.

### 1c — ordering and use-before-initialize

Two distinct hazards:

* **Between initializers.** `(defvar a (f))` where `f` reads global `b`. What
  order do they run in, and is a read of an as-yet-uninitialized `b` detected?
* **Between an initializer and a use.** The hazard the port's `ensure-*` guards
  exist for, and the one the no-init spelling creates today: `@g = global ptr
  null` is read before anything fills it and segfaults. Measured (§2.1).

**Only 1a raises 1c.** 1b globals are initialized by the loader/linker before
any code runs, so a constant initializer is ordering-free by construction. This
is the single most important structural fact in this document.

### Which measured sites fall in which bucket

| Population | 1a runtime | 1b constant | already fine |
|---|---|---|---|
| compiler `src/`+`lib/`, 53 non-null no-init globals | **53** | 0 | — |
| the 48 globals `compiler-init` initializes (§2.12) — 44 of the 53 above, plus `g-arena-alloc`, `g-current-ns` and 2 fn-pointer hooks | **45** | **3** | — |
| compiler, 48 elem-less bare `ptr` no-init globals | — | — | 48 (`void*` hatch, W6-exempt) |
| compiler, 9 `raw:T` + 1 `CStr` no-init | — | — | 10 (declared nullable) |
| Doom port, 21 `ensure-*` initializers | **1** | **20** | — |
| Doom port, 13 non-null no-init `defvar-` | 1 | 12 | — |

---

## 2. Ground truth (measured 2026-08-01)

### 2.1 What `defvar` accepts, and the live hole

`defvar-init-ir` (`src/nucleusc.nuc:8607`) is a **constant renderer**, not an
expression compiler. It accepts exactly: an integer literal, a float literal, a
string literal, the symbols `null` / `true` / `false`, `(char "x")`, and a
`defconst`/`defenum` name. Everything else dies `defvar: init must be a
literal`. Probed, all five rejected identically:

```
(defvar g:ptr:Thing (make-thing))   => defvar: init must be a literal
(defvar g:CStr (as CStr "hi"))      => defvar: init must be a literal
(defvar g:i32 (+ 1 2))              => defvar: init must be a literal
(defvar g:ptr (malloc 16))          => defvar: init must be a literal
(defvar g:Thing (Thing 3))          => defvar: init must be a literal
```

The W6 fix and the hole it left, both re-verified:

```
(defvar g:ptr:Thing null)  => error: defvar: raw pointer where non-null (ref ...) is required …
(defvar g:ptr:Thing)       => @g = global ptr null, align 8   → segfault on first use (exit 139)
```

There is no aggregate route either: `(defvar gs:P)` is legal (`zeroinitializer`),
`(defvar gs:P (P 1 2))` is not, and `(array T N)` is **not a type** — `array` is
a value form only (`emit-array-lit`, `:7877`), so a global fixed-size array
cannot be spelled at all.

### 2.2 The compiler's census

Parsed with a paren- and colon-paren-aware scanner over every top-level
`(defvar …)` / `(defvar- …)` in `src/*.nuc` + `lib/*.nuc`:

| Measure | Count |
|---|---|
| top-level `defvar` forms | **174** (164 `src/`, 10 `lib/`) |
| with an initializer | 60 |
| **no initializer** | **114** |
| … elem-less bare `ptr` (the `void*` hatch — W6-exempt) | 48 |
| … **non-null element-typed pointer** | **53** |
| … `(raw T)` / `raw:T` (declared nullable) | 9 |
| … `CStr` (flow-exempt by W5c) | 1 |
| … non-pointer (`AllocHandle` ×2, `i32`) | 3 |

The 53 break down exactly as `nullability.md` §1.5 records: **21** `ref:Name`
singletons (20 `ty-*:ref:Type` at `nucleusc.nuc:66-97`, plus
`g-globals:ref:Scope` at `:175`) and **32** collection registries (29
`(ref (Vector …))`, 2 `(ref (HashSet …))`, 1 `(ref (HashMap …))`), 50 in
`nucleusc.nuc`, 2 in `union-registry.nuc`, 1 in `type-mangle.nuc`.

**51 of the 53 have exactly one `(set! g …)` site** in the whole tree; 2 have
three. They are mechanically "declare here, assign once at init".

**640 static references** to the 53 across `src/`+`lib/` (372 to the 21
singletons — `g-globals` alone 81, `ty-void` 65, `ty-ptr` 46 — and 268 to the 32
registries). That number is the per-access cost multiplier for Option 4.

### 2.3 Nothing runs before `main`

Zero occurrences of `llvm.global_ctors`, `.init_array`, or any
constructor-attribute emission in `src/`. `main` is emitted as an ordinary
`defn` — `grep '"main"' src/*.nuc` returns **nothing**; the compiler neither
wraps, renames nor special-cases it. `compiler-init` is called from `main`
(`nucleusc.nuc:12507`), after the argv loop, exactly like any other function
call.

### 2.4 A Nucleus program is **not** always one translation unit

`--emit-nuch` exports globals:

```
$ build/nucleusc --emit-nuch mylib.nuc
(defstruct Box (n i32))
(extern (gb (ptr Box)))
(extern (gcount i32))
(declare lib-init () :void)
(declare lib-get () :i32)
```

Compiling the consumer against that header and linking the library object works
and runs:

```
@gb     = external global ptr        # in the consumer's module
@gcount = external global i32
$ ./user2 →  n=42 count=5
```

So the library's globals live in a **different LLVM module**. This is a
supported, Makefile-driven mode (`lib/%.nuch`, `$(BUILD)/lib/%.o`,
`lib-so`, `install`). `--emit-cheader` is multi-TU by definition (though it
does **not** emit `extern` declarations for globals at all — see §7).

**Consequence for the design:** an initializer list reachable only from the
consumer's `main` cannot initialize a library. Only a linker-collected section
(`.init_array`) crosses that boundary.

### 2.5 Value names are still order-dependent — same-file *and* cross-file

> **Fixed 2026-08-01 by G-0** (§5). Everything below is the pre-G-0 measurement
> and is retained as the record of what the probes were; all four now pass in
> both orders and same-file forward. See §5's "G-0 as built".

W1's whole-graph prescan covers `defn` signatures, protocols and struct/union
type *names*. It does **not** cover value names. Measured, all four failing:

| Probe | Result |
|---|---|
| `defn` body reads a `defvar` declared **later in the same file** | `error: undefined: gv — not defined anywhere in this compilation unit` |
| two files, `(import dv)` before `(import uv)` | OK |
| same two files, imports swapped | `error: undefined: gvv — not defined anywhere …` |
| same shape with `defconst` / `defenum` member | identical failure, both orders tested |

The message is actively misleading: the name *is* defined in the unit, it has
merely not been processed yet. (This confirms the brief's `defconst` claim and
extends it: `defvar` and `defenum` behave the same, and the same-file forward
reference — the port's finding §3.5 — still reproduces.)

**This is a prerequisite, not a footnote.** The moment a `defvar` initializer is
an expression, it can name another global — and it will hit this before it ever
reaches an ordering rule.

### 2.6 `llvm.global_ctors`: works on hosted targets, silently dead on AVR

**x86_64-linux — works, including across translation units.** Appending

```llvm
@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }]
  [{ i32, ptr, ptr } { i32 65535, ptr @lib-init, ptr null }]
```

to the *library's* IR, dropping the explicit `(lib-init)` call from the
consumer, and linking the two objects: the initializer ran and the program
printed `n=42 count=5`. `objdump -h` confirms an 8-byte `.init_array`.

**riscv64 — works.** `llc -mtriple=riscv64 -mattr=+m,+a,+f,+d,+c` emits
`.section .init_array,"aw",@init_array`; glibc's loader runs it.

**AVR — two failures, the second silent.**

1. The standard entry type is *invalid*: functions are `addrspace(1)` on AVR
   (Harvard), so `ptr @ini` is rejected —
   `error: '@ini' defined with type 'ptr addrspace(1)' but expected 'ptr'`. The
   entry must be spelled `{ i32, ptr addrspace(1), ptr }`.
2. With that spelling LLVM emits `.section .init_array` plus a `.globl
   __do_global_ctors` reference. But avr-gcc's linker script routes constructors
   through `.ctors`, and the emitted `.init_array` lands in the **data** region:

   | Build | `.init_array` VMA | `__ctors_start` | `__ctors_end` | ctors run? |
   |---|---|---|---|---|
   | avr-gcc `__attribute__((constructor))` | — | `0x68` | `0x6a` | **yes** (1 entry) |
   | LLVM `llvm.global_ctors` → `avr-gcc` link | `0x800100` (RAM) | `0x68` | `0x68` | **no** (0 entries) |

   The constructor is emitted, linked, occupies RAM, and **never executes**. No
   diagnostic anywhere.

### 2.7 The Doom port: 20 of 21 initializers are not initializers

387 `defvar` forms, 71 with no initializer, **13** of those a non-null
element-typed pointer (exactly the shape W6 §1.5 predicted). Around them,
**21 hand-rolled `ensure-*` guards with 50 call sites**, of which **9 are called
exactly once** — i.e. nine of the branches buy nothing at all.

Classifying every `ensure-*` body:

| Shape | Count | What it actually wants |
|---|---|---|
| A — stack `(array T lit…)` + `malloc` + `memcpy` | **9** | a `constant` aggregate global |
| B — `malloc` + `memset 0` | **8** | a `zeroinitializer` array global (`.bss`) |
| C — `malloc`, no init | **3** | same as B |
| D — genuinely runtime | **1** | a real deferred initializer |

**A + B + C = 20 of 21 are 1b, not 1a.**

The cost of the A workaround, measured on a faithful synthetic reproduction
(137 entries × a 3-field struct, the size of `mobjinfo`):

| | today's `ensure-*` | a constant aggregate global |
|---|---|---|
| IR lines in the initializer | **1401** | 0 |
| `alloca`s | **139** | 0 |
| runtime `store`s | **550** | 0 |
| runs at | run time, guarded, every call site | link time |

The port's real tables are far larger: `tables.nuc`'s initializer is 1127 source
lines, `states.nuc`'s is 973.

**The target form is already legal LLVM and was verified end-to-end:**

```llvm
@g.data = internal global [3 x %E] [ … ], align 8
@g      = global ptr @g.data, align 8         ; provably non-null
```

compiled, linked and ran. `@g` is a `ptr:E` that the flow checker can accept as
non-null with no runtime code whatsoever.

### 2.8 The payoff mechanism already exists

`set!` into a typed global already routes through `coerce-int-val` →
`pkind-flow-check`. Measured:

```lisp
(defvar g:ptr:T)
(defn init ():void (set! g (mk)))       ; mk : ptr:T   → accepted
(defn bad  ():void (set! g (mkraw)))    ; mkraw : (raw T) → rejected, "assignment: raw pointer where …"
```

So **any** option that lowers an initializer to an assignment inside a function
body inherits the non-null check for free, with no new typing rule. The
acceptance criterion is a lowering question, not a type-system question.

### 2.9 The JIT tiers have no program globals — the question is moot

* LLVM 19.1.7's ORC **C API has no initializer entry point**. `nm -D
  libLLVM-19.so | grep LLVMOrcLLJIT` lists 17 symbols and none of them is an
  `Initialize`. A `llvm.global_ctors` in a JIT module could never be run through
  the API the compiler is built against.
* But it does not matter, because a JIT module cannot see a program global or a
  program `defn` in the first place. Measured:

  ```
  (compile-time (printf "%d\n" gz))      → IR parse error: use of undefined value '@gz'
  (compile-time (printf "%d\n" (bump)))  → JIT session error: Symbols not found: [ bump ]
  ```

  This is by construction (`context/build.md`: globals go to `g-def-stream`,
  which CT/macro modules do not concatenate; external references resolve
  against the *compiler* binary via the dylib generator). When the compiler
  compiles *itself* the compiler's own globals resolve because they are already
  live in the host process, initialized by the running compiler's `main`.

**Therefore: `compile-time` blocks and `defmacro` JIT modules need nothing from
this design, and a global-init mechanism must not try to run in them.** W1d's
four emission-time couplings are the precedent for how to phrase that — a
located diagnostic if a CT block ever *does* name an initialized global, rather
than a silent zero.

### 2.10 The `g-arena-alloc` blocker — stated, then dissolved

**What the first draft found, and it is all still true as a description of
today's code.** `g-structs` is declared at `nucleusc.nuc:144` and constructed
from `g-arena-alloc`, declared at `:182`. Two facts:

1. **Declaration order is the wrong order.** A "run initializers in declaration
   order" rule would build all 32 registries before `g-arena-alloc` was set up.
2. **`g-arena-alloc` is written by an out-parameter, not by an assignment.** It
   is a by-value `AllocHandle` mutated in place:
   `(arena-allocator (addr-of g-arena-alloc))` (`lib/allocator.nuc:160`).

And the failure mode is **silent**: a zero-filled `AllocHandle` is
`kind = ALLOC-LIBC` (0), and the collection constructors copy the handle *by
value* at construction. Get the order wrong and the 32 registries become
libc-`malloc`-backed instead of arena-backed, with no error and no crash.

**Why it dissolves.** The first draft concluded from (2) that this was "a fourth
bucket no initializer expression can express". That is wrong, and reading
`lib/allocator.nuc` says why:

```lisp
(defenum AllocKind ALLOC-LIBC ALLOC-ARENA)     ; lib/allocator.nuc:83
(defstruct AllocHandle kind:i32 data:ptr)      ; lib/allocator.nuc:88
(defn arena-allocator ((h (ref AllocHandle))):ref:AllocHandle   ; :160
  (.set! h kind ALLOC-ARENA)
  (.set! h data null)
  (return h))
```

The arena handle's *value* is `{ALLOC-ARENA, null}` — two constants. It is a
**bucket 1b constant struct**, expressible by G-2 step 5 alone:

```lisp
(defvar g-arena-alloc:AllocHandle (AllocHandle ALLOC-ARENA null))
;  → @g-arena-alloc = global %AllocHandle { i32 1, ptr null }, align 8
```

That is a link-time constant. Consequently:

* **No ordering rule is needed.** The handle is correct before any code runs,
  so it is correct for every initializer regardless of sequence — including
  ones that run before `main`.
* **No value-returning `AllocHandle` constructor is needed.** §4.4's first
  draft made `(defn arena-handle ():AllocHandle …)` a prerequisite; it is not.
  (It is still worth adding as an idiom, but it is a *runtime* call and
  strictly weaker than the constant.)
* **No placeholder is needed.** Option 7 (§3) does not have to be spent here.
* **The arena needs no setup either.** `arena-alloc` initializes the arena
  lazily on first use — `(when (= g-arena-cap 0) (arena-init))`,
  `lib/arena.nuc:41` — so "ALLOC-ARENA from load time" is safe with no
  `arena-init` ordering obligation at all.

**And it fixes a live latent inconsistency rather than creating one.**
`add-include-path` / `add-link-arg` (`nucleusc.nuc:12426`, `:12432`) are called
from `main`'s argv loop, which runs **before** `compiler-init`. Their own header
comment records the consequence: at that point `g-arena-alloc` is still
zero-filled, so `-I`/`-L` vectors are silently backed by libc `malloc` for their
whole lifetime while every other compiler collection is arena-backed. A constant
`ALLOC-ARENA` initializer removes that split — the handle is correct from
process start, so there is no "before init" window to reason about.

**What remains true, and is now the sharpest *real* test.** The 32 registries
themselves are still bucket 1a: `(vector-new-in (addr-of g-arena-alloc))` is a
call. They still need G-3, and they still name `g-arena-alloc` syntactically, so
§4.2's forward-reference rule applies: `g-arena-alloc` must be *declared* before
them. Today it is at `:182` and the first registry is at `:144`, so this needs a
**source reorder** — which is exactly what the ruling in §4.1 sanctions, and it
is a two-line move.

### 2.11 What "just declare them nullable" costs — measured, not argued

The zero-machinery alternative to this whole document is: re-spell the 53 as
`raw:T` (they *are* null before init, so this is honest) and close W6's hole
immediately. To measure the price, a warn-only compiler was built in scratch
(`pkind-flow-check` and `as-die-flow` print instead of dying), then the retyped
source was compiled with it.

| Source | Flow violations | Distinct lines | Files |
|---|---|---|---|
| unmodified `src/` (control) | **0** | 0 | 0 |
| 21 `ref:Name` singletons → `raw` | **65** | 39 | 3 |
| all 53 → `raw` | **249** | **197** | 10 |

By context, for the full 53: **184 argument**, 27 assignment, 26 return, 12
`as`. Concentrated in `union-registry.nuc` (88), `nucleusc.nuc` (86),
`generics.nuc` (46).

Every one of those 249 would become an `unsafe/cast` or an `as-ref` +
narrowing. That is the number to beat: **an option that costs less than ~200
hand-audited casts in the compiler's own source is worth building.**

### 2.12 `compiler-init`, statement by statement — the deciding corpus

This is the measurement acceptance criterion (A) turns on. `compiler-init`
(`nucleusc.nuc:12047-12123`) has **51 statements**: 41 `set!`, 7 helper calls
(`init-name-sets`, `target-init`, `types-init`, `init-binops`, `init-generics`,
`init-blanket`, `init-rmacros`), 2 `conj`, and 1 `(arena-allocator …)`.

**It runs exactly once per process.** There are two call sites and they are
mutually exclusive: `nucleusc.nuc:12507` (batch, after the argv loop) and
`repl.nuc:850` (`repl-main`). No path calls it twice. This single fact
reclassifies a third of the function.

#### Disposition of all 51 statements

| Disposition | Statements | Globals |
|---|---|---|
| **Combined declaration + initialization** | **30** | **48** |
| … of which *constant* (needs only the static half, G-1/G-2) | 3 | 3 |
| … of which *runtime* (needs G-3) | 27 | 45 |
| **Dead — delete outright** | **20** | 0 |
| **Residual special case — stays an explicit call** | **1** | 5 |

#### A — becomes a combined declaration+initialization (30 statements, 48 globals)

**A1 — constant (3).** These need only the static half and are ordering-free:

| Statement | Becomes | Why constant |
|---|---|---|
| `(arena-allocator (addr-of g-arena-alloc))` | `(defvar g-arena-alloc:AllocHandle (AllocHandle ALLOC-ARENA null))` | §2.10 — a two-field constant struct |
| `(set! g-tmpl-conf-check-hook (unsafe/cast ptr tmpl-conformance-check-instance))` | `(defvar g-tmpl-conf-check-hook:ptr tmpl-conformance-check-instance)` | the address of a global (G-1) |
| `(set! g-stamp-maybe-type-hook (unsafe/cast ptr stamp-maybe-type))` | likewise | likewise |

The two hooks are the late-binding cross-file indirection `init-blanket`
installs (`nucleusc.nuc:11821-11822`). As constants they are `@fn` symbol
references, which LLVM resolves module-wide, so the *emission* order stops
mattering; the compiler's own registration order still does, which is why they
are listed here as a mechanical win and not as a reason to retire the hook
mechanism (that is a separate question W1a's prescan may already have answered).

**A2 — runtime (27 statements, 45 globals).** All of these are
`(vector-new-in (addr-of g-arena-alloc))` / `hashmap-new-in` / `scope-new` /
`intern-str` / `make-type` — genuine bucket 1a, and all become
`(defvar g-X:(ref (Vector …)) (vector-new-in (addr-of g-arena-alloc)))`.

* **19 registries set directly in the body**: `g-strs`, `g-generics`, `g-fnty`,
  `g-protocols`, `g-conformances`, `g-proto-supers`, `g-mono-worklist`,
  `g-structs`, `g-uniondefs`, `g-union-templates`, `g-struct-templates`,
  `g-tmpl-conformances`, `g-enumdefs`, `g-pending-unions`, `g-macros`,
  `g-cast-rules`, `g-globals`, `g-deferror-name-sids`, `g-deferror-msg-sids`.
* **`g-current-ns`** — `(intern-str "user")`. Set **twice** in the current
  function (`:12057` and `:12110`), so two statements collapse to one
  initializer.
* **20 `ty-*` singletons** via `types-init` (`type-utils.nuc:16-41`).
* **5 more via helpers**: `g-special-form-set` + `g-primitive-type-set`
  (`init-name-sets`), `g-binops` (`init-binops`), `g-blanket` (`init-blanket`),
  `g-rmacros` (`init-rmacros`).

**Six of the 48 need a value-returning builder**, because today they are
construct-then-populate rather than construct. Each becomes one small pure
`defn` — which is precisely the source restructuring §4.1's ruling sanctions:

| Global(s) | Today | Builder |
|---|---|---|
| `ty-ptr` / `ty-raw` / `ty-maybe-ptr` | `make-type` then `.set! pkind` | `(defn make-ptr-type (pk:i32):ref:Type …)` — 3 lines |
| `g-deferror-name-sids` / `g-deferror-msg-sids` | vector, then `(conj … 0)` to reserve index 0 | one builder, used twice |
| `g-special-form-set` / `g-primitive-type-set` | alloc + `hashset-init-alloc` + `into #{…}` | `init-name-sets` split into two value-returning builders |
| `g-binops` | vector + 20 `add-binop` | `(defn build-binops ():(ref (Vector (ref BinOp))) …)` |
| `g-blanket` | vector + 2 `conj` | trivial |
| `g-rmacros` | vector + 5 `register-rmacro` | trivial |

**`init-generics` folds too, and is worth calling out** because it is the one
statement that sets *no* global: it walks `g-binops` and seeds `g-generics` with
one intrinsic `Generic` per binop — a *relation between two globals*. It becomes
`g-generics`' builder, which syntactically names `g-binops`. §4.2's
forward-reference rule therefore applies, and it is already satisfied:
`g-binops` is declared at `nucleusc.nuc:266`, `g-generics` at `:271`. No reorder
needed.

**One cross-file friction, recorded so it is not a surprise.** 4 of the 53 are
declared outside `nucleusc.nuc` — `g-fnty` (`type-mangle.nuc:67`) and
`g-boxedfn-table`/`g-dyn-table` (`union-registry.nuc`). A combined
declaration+initialization moves the `hashmap-new-in`/`vector-new-in` call into
*that* file, which must therefore reach `g-arena-alloc` and the collection
constructors at its own emission point. This is the ordinary import-order
question, not a new one, but it is the concrete case where the emission-order
rule (§4.1) has teeth inside the compiler's own source.

#### B — dead: 20 statements that delete

Every one of these restates the value `defvar` already gives, and
`compiler-init` runs once, so none is load-bearing:

* **8 pointer resets to `null`**: `g-prescan-visited`, `g-prescan-sigs`,
  `g-unit-entry-path`, `g-import-cycles`, `g-cycle-prefixes`,
  `g-import-aliased`, `g-import-prefixes`, `g-cinclude-collected`.
* **5 more null resets** whose `defvar` comments cite this very reset as the
  reason they are declared `(raw T)` rather than `(ref T)`
  (`nucleusc.nuc:502`, `:510`, `:528`): `g-ns-prefix-table`, `g-fn-attr-table`,
  `g-priv-files`, `g-priv-cache-path`, `g-priv-cache`. They stay `raw`, keep the
  no-init spelling (which remains legal for `raw` — that is the whole point of
  the pkind split), and lose the reset.
* **4 scalar resets to their own defaults**: `g-ns-seen` (×2, both `0`),
  `g-err-table-used` (`0`), `g-cinclude-collecting` (`0`).
* **3 target-descriptor pre-sets that `target-init` unconditionally
  overwrites** two statements later: `g-target-triple`
  (`"x86_64-pc-linux-gnu"`), `g-target-ptr-bytes` (`8` — already the `defvar`
  default), `g-host-ptr-bytes` (`(sizeof ptr)`). Note in passing that the first
  of these is a string literal `defvar-init-ir` **already accepts today**, and
  the third is a `(sizeof T)` that G-1 would fold — both are moot, because both
  are dead.

Deleting these is not free of consequence: they are compiled code inside the
compiler, so removing them **moves the compiler's own IR** and needs the
standard reconverging refresh. It is a separate, independently verifiable step
from adding the initializers (§5, G-5).

#### C — the residue: one statement

**`(target-init)` stays an explicit call**, and it is genuinely special for two
independent reasons:

1. **It reads argv.** `target-init` (`nucleusc.nuc:11950`) consults
   `g-target-triple-override` and `g-mcpu-override`, which `main`'s argument
   loop sets *before* `compiler-init` runs. An initializer that runs at load
   time, or at the top of `main`, cannot see command-line state. This is
   **configuration, not construction** — a different thing from everything else
   in the function, and the reason "reduce to a few genuinely special cases"
   is the right goal rather than "eliminate entirely".
2. **It sets five globals from one call** — `g-host-target`, `g-target`,
   `g-target-triple`, `g-target-ptr-bytes`, `g-host-ptr-bytes` — which no
   single-value initializer expresses, and which are derived from one another.

So the end state is: `compiler-init` either disappears entirely with
`(target-init)` called directly from `main` after argv parsing, or survives as a
two-or-three-line function whose body is `(target-init)` plus anything a later
stage adds for the same reason. Either satisfies acceptance criterion (A).

#### D — three globals `compiler-init` never touches, and the fourth spelling of the same bug

`g-vtable-table` (`nucleusc.nuc:5629`), `g-boxedfn-table` and `g-dyn-table`
(`union-registry.nuc:396`, `:492`) are all declared
`(ref (Vector (ref …)))` — **non-null** — and are **never initialized in
`compiler-init` at all**. Each is created on first use behind a
`(when (= g-X null) (set! g-X (vector-new-in …)))` guard, and read behind
`(when (= g-X null) (return null))`.

This is the same unsoundness W6 §1.5 describes, in a third spelling: a global
declared non-null that holds `null` for most of the process, with the source
*itself* comparing it to `null` — a comparison that, under Phase F, is being
made against a type that claims it cannot be null. It is also, incidentally, a
live in-tree instance of Option 4 (§3), and its `defvar` comments
(`union-registry.nuc:395`, `:491`) explicitly justify `ref` over `raw` on the
grounds that they are "never explicitly reset" — which is true and is not the
property that makes `ref` sound.

Under G-5 each must go one of two ways, and the choice is a real one:

* **eager**: `(defvar g-vtable-table:(ref (Vector (ref VtableEntry))) (vector-new-in (addr-of g-arena-alloc)))`,
  deleting all six guards. Costs three always-allocated empty vectors.
* **`raw`**: keep the lazy build, re-spell the type honestly. Costs the
  `unsafe/cast`s §2.11 prices.

The same shape covers `g-include-paths` and `g-link-args`
(`nucleusc.nuc:12426`, `:12432`), which are additionally the argv-time
allocation footgun §2.10 resolves.

#### E — the four that are legitimately re-assigned, and stay that way

`g-lbl-tbl` and `g-nundo` (`scope.nuc:139`, `:145`, per function) and
`g-macro-decls` / `g-program-defns` (`nucleusc.nuc:12210-12211`, per module) are
re-created by design at each function/module boundary. A combined
declaration+initialization gives them a valid *first* value — which is what lets
them keep `ref` — and the later re-creations stay exactly as they are. Nothing
in this design says a global may be assigned only once.

#### What this measures

**`compiler-init` initializes 48 globals, and all 48 become a combined
declaration+initialization; 20 of its 51 statements are dead; one statement is
genuinely special.**

The 48 relate to §2.2's census as follows: **44** are members of the 53
non-null element-typed no-init globals, plus `g-arena-alloc` (an `AllocHandle`,
one of the census's 3 non-pointer entries), `g-current-ns` (an elem-less bare
`ptr`) and the two fn-pointer hooks. The remaining **9** of the 53 are
initialized elsewhere: three lazily and unsoundly (§2.12 D), two at argv time
(§2.12 D), and four per function or per module (§2.12 E).

That is the answer to acceptance criterion (A), and it is also the answer to
§8: the runtime half is not optional, because **45 of the 48 are runtime**.

---

## 3. The options

### Option 1 — synthetic entry point

Rename the user's `main` to `@__nucleus_user_main`; emit a real `@main` that
calls a synthesized `@__nucleus_init` (containing every runtime initializer, in
some order) and then tail-calls the user's.

* **Expressible:** all of 1a. `(defvar g:ptr:T (make-thing))` becomes an
  ordinary assignment in a function body, so §2.8's check applies and the
  acceptance criterion is met.
* **Runtime cost:** one extra call at startup; zero per access.
* **Implementation cost:** low. The queue-and-drain shape already exists
  (`MonoJob` + `drain-mono-worklist`, `generics.nuc:2580`, which carries a
  per-job `context` for diagnostics — the exact precedent for capturing
  namespace/source-path/line with each queued initializer). `emit-defn`
  clobbers the per-function streams, so the synthesized function must be
  emitted where none is in progress: the end of `emit-toplevel-forms` at
  `g-toplevel-depth == 1`, beside `check-generic-templates`. That is already
  where `drain-mono-worklist` runs.
* **How it fails:** **it cannot initialize a library** (§2.4). A `.nuch`+`.o`
  library, or a Nucleus object linked into a C program, has no Nucleus `main`
  to wrap. It also has to reproduce `main`'s signature exactly (`():i32` and
  `(argc:i32 argv:ptr):int` both occur) and forward argv, and it breaks the
  "`main` is not special-cased" property (§2.3) — the first special case in the
  compiler's treatment of a user function name.
* **Non-hosted:** works on AVR (avr-libc's crt calls `main` from `.init9`) and
  on any freestanding target that has a `main` at all. This is the *only*
  option in this list that works on AVR.
* **Ruled out of v1 by §4.8**, and this is the decisive objection rather than
  the library one: renaming `main` happens in `emit-defn`, which runs *before*
  the point at which the compiler knows whether any runtime initializer exists
  — so Option 1 cannot satisfy zero-cost-when-unused without a second,
  earlier evaluation of the fold classifier. Held in reserve for AVR only, if
  §4.6's `.ctors` measurement fails.

### Option 2 — `llvm.global_ctors` / `.init_array`

Emit `@__nucleus_init` and register it in `llvm.global_ctors`.

* **Expressible:** all of 1a; same acceptance-criterion story as Option 1.
* **Runtime cost:** one call at startup; zero per access.
* **Implementation cost:** *lower* than Option 1 — one appended global, no
  renaming, no signature matching, no special case for `main`.
* **How it fails:**
  * **AVR: silently.** §2.6. Needs `ptr addrspace(1)` to be *valid at all*, and
    even then the section is never walked. This is the failure mode the repo's
    conventions most consistently warn about — a constant/ABI decision that
    produces no diagnostic. **Answered in §4.6** by refusing to emit it there at
    all: on an AVR triple a non-empty initializer queue is a located error.
  * **Cross-TU ordering is genuinely unspecified.** Within one module, entry
    order is preserved; across objects, the linker's order is what you get.
    (The priority field gives coarse control via `.init_array.NNNNN`.) The
    brief's hope that "one TU" makes this moot is only true for the
    whole-program mode.
  * **JIT: unreachable.** §2.9 — no C API. Moot in practice, but it means the
    mechanism is *structurally* unavailable in one of the compiler's four
    emission contexts, which is worth stating rather than discovering.
* **What it uniquely buys:** the multi-TU case. A library `.o`'s initializers
  run whether the program's `main` is Nucleus, C, or absent.

### Option 3 — compile-time evaluation into a real static initializer

Two very different things share this heading, and separating them is the most
useful thing this section does.

**3a — fold a pure initializer with the existing JIT.** Rejected, on a measured
blocker: a CT/macro JIT module cannot call the program's own `defn`s
(`Symbols not found: [ bump ]`, §2.9). Folding `(make-table)` would require
JIT-compiling the program's functions into the JIT module, which is the "emit
and JIT macro bodies ahead of their file's emission" problem W1d scoped and
declined. It is also *cross-compilation-unsound*: the fold runs in the host
process, so a `--target=avr` build would bake host pointer sizes and endianness
into a constant (`context/conventions.md` already records the `-ffast-math`
version of this hazard). And it can never produce a value that is a runtime
address — which is exactly the arena idiom the user's recorded preference calls
for.

**3b — constant-fold in `defvar-init-ir`, with no JIT at all.** *This is the
option the measurements pick, and the brief does not list it.* Extend the
constant renderer to cover: an `(array T lit…)` (emitted as an
`internal constant`/`global` aggregate plus `@g = global ptr @g.data`, verified
in §2.7), a struct literal of constants, arithmetic over `defconst`s,
`(sizeof T)`, `(as T lit)`, and the address of another global. Plus an
`(array T N)` **type** so a zero-filled fixed-size array global is spellable.

* **Expressible:** all of 1b — 20 of the port's 21 sites, 0 of the compiler's
  53.
* **Runtime cost:** **negative**. Deletes 1401 IR lines / 550 stores per
  137-entry table (§2.7), and deletes the guard branch at every access.
* **Implementation cost:** moderate, and *entirely confined* to
  `defvar-init-ir` plus a new constant-folding helper, plus type-system work for
  `(array T N)`. `defvar-init-ir` is already the documented second
  value-into-a-typed-slot path (`context/conventions.md`), so this is
  strengthening a known chokepoint rather than opening a new one.
* **Interaction with the nullability fix:** direct and clean. `@g = global ptr
  @g.data` is provably non-null; `defvar-init-ir` can accept it under exactly
  the `pkind-flow-check` it already calls, with no new rule.
* **How it fails:** it does not address 1a at all. The compiler's own 53 sites
  are untouched, and W6's hole stays open for them.
* **Ordering:** none. There is nothing to order.

### Option 4 — compiler-generated lazy initialization

Codify the port's `ensure-*`: the compiler emits `if (g == null) g = <init>;`
before every read.

* **Expressible:** all of 1a and 1b. No ordering problem — a cycle is the only
  failure and is detectable at emit time.
* **Runtime cost:** a load + compare + branch at **every** read. In the
  compiler that is **640 sites** (§2.2); in the port, 50 today would become
  every access.
* **Implementation cost:** high and *invasive in the wrong place*. It changes
  `emit-symbol-ref` — the one emitter that cannot be handed a node
  (`context/conventions.md`), with ~98 `emit-node` call sites feeding it — and
  it must be mirrored in `node-type`, which is the repo's standing lockstep
  hazard.
* **How it fails, and it is a hard failure:** the guard is `g == null`, so it
  cannot express "initialized to null" and it cannot be used for a non-pointer
  global at all. It also re-introduces reentrancy: an initializer that
  (transitively) reads its own global recurses. And it *weakens* the payoff —
  a lazily-initialized global is non-null only *after* the guard, which is a
  flow fact, i.e. exactly the W6 machinery this is supposed to avoid needing.
* **Verdict: reject.** It is the option with the worst cost/benefit on every
  measured axis, and it is the pattern the port adopted only because nothing
  better existed.

### Option 5 — status quo, documented

Keep an explicit `init` function, as the compiler does, and document it.

* **Cost, stated honestly:** W6's §3.4 hole stays open in the no-init spelling
  *forever* — an author blocked by the `null` rejection gets the old unsound
  behavior back by deleting one word. The port pays 21 guards / 50 branches / 9
  useless ones, and 1401 IR lines per constant table. The nullability lattice
  keeps a documented lie: `ptr:T` means non-null except at a global.
* **The cheap variant, and why it is not free:** re-spell the 53 as `raw:T` and
  close the hole today. Measured at **249 flow violations across 197 lines and
  10 files** (§2.11) — i.e. ~200 new `unsafe/cast`s in the compiler's own
  source, in a stage whose sibling document (`nullability.md` §3) identifies
  2113 `unsafe/cast`s as *the* headline defect. Adding 200 more to the
  compiler's own source to close a nullability hole is the wrong direction.

### Option 6 — reject the no-init spelling and require an initializer, with 3b + 2 supplying one

This is not a separate mechanism; it is the *acceptance criterion* expressed as
a rule, and it is what §5 stages. Recorded here so the option list is complete:
the language change is "a `defvar` whose type is a `PTR-REF` with an element
type must have an initializer", and the other options are the different ways to
be able to write one.

### Option 7 — placeholder, then substitute *(last resort; an explicitly-marked code smell)*

**Available by ruling (§Revised, item 1), for the case where an initializer
genuinely cannot be computed at the declaration point.** Declare the global with
a *placeholder* value that satisfies the type — typically the address of a
static sentinel object of the right type — and overwrite it with the real value
at the first point the real value can be computed.

```lisp
(defvar g-sentinel:T)                        ; a real, zero-filled T
(defvar g:ptr:T (addr-of g-sentinel))        ; non-null by construction
… later …
(set! g (make-thing))                        ; the substitution
```

* **Expressible:** anything, including the argv-dependent case §2.12 C names.
* **What it buys, and it is exactly one thing:** the *declared type* becomes
  honest. `g` is `ptr:T`, is genuinely non-null from load time, and the flow
  checker's claim about it is true. A reader that runs before the substitution
  gets a well-typed sentinel rather than a segfault.
* **What it costs, and why it is a smell:** it converts a crash into *wrong
  answers*. Reading `g` before substitution is now silent and plausible instead
  of loud. That is the same failure class §2.10 called out for the zero-filled
  `AllocHandle`, deliberately adopted. It also costs a sentinel object per
  placeholder.
* **Rule for using it:** the placeholder must be a *distinguishable* value where
  that is possible (a sentinel the code can assert against), the substitution
  must be a single named site, and both must carry a comment saying this is the
  placeholder route and why nothing else worked. If it appears more than a
  couple of times, the right response is to fix the thing that made an
  initializer inexpressible, not to add another placeholder.
* **Where this design expected to need it, and does not:** `g-arena-alloc`.
  §2.10 shows it is a constant, so the placeholder route is **not spent** there.
  As of this revision **no site in the compiler needs Option 7**; it is
  available for the case a future one does.

---

## 4. Cross-cutting questions

### 4.1 Ordering — settled policy, and its consequences

**Decided (2026-08-01): order may matter for initializers, and reordering the
compiler's own source to make an initializer expressible is sanctioned.** This
section states the resulting policy and what follows from it. It is no longer a
defence of an ordinal rule against W1's retirement of one, because the question
is not open — but the distinction between the two is real, load-bearing, and
belongs in `docs/`.

**The rule: initializers run in the order their `defvar` forms are *reached
during emission* — source order within a file, import depth-first order across
files.**

**Why this is not the rule W1 retired.**

* W1 retired an ordinal rule for **name resolution** — a static property that
  has one right answer independent of order, so an order-dependent answer was
  simply a bug. `docs/toplevel.md` now says *"an import establishes
  reachability, not visibility."*
* **Initialization is inherently sequential.** Some order must exist; C++ has
  exactly this rule within a translation unit and leaves it unspecified across
  them. Making it depend on emission order is not a regression to what W1
  removed — but a design that made *resolution* depend on it would be, and
  §4.2's prerequisite (G-0) exists to prevent that.

**Consequences, accepted:**

1. **Reordering imports can change program behaviour**, where today it cannot
   change anything. This is the price, it is paid knowingly, and G-4's
   forward-reference diagnostic is what keeps the *detectable* half of it from
   being silent.
2. **Reordering the source is a legitimate fix.** Where a global's initializer
   names another global that is declared later, the answer is to move the
   declaration, not to invent a mechanism. Two concrete instances are already
   known: `g-arena-alloc` at `nucleusc.nuc:182` must move above the first
   registry at `:144` (§2.10), and `g-binops`/`g-generics` are *already* in the
   right order (`:266`/`:271`, §2.12). This is a two-line edit, not a design
   problem.
3. **A cycle between two initializers is not fixable by reordering**, and is a
   compile error under §4.2 when it is syntactically visible.
4. **Bucket 1b is unaffected.** A constant initializer is applied by the
   loader/linker before any code runs, so it has no order at all. This is why
   §5 ships the static half first: it buys the largest single population
   (including `g-arena-alloc`) with zero ordering surface.

**The live precedent, and this design's effect on it.** `defvar`, `defconst`
and `defenum` names were *already* import-order dependent (§2.5), with a
diagnostic that falsely claimed the name is not defined anywhere. This design is
**not orthogonal** to that: G-0 (§5) fixes it, and must, because an initializer
expression naming another global would otherwise fail at name resolution before
any ordering question arose. Fixing it also *narrows* the ordinal surface: after
G-0 the only thing import order affects is initializer *sequencing*, not what
resolves — which is exactly the line W1 drew. **G-0 landed 2026-08-01**, so that
narrowing is now a fact rather than a plan: nothing in the language is
order-dependent for *resolution* except a string-path import, and the ordering
policy above governs sequencing alone.

### 4.2 Dependencies between initializers

`(defvar a (f))` where `f` reads global `b`.

* **Detected?** Only when the reference is *syntactic*. A direct
  `(defvar a (+ b 1))` is checkable: `b`'s `defvar` either precedes `a`'s in
  emission order or it does not. A reference laundered through a call — which
  is the compiler's own shape, `(vector-new-in (addr-of g-arena-alloc))` — is
  **not detectable** without callee effect summaries, which
  `nullability.md` §9 already declares a permanent non-goal for the same reason.
* **Recommended rule:** a `defvar` initializer that *syntactically names* a
  global whose `defvar` has not yet been reached is a **compile error**, naming
  both sites. Everything else is unchecked and documented as such. This is the
  same honest boundary W6 §4.5 draws for F1: conservative on what it can see,
  silent on what it cannot, and explicit about which is which.
* **A genuine cycle** (`a` reads `b`, `b` reads `a`, both syntactically) is
  caught by the same check — the second one always references a not-yet-reached
  global. Through calls it is not caught, and becomes a read of a zero/null
  global. Documented, not diagnosed.
* **Non-goal:** a computed topological order. It needs the interprocedural
  analysis above.

### 4.3 The payoff test

| Option | `(defvar g:ptr:T (make-thing))` typechecks non-null? | lets `(defvar g:ptr:T)` be rejected? |
|---|---|---|
| 1 synthetic entry | **yes** (§2.8 — it is an ordinary `set!`) | yes, for whole programs; **no** for a library |
| 2 `global_ctors` | **yes** | yes, including libraries; **not on AVR** |
| 3a JIT fold | no (cannot produce an address) | no |
| **3b constant fold** | **yes** for 1b — `@g = global ptr @g.data` is provably non-null | yes, for every 1b global; leaves 1a open |
| 4 lazy | only *after* the guard — a flow fact, not a declared one | weakly; needs W6 machinery to be useful |
| 5 status quo | no | no |
| 7 placeholder | **yes** — the sentinel address is genuinely non-null | yes, but converts a crash into a wrong answer |

**2 + 3b together reach the criterion on every target and every output mode**
(with 1 as the AVR fallback if §4.8's `.ctors` question resolves against
append-only registration). No single one does.

### 4.4 Migration — now the point of the exercise, not a follow-on

The first draft recommended *not* migrating the compiler in the same change that
adds the feature. That is superseded: **eliminating `compiler-init` is
acceptance criterion (A)**, so the migration is the deliverable. What survives
from the first draft is the sequencing — it is still the last step, and still
independently verifiable.

**The compiler's sites.** §2.12 is the full accounting: 48 globals gain a
combined declaration+initialization, 20 statements delete, `target-init`
remains. 51 of the 53 non-null no-init globals have exactly one `(set! …)` site
in the whole tree (§2.2), so the great majority is mechanical. The parts that
are not:

1. **Six value-returning builders** to write (§2.12 A2's table) — `make-ptr-type`
   for the three pointer-kind singletons, and one each for the deferror tables,
   the two name sets, `g-binops`, `g-blanket`, `g-rmacros`. Each is a small pure
   `defn`; this is the sanctioned source restructuring, not a workaround.
2. **One source reorder**: `g-arena-alloc` (`:182`) above the first registry
   (`:144`). §2.10 — and *only* a reorder, since the handle is now a constant.
3. **Three lazily-built erasure registries** (§2.12 D) must be decided one way
   or the other — eager `defvar` initializer, or honest `raw`. They are the
   fourth spelling of W6 §1.5's hole and G-5 cannot close it without ruling on
   them.
4. **`g-fnty` / `g-boxedfn-table` / `g-dyn-table` cross the file boundary**
   (§2.12 A2's last paragraph): their initializers move into `type-mangle.nuc` /
   `union-registry.nuc`, which must reach the collection constructors at their
   own emission point.
5. **A positive `ALLOC-ARENA` assertion.** The constant initializer makes the
   arena handle correct from load time, which removes the ordering hazard — but
   the failure mode of getting it wrong is still silent, so the migration needs
   a test that asserts the registries are arena-backed, not just a green
   `make test`. This test is *also* the regression marker for the
   `add-include-path` inconsistency §2.10 fixes.
6. **The deletions move the compiler's own IR** and need the standard
   reconverging refresh — they are compiled code, not emitted output.

**The port's 13 sites.** 12 of 13 are 1b and become one-line `defvar`s under 3b
alone, deleting 20 `ensure-*` functions, ~50 guard call sites and ~2500 lines of
table-building IR. The 13th (`s_sound`) keeps an explicit init or becomes a 1a
initializer. **Per the ruling, this conversion is not scheduled here and is not
a gate on anything.** It is worth doing when the static half has landed, as a
second corpus for the same machinery; until then the port keeps the no-init
spelling, which is what it currently uses.

### 4.5 Output modes with no `main`

| Mode | Has `main`? | What must happen |
|---|---|---|
| `--emit-llvm` / `-c` / `-o`, entry file with `main` | yes | Option 2 (Option 1 would also work here, and only here — but is ruled out of v1 by §4.8) |
| `--emit-llvm` / `-c` on a **library** (no `main`) | **no** | Option 2 only |
| `--emit-nuch` + consumer links the `.o` | consumer's `main` is in another TU | **Option 2 only** (§2.4) |
| `--emit-cheader` + C consumer | C's `main` | **Option 2 only** |
| REPL | no — per-form evaluation | run the initializer immediately, at the `defvar`. `repl.nuc:148-169` already JITs each `defvar` into its own module and appends an `external global` to the preamble; a synthesized nullary init function JITed and called right there matches the REPL's existing semantics exactly. |
| `compile-time` block | n/a | **nothing.** §2.9 — a CT module has no program globals or `defn`s. If a CT block ever names an initialized global today it already dies `use of undefined value '@g'`; that message should become a W1d-style located diagnostic, not a silent zero. |
| `defmacro` JIT module | n/a | same as above |

### 4.6 Non-hosted targets

* **riscv64-linux** — hosted glibc, `.init_array` works, no special case.
* **AVR** — `.init_array` is emitted and never run (§2.6), and §4.8 rules out
  the synthesized-`main` route as the *primary* mechanism because it is not
  append-only. The decision, and it is the simplest one available:

  > **On a triple with no working append-only startup mechanism, a non-empty
  > initializer queue is a located error**, naming the `defvar` that made it
  > non-empty and saying that this target requires explicit initialization.
  > Never a dead section, never a silent no-op.

  This is fully zero-cost (a program with no runtime initializer is unaffected,
  which is every AVR program that compiles today), fully loud, and it unblocks
  everything else without waiting on an AVR measurement. It matches the
  first draft's own closing position for AVR — *"the important property is that
  it **fails loudly** if unreachable, not that it is fast"* — and AVR's v1
  profile is `(exclude-prelude)` freestanding, where a runtime initializer is
  rare to begin with.
* **The AVR mechanism is deferred, not abandoned**, and there is one specific
  thing to measure: whether a global placed in `section ".ctors"` with the
  word-address relocation avr-gcc's linker script collects is walked by
  `__do_global_ctors`. If it is, AVR gains an append-only mechanism identical in
  shape to `llvm.global_ctors` and the located error is replaced. If it is not,
  the synthesized-`main` route returns as the only option and pays §4.8's
  early-decision cost. **This is the one measurement this design leaves open.**
* **Mechanism selection belongs in a triple-keyed resolver**, matching the
  established pattern `context/build.md` documents for `reloc-for-triple` /
  `cpu-for-triple` / `features-for-triple` / `abi-for-triple`: add
  `ctor-mechanism-for-triple` beside them rather than an inline `strncmp` at the
  emission site. Its v1 answers are exactly two — `global_ctors` and `none` —
  which is a much smaller split than the first draft's per-triple
  `global_ctors`-or-`main` fork, and §4.8 is why.

### 4.7 Bootstrap

Every stage in §5 is gated on emitting **nothing new** for a unit with no
non-constant initializer:

* G-0 (value-name prescan) registers names earlier but must not move any
  emission. W1a is the precedent and the warning: its own registration-only
  change still moved 44 `%Name = type {…}` lines and needed the diff proven
  inert before reconverging. Expect the same class of shift and the same proof
  obligation.
* G-1/G-2 (constant folding, `(array T N)`) fire only where today's
  `defvar-init-ir` *dies*. Byte-identical by construction.
* G-3 (`@__nucleus_init` + registration) is emitted only when the unit has ≥1
  runtime initializer. Today no unit does, so the compiler's own IR cannot move.
* G-5 (migrating the compiler's 53) **will** move the compiler's IR
  substantially and is a deliberate reconverge, per `context/build.md`'s
  `make clean && make && make update-bootstrap && make clean && make && make
  bootstrap` cycle.

One bootstrap hazard to plan for: a **new top-level form** would be a
chicken-and-egg break (`context/build.md`: "a new special-form dispatch symbol
the OLD boot doesn't know" needs a 2-stage manual bootstrap), because
`emit-toplevel-forms`' dispatcher is a static `case hp` chain. This design
deliberately introduces **no new top-level head symbol** — everything rides on
the existing `defvar`.

### 4.8 Zero cost when unused — a hard requirement

**Decided (2026-08-01), and it is new.** A program with **no** runtime
initializer must emit **nothing**: no `@__nucleus_init`, no `llvm.global_ctors`
global, no `.init_array` entry, no synthesized `main` wrapper, no extra symbol
of any kind. Stated reason: microcontroller binary size, where this is a real
constraint. It is also what keeps the bootstrap byte-identical through G-3
(§4.7) — today no unit in the tree has a runtime initializer, so today's IR
cannot move.

#### How "is it used?" is determined, and where

**The determination is: "is the runtime-initializer queue non-empty?"** A
`defvar` initializer is queued exactly when `defvar-init-ir` — after G-1/G-2's
constant folding — cannot render it as a constant. That is the same single
predicate that decides whether an initializer is bucket 1a or 1b, so there is no
second classifier to drift out of step with the first
(`context/conventions.md`'s standing rule for this function: call the shared
predicate, do not re-derive it).

**Where it is known: at `emit-toplevel-forms`, `g-toplevel-depth == 1`**
(`nucleusc.nuc:11129-11132`), beside `check-generic-templates` and
`drain-mono-worklist`. Every top-level form of every reachable file has been
walked by then, so the queue is complete and the answer is **exact** — not an
over- or under-approximation.

**Therefore every artefact of the runtime half is emitted at that one point and
nowhere else.** An empty queue means the drain returns immediately and no
statement in the compiler has written a byte. This is the same discipline the
mono worklist already follows, which is why G-3 can reuse its shape.

#### The consequence that changes the design: registration must be append-only

A mechanism qualifies only if it can be emitted *entirely* at the drain point,
appending to the module. Checked against the candidates:

| Mechanism | Append-only at drain? |
|---|---|
| `llvm.global_ctors` | **yes** — one appended global |
| a `section ".ctors"` global (the AVR candidate, §4.6) | **yes**, if it works at all |
| REPL: JIT and call the initializer at the `defvar` | **yes** — there is no queue; each form is its own unit (§4.5) |
| **synthesized `main` wrapper (Option 1)** | **no** |

**Option 1 fails the requirement as stated**, and this is the sharp finding.
Wrapping `main` means emitting the user's entry function under a different
symbol (`@__nucleus_user_main`), which happens in `emit-defn` — typically far
*earlier* than the drain, and `main` is only conventionally the last form in a
file, never guaranteed to be. So the decision to rename would have to be made
before the queue's emptiness is known.

Two ways out, and the design takes the first:

1. **Do not use a `main` wrapper.** Use only append-only mechanisms, and on a
   triple that has none, make a non-empty queue a located error (§4.6). This is
   what §5's G-3 specifies. It costs one target's runtime-initializer support
   until the `.ctors` question is measured, and it buys an exactly-zero-cost
   guarantee with a one-line proof.
2. **Compute the flag in the prescan** — run the *same* fold classifier over
   every reachable file's `defvar` forms during W1a's whole-graph walk, and let
   `emit-defn` consult the result. This is viable (the walk already visits every
   top-level form) but it evaluates the classifier twice, at two different
   points in the pipeline, with two different amounts of environment available —
   the drift hazard this repo's `node-type`↔`emit-node` lockstep exists to warn
   about. **Held in reserve for the case AVR's `.ctors` route fails.**

**Net effect: the requirement simplifies the per-triple mechanism split rather
than complicating it.** The first draft needed a two-way fork
(`llvm.global_ctors` on hosted, synthesized `main` on AVR) *and* Option 1's
whole apparatus — `main`-signature matching for both `():i32` and
`(argc argv):int`, argv forwarding, and the first special case in the
compiler's treatment of a user function name (§2.3, §3 Option 1). Zero-cost
deletes all of that from v1. `ctor-mechanism-for-triple` returns
`global_ctors` or `none`.

#### What the AVR measurement in §2.6 means under this requirement

§2.6 measured that LLVM's `.init_array` lands in RAM on AVR and
`__ctors_start == __ctors_end`, so the constructor is emitted, linked, occupies
RAM, and never executes — with no diagnostic. Under zero-cost that measurement
is *more* decisive, not less: emitting a dead constructor is not merely wrong,
it spends exactly the resource the requirement exists to protect. The rule
"never emit a mechanism that does not run" and the rule "emit nothing when
nothing needs it" are the same rule seen from two sides.

---

## 5. Recommendation and staging

**Recommended: Option 3b first, then Option 2 as the single append-only runtime
mechanism, with Option 6's rejection rule and the `compiler-init` elimination as
the closing step. Reject Options 3a and 4. Option 1 is held in reserve for AVR
only (§4.6, §4.8); Option 7 is the last resort no current site needs.**

The reasoning, compressed: bucket 1b needs no runtime mechanism at all,
*deletes* code, has zero ordering surface, and already covers the sharpest
migration blocker (§2.10) plus all the external evidence — so it ships first
regardless. The runtime half is then **required**, not optional, because 45 of
the 48 globals `compiler-init` constructs are runtime (§2.12) and eliminating
`compiler-init` is the goal (§8). Option 2 is the only mechanism that is
append-only on every output mode a hosted triple has, which §4.8 shows is the
binding constraint.

Staged the way Stage 10's Phase F flip was staged — each step independently
verifiable, the flip last:

### G-0 — value names resolve on reachability *(prerequisite, standalone value)*

Extend W1a's whole-graph walk (`prescan-imported-signatures`) to register
`defvar` / `defconst` / `defenum` **names** (and `defconst`/`defenum` *values*,
which are literals and already available at prescan time). Registration only —
no emission moves, so the `@g = global` lines stay in place.

*Verify:* §2.5's four probes pass in both orders and same-file forward; the
misleading "not defined anywhere in this compilation unit" no longer fires for a
name that is in the unit; `make bootstrap` diff, if non-empty, proven inert the
way W1a's 44 type lines were. **This is shippable on its own** and fixes a
finding the port reported independently (§3.5, §3.2).

---

#### G-0 as built — 2026-08-01

**Done.** `prescan-value-names` + three per-definer helpers
(`prescan-defvar-name`, `prescan-defconst-name`, `prescan-defenum-names`), all in
`src/nucleusc.nuc` immediately after `prescan-defn-signatures`. Called from
exactly two places, both under the guard W1a already established: inside
`prescan-imported-signatures`' per-file block (after `prescan-defn-signatures`,
before the recursion) and inside `emit-toplevel-forms`' `(= sigs-done 0)` branch
(which is what covers the unit's **root** file, on no import list, and therefore
the same-file forward reference). `.nuch` headers and C-header string imports stay
excluded for free — both skips are path-level tests in the walk this rides on, and
`emit-nuch-header`/`emit-nuch-import-forms` never route through
`emit-toplevel-forms`.

**All four §2.5 probes pass**, each compiled, linked and run:

| Probe | before | after |
|---|---|---|
| `defn` body reads a `defvar` declared later in the same file | `error: undefined: gv` | exit 7 |
| `(import cb)` then `(import ca)`, `defconst` | exit 42 | exit 42 |
| imports swapped | `error: undefined: MYK` | exit 42 |
| same shape, `defenum` member / `defvar`, both orders | error in one order | exit 1 / exit 33, both orders |

**Two design premises were wrong, both in the safe direction.**

1. **Registration idempotency was not a problem to solve here.** W1a's per-path
   skip exists because `generic-register-method` *appends a Method and
   `finalize-generics` then compares them*, so a second prescan is a duplicate.
   `scope-define` appends a *binding* and `scope-lookup` scans backwards; a
   second identical definition is inert. So the prescan copy and the emitter's
   copy coexist by construction, no new guard was needed, and **no duplicate
   check was relaxed**: two `defvar`s of one name still emit two
   `@g = global` lines and LLVM still rejects them (measured, unchanged), and
   two `defn`s of one signature still hit `finalize-generics`. Worth recording
   that duplicate `defconst`s across two files were *already* a silent last-wins
   before this change — that is a pre-existing gap, not one G-0 opened, and it is
   unchanged.
2. **G-0 makes W1d's cycle diagnostic for constants obsolete outright**, as the
   brief suspected. The walk visits both members of a cycle, so a `defconst`,
   `defenum` member and `defvar` from a cycle partner now all compile, link and
   return the right value (42 / 2 / 77). `cycle-definer-message`'s note was
   rewritten (it claimed "not macros, constants or enum members"; it now names
   macros, `deferror` ids and `extern` declarations, which is what actually
   remains), and the two units that pinned the old behaviour were **replaced**,
   not deleted: `w1d-cycle-deferror-diagnosed` keeps the diagnostic pinned for a
   name a cycle still cannot carry, and `run_g0_cycle_values` pins the three that
   now work, by value.

**A latent silent wrong answer fell out, unrelated to ordering.** A `defconst-`
referenced from *earlier in its own file* resolved, before G-0, to another file's
**public** constant of the same spelling — compiled clean and returned 7 instead
of 61. W5e's key scheme was right; the private key simply did not exist yet when
the reader was emitted, while the public one did. G-0 fixes it because the
prescan arms `g-defining-private`. Pinned by `g0-private-const-forward`.

**Bootstrap: reconverged, and the diff was proven inert first.** The first pass
diffed by **48 type-definition lines (24 moved), and nothing else** — front-loading
`defvar` type resolution front-loads the parametric-instance stamps that queue
`%Name = type {…}` lines, exactly the W1a class. Proof, before any
`make update-bootstrap`: zero non-`%Name = type` lines differ; sorting the
type-definition lines makes the two files byte-identical; and the new compiler is
a fixed point independently of the stale boot (`build/nucleusc` → stage2.ll →
stage2 binary → stage3.ll, byte-identical). Old-vs-new `--emit-llvm` sweep of
every `examples/`, `lib/`, `lib/avr/` and `tests/fixtures/` program against a
compiler built from HEAD's source: **203 byte-identical, 1 type-order-only
(`examples/fn-ptr-union.nuc`, one anonymous-union line moved), 0 genuinely
different, 0 regressed**, 2 newly compiling (the new example, and
`tests/fixtures/w4a-defvar-forward.nuc`, whose header comment left this question
open for W1 and has been updated). Post-reconverge `make bootstrap` is
byte-identical; `make test` 328 → **347 PASS / 0 FAIL**; `make abi-test` and
`make layout-test` green.

**Deliberately not built** (each a separate question, none needed by G-1..G-5):

* **`deferror` and `extern` are not prescanned.** A `deferror`'s dense id is
  allocated in emission order and an `extern` is a declaration with its own
  emitter; neither is a value *binding*. They are what keeps
  `cycle-definer-message` reachable, which is why the diagnostic still has a
  pinning test.
* **`g-enumdefs` is not front-loaded.** `prescan-defenum-names` registers the
  member *bindings* only, not the EnumDef table `match` exhaustiveness reads —
  that is emission-time state keyed by the enum's type name, capped by
  `MAX-ENUMS`, and front-loading it would move `g-enumdefs` order for no G-0
  benefit. A `match` over a cross-file enum is unchanged.
* **String-path imports (`(import-use "lib/foo.nuc")`) and `.nuch` headers are
  still ordinal**, for values exactly as they already were for functions —
  measured both ways, so G-0 introduces no asymmetry between the two kinds of
  name. Neither prescan walks a NODE-STR `.nuc` path, and the sig walk skips
  `.nuch` deliberately. Both are noted in `docs/toplevel.md`. One thing improved
  for free: because the root/unwalked-file branch of `emit-toplevel-forms` now
  runs the value prescan, a *cycle* written with string paths resolves its own
  file's constants.

  **These two are the whole remaining surface of W9 defect 6's misleading
  message, and they are why the interim W1c-style note was NOT added.** In the
  post-G-0 tree the message fires for a value name that is genuinely absent (the
  message is true), one defined only in an unreached file (W1c's note already
  names it), one from a cycle partner's macro/`deferror`/`extern` (W1d's note
  already explains it), or one behind these two spellings — where the right fix
  is to extend the walk (or to phrase a note about *how* the file was imported),
  not to add a third value-specific note that whoever extends the walk would
  then have to remove. Filed as a **W1 follow-up**, not a W8 one, because it
  affects `defn` identically.
* **A `defvar`'s type must now be reachable at prescan time**, joining `defn`
  signature types under W1c's §2.7 rule. Measured against the whole tree: no file
  in `src/`, `lib/`, `examples/` or `tests/fixtures/` regressed.

### G-1 — constant expressions in `defvar-init-ir`

Fold, in the renderer, with no JIT: arithmetic and bit ops over integer literals
and `defconst`/`defenum` names; `(sizeof T)`; `(as T lit)` including
`(as CStr "…")` (which W5c's progress note recorded as out of scope under "the
general expressions-aren't-literals rule" — this is the rule changing, not an
exception to it); the address of another global; `(char "x")` (already present).

*Verify:* fixtures for each shape; the existing `int-literal-fits` /
`float-literal-ir-at` / `pkind-flow-check` calls still fire on the folded value —
per `context/conventions.md`'s standing rule for this function, **call the
shared predicate, do not re-derive it**. `make bootstrap` byte-identical (every
new shape is one that dies today).

---

#### G-1 as built — 2026-08-02

**Done.** One evaluator plus two renderer branches, all in `src/nucleusc.nuc`
immediately above `defvar-init-ir`, plus one predicate extracted into
`src/type-utils.nuc`.

| Piece | Where | What |
|---|---|---|
| `const-fold-int` | `nucleusc.nuc:8769` | node → i64. Returns 1/0; a *malformed* constant expression dies here instead. |
| `cfold-add/sub/mul/div/rem/shift` | `nucleusc.nuc:8659`–`8706` | overflow/zero/shift-range-checked i64 primitives |
| `cfold-i64-min` / `-max` / `-overflow` | `nucleusc.nuc:8650`–`8657` | bounds and the shared diagnostic |
| `cfold-op-code` / `cfold-apply` | `nucleusc.nuc:8713`, `8728` | the foldable operator table |
| `cfold-sizeof` | `nucleusc.nuc:8753` | `(sizeof T)` via `abi-sizeof` |
| `defvar-addr-of-ir` | `nucleusc.nuc:8867` | `(addr-of g)` → `@g` |
| renderer: `(as T x)` at a ptr-like dest | `nucleusc.nuc:9060` | recursion + `pkind-flow-check` |
| renderer: `(addr-of g)` | `nucleusc.nuc:9074` | |
| renderer: integer fold + `int-literal-fits` | `nucleusc.nuc:9077` | |
| `as-int-narrowing` | `type-utils.nuc:397` | **shared** with `emit-as` step 5 (`nucleusc.nuc:3085`) |

**What folds.** Arithmetic `+ - * / %` (including unary `-`); bit operations
`bit-and bit-or bit-xor bit-shl bit-shr bit-not`; over integer literals,
`defconst`/`defenum` names, `(char "x")`, `(sizeof T)`, and `(as IntT x)` — to
any depth, in any mix. At a pointer-like destination, `(as PtrT x)` (which is
what makes `(as CStr "…")` legal) and `(addr-of other-global)`. Every shape is
covered by `examples/g1-const-init.nuc`, which **prints** each folded value: the
characteristic failure of a constant folder is the wrong number, and an exit-0
compile cannot see it.

**W5c's `(as CStr …)` note is superseded, not excepted.** `design/stage15-
stress-test/progress.md`'s W5c entry records `(as CStr "…")` in an initializer as
deliberately out of scope under "the general expressions-aren't-literals rule".
G-1 *is* that rule changing. The W5c entry is left as the accurate historical
record of what W5c decided; the supersession belongs at the stage level.

**What deliberately does not fold, and why.**

* **Float arithmetic.** `(defvar g:f32 3.14)` already works and re-renders at the
  target width through `float-literal-ir-at`; `(+ 1.0 2.0)` does not fold. Two
  reasons: folding target FP in the compiler process is the `-ffast-math` hazard
  `context/conventions.md` records (removed from the Makefile in W2d and must not
  come back), and the only interesting `as` spelling is already rejected in value
  position — measured: `(as f32 1.5)` dies `as: lossy conversion from f64 to f32`,
  because a float literal is f64 and `as` never narrows. So a float `as` fold
  could only have *diverged* from the value path.
  **Amended 2026-08-10 (Stage 15 W9 item 8).** "`as` never narrows" no longer
  holds for integers: `as` now narrows a literal that provably fits, and the
  two askers were kept in step by giving `as-int-narrowing` the literal channel
  (`const-fold-int` passes the folded value unconditionally, since everything
  reaching it is a known constant). The float clause above is still accurate as
  written — `(as f32 1.5)` is still rejected — and is now filed as W9 item 30,
  where the remark that a float fold "could only have diverged" becomes the
  argument for fixing the value path first.
* **Comparisons, `and`, `or`, `not`.** They produce `i1`, a second value domain
  the folder does not model, and `_and`/`_or` are short-circuit special forms
  rather than binops. `(defvar g:bool true)` is the spelling.
* **Aggregates** — struct literals, array literals, the `(array T N)` type. That
  is G-2, deliberately untouched.
* **Anything requiring evaluation** — a call, an allocation, a read of another
  global's *value* (as opposed to its address).

**Typing discipline: a folded result is an untyped integer literal of that
value.** No result *type* is tracked through the fold. This is a deliberate
rejection of the obvious alternative (carrying a `Type` alongside the i64), which
would have needed the folder to re-derive `binop-result-type`'s rule for operator
results — precisely the mirrored-logic shape W2a exists to delete. Consequences,
both stated rather than incidental:

* the W2b range gate is exactly the literal's: `(defvar g:i32 (* BIG 2))` is
  rejected by the same `int-literal-fits` call that rejects
  `(defvar g:i32 6000000000)`, in the same wording family;
* `(sizeof T)` loses its `usize` provenance inside a fold, so
  `(defvar g:i32 (as i32 (sizeof S)))` is accepted here while the value-position
  `(as i32 (sizeof S))` is refused as lossy. The fold is *better informed* (it has
  the number), so this is permissive, never wrong. The converse wart is
  `(as i8 5)`, refused in both positions because `int-literal-type 5` is `i32` and
  `as` compares widths, not values — an `emit-as` over-strictness that predates
  G-1 and that the shared predicate faithfully reproduces rather than papering
  over on one side only.

**Overflow, division by zero, shift overflow — the three decisions.**

* **Overflow: fold in i64, reject at the fold, then range-check the result at the
  destination.** Both halves are real. `(* 2000000000 3)` = 6000000000 is
  computed exactly and then refused by `int-literal-fits` at an `i32`
  destination; `(* 4000000000 4000000000)` leaves i64 and is refused *during* the
  fold with `constant initializer overflows 64-bit signed integer arithmetic`.
  Silent wrapping happens in neither. The overflow tests run **before** the
  operation, not after: the compiler's own `+`/`-`/`*` emit `add nsw`/`sub
  nsw`/`mul nsw`, so inspecting an overflowed result would be inspecting LLVM
  poison. The four sign quadrants of the multiply test reduce to one comparison
  against a truncating quotient (exact, since truncation toward zero is floor for
  a positive quotient and ceiling for a negative one), with `-1 * INT64_MIN`
  screened first because the quotient test for it traps.
* **Division/remainder by zero: a located compile-time error**
  (`division by zero in constant initializer` / `remainder by zero …`). Not
  executed — executing it would SIGFPE the compiler — and not emitted as poison.
  `INT64_MIN / -1` is refused as overflow; `INT64_MIN % -1` answers `0` directly
  (mathematically correct, and the instruction traps).
* **Shift count outside [0,64): a located compile-time error.** LLVM's answer is
  `poison`, so the runtime path has no value to be consistent with; refusing is
  strictly more informative than baking poison into a constant.

**The three inherited checks still fire, each pinned at a real `file:line:`.**

| Check | Fixture | Diagnostic |
|---|---|---|
| `int-literal-fits` on the folded value | `g1-fold-range.nuc:5` | `constant expression value 6000000000 does not fit i32` |
| `pkind-flow-check` through the new `as` branch | `g1-as-null-launder.nuc:7` | `raw pointer where non-null (ref ...) is required` |
| `as-int-narrowing` (shared with `emit-as`) | `g1-as-lossy.nuc:5` | `as: lossy conversion from i64 to i32` |

`float-literal-ir-at` is untouched and unbypassable: there is no float fold, so
every float initializer still reaches the existing branch (verified —
`(defvar g:f32 3.14)` still emits `float 0x40091EB860000000`).

**One check G-1 had to ADD that the value path does not need.** `emit-sizeof`
lowers to a GEP over the LLVM *named* type, which LLVM resolves from a
`%Name = type {…}` line emitted anywhere in the module. The fold cannot: it reads
the compiler's own field table via `abi-sizeof`. That is exactly the split
`src/type-utils.nuc`'s W1d note warns about, so `cfold-sizeof` calls
**`reject-cycle-pending-layout`** as well as `reject-opaque-type` — without it a
`(sizeof S)` across an import cycle would have silently folded to **0**. Verified:
it now reports `sizeof: 'CA' has no layout at this point` with W1d's cycle note.

**Cross-compilation.** `abi-sizeof`/`type-size` key off `g-target-ptr-bytes`, the
**output** target, so the fold is target-correct by construction — measured:
`(defvar g:i32 (sizeof ptr))` emits `2` under `--target=avr-unknown-unknown` and
`8` on the host. (One residual, pre-existing and not introduced here: inside a
`compile-time` block the JIT module runs on the *host* while `type-size` still
answers for the output target. Every `type-size` consumer already has that
property; no shape in the tree hits it.)

**Verification.**

* `examples/g1-const-init.nuc` compiles, links and runs, and cross-checks every
  folded `sizeof` against the runtime `sizeof` in the same program — it prints
  `agree` per type, so a divergence between `abi-sizeof` and LLVM's layout fails
  the suite rather than passing quietly. All four agree today.
* Four cross-file units (`run_g1_fold_cross_file`) compile, link and run,
  asserting the exit status: a constant folded from a not-yet-emitted file in
  **both** import orders (42), a `defconst-` folded from earlier in its own file
  while another file defines the same spelling publicly (45, not 63), and
  `(addr-of g)` across files where the target is defined later (88).
* Nine `run_reject_at` fixtures, each pinned at a real `file:line:`.
* **`make test` 347 → 361 PASS / 0 FAIL** (the brief's baseline of 346 was one
  low; 347 measured directly before any G-1 change, matching G-0's report).
  `make abi-test` and `make layout-test` green.
* **`make bootstrap` byte-identical on the first pass**, as predicted — every
  shape G-1 adds is one that died before it, so no program's IR could move.

**One pre-existing soundness gap this made visible** (reported, not fixed —
fixing it would change the value path, which was out of scope, and it is a
`pkind-flow-check` carve-out, not a renderer bug). `pkind-flow-check` only
diagnoses a **TY-PTR** source, so a `CStr` source flows into a non-null
`(ref T)` unchecked — the "CStr is ref-compatible" carve-out. Therefore
`(defvar g:ptr:T (as CStr null))` compiles to `@g = global ptr null` in a
non-null slot. The identical local, `(let (p:ptr:T (as CStr null)) …)`, is
**equally** accepted, by this compiler and by the pre-G-1 boot — so the renderer
matches the chokepoint exactly, which is the G-1 contract; what is wrong is the
carve-out, in both positions at once. W9-class; the fix belongs with whatever
revisits `CStr`'s exemption from the Phase-F regime.

**A second, cosmetic pre-existing wart:** `int-literal-fits` returns 1 for any
value at width ≤ 1, so `(defvar g:i1 5)` emits `global i1 5`. LLVM accepts and
truncates it to `true`. G-1 gives it a second spelling (`(+ 2 3)`) but does not
change the behaviour; the old boot emits the identical line for the literal.

### G-2 — aggregate globals: `(array T N)` type + constant aggregate initializers

1. An `(array T N)` **type**, usable as a `defvar` type and — the same feature
   one level down — as a `defstruct` field type. The port reports the field
   version separately as a Major finding (`NUCLEUS-FINDINGS.md` §4.2, "No
   fixed-size array struct fields"), and `design/overview.md` already lists it
   as a next-stage candidate wanting the
   [stage14/attributes.md](stage14/attributes.md) layout design. **These are one
   feature; do them together.**
2. `(defvar g:(array T N))` → `zeroinitializer` (covers the port's 11 B/C
   sites).
3. `(defvar g:(array T N) (array T lit…))` → a constant aggregate.
4. `(defvar g:ptr:T (array T lit…))` → `@g.data` + `@g = global ptr @g.data`
   (verified §2.7), which is the port's 9 A sites, and is **non-null**.
5. A constant struct literal `(defvar g:S (S lit…))`.

*Verify:* fixtures for each of the five shapes; `g-arena-alloc` converted to its
constant form (§2.10) as the first in-compiler use, with the positive
`ALLOC-ARENA` assertion §4.4 requires. `make bootstrap` byte-identical.
Optionally, and **not as a gate**: rewrite the port's
`mobjinfo`/`states`/`tables` and check the initializer function disappears from
the IR while the demo gates stay bit-exact — a second corpus for the same
machinery, scheduled when convenient (§4.4).

---

#### G-2 as built — 2026-08-02

**Done, with one deliberate split** (see "The `g-arena-alloc` tension" below):
all five shapes plus the `defstruct` array field landed with `make bootstrap`
byte-identical on the first pass; the `g-arena-alloc` conversion did **not**
land, because the same *Verify* clause demands it and byte-identical bootstrap
in one breath and those cannot both hold.

**The central decision: an array is a VALUE in storage and DECAYS on read.**
The spec left this open, and it determines nearly everything else, so it is
stated here rather than left implicit in the code.

`(array T N)` is a **storage type**: N values of T laid out inline, exactly as
C's `T x[N]`. It is legal in precisely two declaration positions — a `defvar`
type and a field of an aggregate (`defstruct`, and the anonymous `(struct …)` /
`(union …)` member lists) — plus `(sizeof (array T N))` and
`(alloca (array T N))`. Read in **any** value position it yields the address of
element 0, typed `(ref T)`.

Three reasons, in decreasing order of force:

1. **The C interop invariant decides it.** `context/conventions.md` requires
   every Nucleus type to be representable in C, and the whole point of the
   feature — the port's Major finding — is `struct { int xs[4]; }` laying out
   the same on both sides. C's array-in-struct is inline value storage. There
   was no second option here, and `make layout-test` now gates it against the
   platform C compiler.
2. **The decay half was already the language's answer.** The pre-existing
   `(array T lit…)` *expression* (`emit-array-lit`) allocas `[N x T]` and
   returns `ptr:T`. Making the *type* behave differently in value position
   would have given one spelling two meanings. §2.7's measured target form
   (`@g.data` + `@g = global ptr @g.data`) is that same decay at file scope.
3. **A non-decaying array would need machinery nothing else needs.** By-value
   parameters, returns and assignment of an aggregate whose size is unbounded
   in the type — `abi-classify` would have to grow an array arm, `set!` an
   aggregate copy, and `type-spelling` a round-trippable spelling. Refusing
   those positions costs one diagnostic and buys the whole rest of the design.

The corollary is that **arrays are refused everywhere a value copy would be
implied** — by-value parameter, return, `let`/`with` binding, pointer element,
generic type argument, nested array, `set!` target, `.set!` field target — each
with a located diagnostic naming the `ptr:T` spelling that works.

**Containment is ONE gate, not N refusals.** The obvious implementation
(`reject-array-type` at every position that must refuse) is the shape that
drifts: a position added later silently accepts. Instead `g-array-ok`
(`src/nucleusc.nuc`, beside `g-form-line`) is a one-shot permission that the
four permitting sites arm and `parse-type-from-node` **consumes on entry**, the
same consume-once discipline `emit-generic-call` applies to `g-want-type`.
Nesting then falls out for free with no per-constructor check: `(ptr (array i32
4))` consumes the permission at the outer parse, so the recursion into the
element sees 0 — and so do `(array (array i32 2) 3)`, `(Vector (array i32 4))`,
`(Maybe (array …))` and every other nesting, present and future.
`reject-array-type` (`src/type-utils.nuc`) survives only as a backstop for the
two positions the syntactic gate cannot see, where a Type arrives already
parsed: `abi-classify` and the `set!`/`.set!` targets.

The permitting sites are `extract-decl-name-and-type` (a thin arm-and-clear
wrapper over `extract-name-and-type`, called by `emit-defvar`,
`emit-defstruct`'s field loop, the anonymous struct/union member loops,
`emit-extern`, the REPL's preamble re-resolution) and three direct arms in
`emit-sizeof`, `emit-alloca-form` and `cfold-sizeof`.

**A third permission state exists, and the reason is a real divergence.** A
`defvar`'s type is resolved **twice**: once by G-0's `prescan-value-names` and
once by `emit-defvar`. The length is a constant expression evaluated by G-1's
`const-fold-int`, which routes through `macroexpand-form` — and **macros are
registered only when their file is emitted** (the same structural property W1d
and G-0 record). So during a prescan `(array i32 (_* K 2))` folds and
`(array i32 (* K 2))` does not: the two resolutions would disagree about
whether the same source is legal. `g-array-ok` mode **2** ("provisional") is
the resolution — the prescan builds the array type with the element resolved
and the length left at 0, and does not fold. That is sound because the prescan's
Sym exists only so a forward *reference* resolves, and every read of an
array-typed binding goes through `array-decay`, which reads `elem` and never
`arr-len`; `emit-defvar` then re-resolves the real type (macros registered) and
re-defines the Sym. The claim is *checked*, not merely asserted: a real
`(array T 0)` is refused at parse, so a zero length can only be provisional, and
`type-to-ir` dies on one rather than emitting a plausible `[0 x i32]` (which is
legal LLVM — a flexible array member — and would therefore have been silent).

**What the new type kind touched, subsystem by subsystem.**

| Subsystem | Change | Note |
|---|---|---|
| `TypeKind` / `Type` | `TY-ARRAY` appended last; new `arr-len:i32` | `compiler-types.nuc` |
| Type cloning | `type-with-volatile` copies `arr-len` | the one Type-cloning site; a miss would silently make a zero-length array |
| `type-to-ir` | `[N x T]`, plus the provisional-length assert | `type-utils.nuc` |
| `type-size` | **element** size, i.e. the slot ALIGNMENT — not `N*sizeof(T)` | every caller uses it in an `align N` operand, which must be a power of two; `alloca [3 x i32], align 12` is invalid IR. The real size is `abi-sizeof`, exactly as for `TY-STRUCT`. |
| `type-to-c` | the **element** type only | C's array declarator is postfix; the `[N]` is appended by `emit-cheader-defstruct` |
| `abi-sizeof` / `abi-alignof` | `N * sizeof(T)` / `alignof(T)` | |
| `abi-class-eightbyte` | **restructured**: the per-field body extracted into `abi-class-type-at`, which the array case recurses into per element | see below — this is the one that would have been silently wrong |
| `abi-classify` | `reject-array-type` backstop | an array param would otherwise have become a legal-but-not-C-ABI `[4 x i32] %x.arg` |
| `parse-type-from-node` | the `(array T N)` branch + the consume-once gate | placed ahead of the template lookups so a user template named `array` cannot capture the spelling |
| `type-eq` / `hash-type` | element **and** length | |
| `type-mangle-token` | `a<N>_<elem>` | unreachable today; the old fall-through `"x"` collided with every unmodelled kind |
| `type-spelling` | `(array T N)` — diagnostic-only, deliberately **not** round-trippable | sound only because arrays are refused in every position where the spelling has to re-parse (conformance keys, generic substitution) |
| `emit-symbol-ref` / `emit-field-load` / the two union-member arms / `emit-field-addr` / `emit-alloca-form` | decay, via the shared `array-decay` | |
| `node-type-sym` / `node-type-field` / `callable-get-type` / `node-type-alloca` | the same `array-decay` **call** | the lockstep; `node-type-alloca` also had to arm the gate, or the non-emitting pass rejected what codegen accepted |
| `emit-zero-store` / `emit-defvar`'s no-init default | `zeroinitializer` | the three-bucket rule moved into `type-zero-const-ir`, now shared with the aggregate renderer's unspecified slots |
| `emit-set` / `emit-field-set` | refuse | before the RHS is emitted, so the message names the cause |
| `emit-cheader-defstruct` | `T name[N];` | |
| `emit-extern` | permits an array type | `--emit-nuch` exports an array `defvar` as `(extern (g (array i32 3)))`; without this the import side could not read the header the export side wrote |
| `repl.nuc`'s `defvar` arm | permits an array type | the preamble's `external global` line is written from a *second* resolution of the same type node |

**Three things surprised me.**

1. **`abi-class-eightbyte` was the real hazard, and it is invisible without a
   float array.** Its field loop ended `not a struct, not a float → INTEGER`, so
   an array field fell into INTEGER wholesale. For `struct { int v[2]; }` that
   is accidentally right; for `struct { float v[2]; }` it is wrong in a way no
   size or offset check can see — the struct is 8 bytes either way, but the
   value travels in `rdi` instead of `xmm0`, so C and Nucleus disagree only at
   the *call*. `make layout-test` cannot catch it. `tests/abi/`'s new `FArr2`
   is what does: the emitted declaration must be
   `declare double @farr2_sum(<2 x float>)`, and it is.
2. **`--emit-cheader` cannot fold a named length, and must not try.** The
   cheader pass never runs the emitter, so a `defconst` is not in the value
   scope during it and `(array CStr N)` does not fold. The first cut died with a
   `:0:` diagnostic. The right answer is not to fold harder but to notice that
   the header *already exports* `#define N 3` beside the struct: the extent is
   emitted **verbatim** when it is a bare name, giving correct C that keeps the
   symbolic size. Only a computed length whose constants this pass cannot see is
   an error, and it now carries the field's line.
3. **`fmt-s` with two `%s` segfaulted the compiler**, in my own new code, within
   an hour of reading the note that says so. It is worth recording that the trap
   is not "you might forget" — it is that the failure is a bare SIGSEGV with no
   output, so a one-line diagnostic path that is never exercised by a passing
   test can carry it indefinitely. Which is exactly what a grep then found in
   **three pre-existing sites** (§7).

**The `g-arena-alloc` tension — the spec is internally inconsistent, and this
is the resolution.** The *Verify* clause above requires both (a) `g-arena-alloc`
converted to its constant form as the first in-compiler use and (b)
`make bootstrap` byte-identical. They are incompatible, and not marginally:

* The committed boot compiler cannot parse a constant struct initializer at all
  (measured: `bin/nucleusc` on `(defvar h:AllocHandle (AllocHandle ALLOC-ARENA
  null))` dies `defvar: init must be a literal`, and on `(defvar g:(array i32
  4))` dies `defvar: missing :type on 'g'`). So **any** in-compiler use of G-2
  makes `make` itself fail, before `make bootstrap` can even run — this is
  `context/build.md`'s "breaking changes the OLD boot can't bridge", needing a
  2-stage manual bootstrap and a `make update-bootstrap` reconverge.
* §4.4 already places the `g-arena-alloc` conversion in the **migration** list
  (item 2), whose home is G-5, and §4.7 already predicts G-5 "**will** move the
  compiler's IR substantially and is a deliberate reconverge". The G-2 *Verify*
  clause pulled one migration item forward without noticing it also carries
  G-5's bootstrap cost.

**Resolution: split.** G-2 is the feature, bootstrap byte-identical. The
conversion is a separate step (call it G-2b, or fold it into G-5). It is
de-risked rather than merely deferred — the exact form was reproduced and
measured end to end:

```lisp
(defvar g-ah:AllocHandle (AllocHandle ALLOC-ARENA null))
;  → @g-ah = global %AllocHandle { i32 1, ptr null }, align 8
```

compiled, linked and ran; a `(vector-new-in (addr-of g-ah))` built from it
reports `kind = ALLOC-ARENA` in its copied handle. Two facts the follow-up needs
and now has:

* **`null` into `AllocHandle.data` passes the Phase-F gate**, because `data` is
  an elem-less bare `ptr` — the `void*` escape hatch `pkind-flow-check` exempts.
  This was not obvious and is the one thing that could have blocked the whole
  approach.
* **No source reorder is needed for this step.** §2.10 calls for moving
  `g-arena-alloc` (`:182`) above the first registry (`:144`); that is a
  requirement of a *runtime* initializer ordering rule, i.e. G-3. A constant
  initializer is link-time and correct before any code runs, so the reorder
  belongs with G-3/G-5, not here.

The procedure, when it is taken: (1) edit `nucleusc.nuc:182` and delete
`compiler-init`'s `(arena-allocator (addr-of g-arena-alloc))`; (2) `make` will
fail, so build with the G-2 compiler directly (`build/nucleusc --emit-llvm
src/nucleusc.nuc`) and link that; (3) `make test` / `abi-test` / `layout-test`;
(4) prove the diff inert — normalized per-function diff plus an old-vs-new
`--emit-llvm` sweep of every `examples/`, `lib/` and `tests/fixtures/` program,
with the **baseline compiler built from HEAD's source**, not from `bin/nucleusc`
(G-0's finding: the committed boot lags HEAD and manufactures phantom entries);
(5) `make update-bootstrap`, then `make clean && make && make bootstrap`. The
positive `ALLOC-ARENA` assertion §4.4 requires belongs in the same step, since
it is the thing that makes the conversion checkable rather than silent.

**Verification.**

* `examples/g2-array-init.nuc` compiles, links and runs, **printing** every
  value of all five shapes — a constant aggregate's characteristic failure is
  the wrong bytes at the wrong offset, which an exit-0 compile cannot see. It
  also cross-checks three folded `sizeof`s and two field offsets against
  field-address arithmetic, printing `agree`/`DISAGREE` per measurement.
* **`make layout-test` extended with six array-field shapes** — `int[4]` alone,
  with a leading and a trailing scalar, `char[3]` (alignment 1), `double[2]`
  (alignment 8), an array of structs, and an array of array-bearing structs. The
  measurement that matters is the offset of the field **after** the array, which
  moves if the array's size is computed wrong. The C oracle's copies live in
  `tests/layout/structs.h` behind `NUCLEUS_LAYOUT_C_ORACLE` (only `layout.c`
  defines it), because the Nucleus C-header parser skips array declarators by
  design; the Nucleus side `defstruct`s the matching shapes.
* **`make abi-test` extended with four by-value array-field structs** —
  `{int[2]}` (one INTEGER eightbyte), `{float[2]}` (one SSE eightbyte), `{int[4]}`
  (two INTEGER eightbytes) and `{int[6]}` (MEMORY). Verified in the emitted IR:
  `i64`, `<2 x float>`, `{i64,i64}`, `byval`/`sret` respectively, matched
  against an all-C reference build.
* **21 rejection fixtures**, each pinned at a real `file:line:` by
  `run_reject_at`, plus one `run_accepts` (an anonymous `(struct …)` member may
  be an array) and a REPL session.
* `run_g2_cheader` **compiles the generated C header with the platform `cc`**
  and diffs its `sizeof`/`offsetof` against the Nucleus unit's — checking the
  header is not merely plausible text.
* `run_g2_nuch` round-trips an array field **and** an array-typed `defvar`
  through `--emit-nuch`, then links and asserts an exit status.
* **`make test` 361 → 385 PASS / 0 FAIL** (counted with `NUCLEUS_TEST_JOBS=1`;
  the parallel count wobbles between 383 and 385 on this host, which is W9
  item 10). `make abi-test` and `make layout-test` green.
* **`make bootstrap` byte-identical on the first pass** — every G-2 shape is one
  that died before it, so no existing program's IR could move.

**Deliberately not built.**

* **Multi-dimensional arrays.** `(array (array T M) N)` is refused by the same
  consume-once gate that refuses `(ptr (array …))`. Nothing in the port or the
  compiler wants one, and the decay story for a 2-D array (`ptr:(array T M)`,
  a type that is itself refused) needs the pointer-to-array case first.
* **Pointer-to-array**, for the same reason.
* **Whole-array assignment and by-value array parameters/returns.** These are
  the positions the value-vs-decay ruling closes; C does not have them either.
* **Struct packing and alignment attributes.** Out of scope per
  `design/stage15-stress-test/prompt.md` §7, and — measured, not assumed — not
  needed: all six layout shapes and all four ABI shapes match the platform C
  compiler with natural alignment alone. Nothing in G-2 wanted an attribute.
* **Converting the Doom port.** Not a gate (the 2026-08-01 ruling), and the
  user directed it not be converted unless a test needed one; the fixtures above
  are the second corpus instead.
* **The C-header parser reading array declarators.** `(import "foo.h")` still
  registers a struct with an array member as opaque. That is the *import*
  direction; G-2 delivers the *export* direction (`--emit-cheader`). Worth
  doing, but it is cheader work, not array-type work.

### G-3 — `@__nucleus_init`, emitted only when non-empty

A `defvar` initializer that G-1/G-2 cannot fold is queued (a `MonoJob`-shaped
record carrying the form, namespace, source path and line) and drained at
`emit-toplevel-forms` depth 1 into a single synthesized
`void @__nucleus_init()`, in reach order. Each initializer lowers to an ordinary
`set!`, so §2.8's `pkind-flow-check` applies unchanged.

**Zero cost when unused is a gate on this step, not a nicety (§4.8).** The
queue, the function, the registration global — all of it is emitted at the drain
point and only when the queue is non-empty. Nothing is emitted eagerly anywhere
else in the pipeline.

Registration is chosen by `ctor-mechanism-for-triple`, with exactly two v1
answers:

* **`global_ctors`** — hosted (`x86_64`, `aarch64`, `riscv64`, Windows). One
  appended global; works for a library object and for a C consumer, which is
  the multi-TU case §2.4 shows nothing else covers.
* **`none`** — `avr`, and any future triple with no verified append-only
  mechanism. A non-empty queue is a **located error** naming the offending
  `defvar` (§4.6), never a dead section.
* **REPL** is not a triple case: there is no queue, because each form is its own
  unit. Run the initializer immediately at the `defvar`, per §4.5 —
  `repl.nuc:148-169` already JITs each `defvar` into its own module.

*Gate:* `make bootstrap` byte-identical on the first pass — today no unit has a
runtime initializer, so the queue is empty everywhere and nothing is emitted.
Fixtures: a whole program; a `.nuch`+`.o` library initialized with **no** Nucleus
`main` (the case Option 1 cannot serve); an AVR program that hits the `none`
error and one that does not, under `make avr-test`; a REPL session; and — the
zero-cost tripwire — a program with only *constant* initializers, asserting the
emitted IR contains no `__nucleus_init` and no `global_ctors`.

*Deferred within this step:* the AVR `.ctors` measurement (§4.6). It converts
`none` to a third answer and is the only open question in this design.

---

#### G-3 as built — 2026-08-02

**Done**, with `make bootstrap` byte-identical on the first pass exactly as
predicted, and with one hole in the spec's own §4.5 found and closed (the REPL's
*import* route, below).

| Piece | Where | What |
|---|---|---|
| `InitJob` | `compiler-types.nuc:688` | `{form, ns, path, line, name}` |
| `g-init-worklist` / `g-init-drained` | `nucleusc.nuc:290`/`291` | the queue + persistent cursor, mirroring `g-mono-worklist` |
| `g-defvar-soft` | `nucleusc.nuc:358` | the one-shot "this may turn out not to be constant" flag |
| `defvar-const-init-ir` | `nucleusc.nuc:9536` | **the** classifier |
| `defvar-queue-init` | `nucleusc.nuc:9582` | builds `(set! name init)`, appends the job |
| the two soft returns | `nucleusc.nuc:9443`, `9503` | in `defvar-init-ir`, at the "unsupported init symbol" and terminal raises |
| `emit-defvar`'s classify + refuse + queue | `nucleusc.nuc:9649`–`9684` | |
| `CTOR-NONE` / `CTOR-GLOBAL-CTORS` / `ctor-mechanism-for-triple` | `nucleusc.nuc:13038`–`13056` | beside `reloc-`/`cpu-`/`features-`/`abi-for-triple` |
| `init-emit-function` | `nucleusc.nuc:12009` | emits the function, or nothing |
| `drain-init-worklist` | `nucleusc.nuc:12051` | the batch drain + the registration global |
| the drain call | `nucleusc.nuc:12284` | `emit-toplevel-forms`, depth 1, before `drain-mono-worklist` |
| `repl-emit-init-fn` / `repl-run-init-fn` | `repl.nuc:128`–`145` | the REPL's JIT-and-call pair |
| REPL `defvar` arm / `import-use` arm | `repl.nuc:189`, `466` | both routes |

**The queue predicate is `defvar-init-ir`'s own answer, obtained rather than
re-derived.** `g-defvar-soft` is armed by `defvar-const-init-ir` around exactly
one call and turns the renderer's terminal *"init must be a compile-time
constant"* raise into a `null` return. Every other diagnostic inside the
renderer still fires — a range violation, a `pkind-flow-check` failure, an
arithmetic fault, a malformed `(char …)` — because a malformed *constant* is an
error, not a runtime initializer. The flag is 0 during aggregate **element**
rendering, so an element that is not constant remains the hard error it has
always been. That single distinction is what keeps this from being a second
classifier, which §4.8 turns on and which this stage has been bitten by twice.

**An aggregate destination needed one extra rule, and finding it was the useful
part.** The first cut classified "not a constant aggregate" as "runtime", which
is right for a CELL and wrong for a leaf: `(defvar p:P 5)` became
`set!: type mismatch for 'p'`, losing G-2's better *"a `P` slot must be
initialized with a `(P …)` compound literal"*. The rule now is: at a struct or
union slot, `const-struct-lit?` (the same gate `defvar-write-const` applies)
decides constant; a **leaf** node that is not one cannot be a compound literal
at all, so it is a type error and is handed back to the renderer for the better
message; a **CELL** that is not one is an expression, and an expression at an
aggregate slot is exactly a runtime initializer. The one shape this costs is
`(defvar p2:P p1)`, a whole-struct copy from another global, which `set!` would
accept — deliberately traded for the diagnostic.

**`(array T N)` is constant-only, and that is a consequence of G-2, not a
limitation invented here.** G-2 ruled that an array binding names storage no
assignment can target (`emit-set` refuses one), so there is no `set!` for a
runtime lowering to produce. `defvar-write-const` keeps its existing
diagnostic, which is *still true* only because of this restriction — a struct
slot's message had to be re-scoped for the same reason.

**Three positions where a runtime initializer has nowhere to run, each refused
with a located error rather than left as a silent zero.** All three are
`emit-defvar`, so the message names the `defvar`, not a synthesized form:

| Position | Why | Fixture |
|---|---|---|
| inside `compile-time` / `defmacro` | §2.9: that module has no program globals and never reaches a drain point | `g3-init-in-compile-time.nuc` |
| a `:const` global | LLVM `constant` storage is read-only; `emit-set` refuses a store for the same reason | `g3-init-const-storage.nuc` |
| a `none`-mechanism triple | §4.6/§2.6 | `tests/fixtures/avr-runtime-init.nuc` |

The CT case is worth calling out: it is not hypothetical hygiene. `emit-defvar`
is reachable from `emit-compile-time`'s own dispatch (`nucleusc.nuc:10706`),
which never routes through `emit-toplevel-forms`, so without the guard the job
would sit in the queue and the global would keep its zero with no diagnostic
anywhere — the same silent-dead-constructor shape §4.6 refuses on AVR.

**The spec's §4.5 was incomplete about the REPL, and the gap was measured, not
reasoned about.** §4.5 and G-3's own text say "run the initializer immediately
at the `defvar`", and `repl.nuc`'s `defvar` arm is indeed one route. It is not
the only one: `(import-use "lib.nuc")` at the REPL goes through
`emit-import-use` → `emit-toplevel-forms` at **depth 1** → `drain-init-worklist`,
which appended `llvm.global_ctors` into a module ORC then JITed — and ORC has no
initializer entry point (§2.9), so the entry was registered and never run.
Measured: the imported global read back **0**. Fixed by making
`drain-init-worklist` return early under `g-interactive` and giving the REPL two
helpers it calls at *both* routes (emit before `repl-jit-module`, call after —
the function must be in the module, the symbol must exist). The linkage differs
on purpose: `internal` in batch (reachable only through `llvm.global_ctors`, and
two Nucleus objects must not collide on the symbol), external in the REPL so
`LLVMOrcLLJITLookup` can find it. `tests/repl/g3-init.in` pins both routes.

**Reach order falls out; per-job context does not.** The queue is appended in
`emit-defvar`, which runs in reach order, so the order rule needs no sorting
step. But the *drain* happens at the end of the outermost unit, long after
`g-current-ns` and `g-source-path` have moved on — which is why the job record
carries them and `init-emit-function` restores them around each `set!`.
Verified by a fixture that initializes a namespaced global, a **private**
`defvar-` from a `defn-` in the same imported file (private resolution is
`priv-key-use`, which reads `g-source-path`), and a `(Vector i32)` global from a
generic — the last of which is why the drain is placed **before**
`drain-mono-worklist`: an initializer body can stamp a generic, and the existing
drain that follows emits it.

**Zero cost when unused, and how it is proven rather than asserted.** The queue,
the function and the registration global are produced at one point and nowhere
else; an empty queue returns from `drain-init-worklist` having written nothing.
`run_g3_zero_cost` compiles a unit using **every** constant-initializer shape
G-1/G-2 added (folded arithmetic, `(as CStr …)`, `(addr-of g)`, an array
literal, a zero-filled array, a struct literal, a pointer-to-anonymous-table)
and asserts the IR contains neither `__nucleus_init` nor `global_ctors` — an
empty file could not catch a classifier that quietly routed a foldable
initializer down the runtime path. The **same function** then adds one runtime
initializer to the identical unit and asserts both artefacts *do* appear, so
deleting the feature outright cannot pass the tripwire. `make avr-test` carries
the same pair of assertions under `--target=avr`, on the target the requirement
was stated for.

**Verification.**

* `examples/g3-runtime-init.nuc` compiles, links, runs and **prints** every
  value — a startup initializer's characteristic failure is that it never ran,
  and the slot's zero is indistinguishable from a clean compile unless you look.
  Covers a call, ordering (`g-after` sees `g-n`'s value), a non-null `ptr:T`, a
  by-value struct, a `CStr`, a function pointer, and constant initializers
  coexisting in the same unit.
* `run_g3_library`: `--emit-nuch` + two separately compiled `.o`s, a library
  with **no Nucleus `main`**, whose global is initialized by its own object's
  `.init_array` entry and read correctly by the consumer. The library is
  `(exclude-prelude)` and that is forced, not stylistic — **W9 defect 2 is worse
  than "7 duplicate prelude globals"**: two prelude-carrying Nucleus objects
  duplicate the prelude's *functions* too (`arena-init`, `arena-alloc`,
  `arena-strndup`, …), re-measured here. §2.4 used the same route. This is the
  narrowest fixture that genuinely exercises the multi-TU path without fixing
  that defect, which is not G-3 work.
* Four `run_reject_at` fixtures, each pinned at a real `file:line:`: the
  nullability inheritance (`assignment: raw pointer where non-null (ref ...) is
  required`, at the `defvar`), the type mismatch, and the CT/`:const` refusals.
* `tests/repl/g3-init.in`: a directly typed runtime `defvar`, a constant one, a
  later `set!`, and the `import-use` route.
* `make avr-test`: `examples/avr-global-init.nuc` links and stays in budget with
  no constructor machinery; `tests/fixtures/avr-runtime-init.nuc` is refused
  with the located message.
* **`make test` 385 → 393 PASS / 0 FAIL** (`NUCLEUS_TEST_JOBS=1`; the parallel
  count wobbles, W9 item 10). `make abi-test`, `make layout-test`,
  `make avr-test` green.
* **`make bootstrap` byte-identical on the first pass.** Additionally, an
  old-vs-new `--emit-llvm` sweep of every `examples/`, `lib/`, `lib/avr/` and
  `tests/fixtures/` program against a baseline compiler **built from HEAD's
  source** (not `bin/nucleusc`, which lags — G-0's finding): **210
  byte-identical, 0 differing, 0 regressed**, 3 newly compiling (the new
  fixtures). A second sweep over the *rejection* fixtures compared **stderr**:
  113 byte-identical diagnostics, 4 changed — and all four are the new G-3
  fixtures. So no existing program's IR and no existing program's diagnostic
  moved.

**Two pre-existing defects this step ran into. Both reported, neither fixed
here; both are independent of global initialization.** They are also in §7.

1. **A `defvar` whose declared type is a function-pointer type cannot be
   declared at all** — with or without an initializer. `(defvar g:(fn i32)(i32)
   null)` dies *"'g' already names a function"*. `name-existing-kind`
   (`nucleusc.nuc:8703`) classifies **any** global Sym whose type is `TY-FN` as
   `NK-FUNCTION`, and since G-0 `prescan-defvar-name` defines that Sym before
   `emit-defvar` runs, so the `defvar` collides with itself. **This is a G-0
   regression** (reproduced identically on the committed boot). It matters for
   G-5: §2.12 counts two fn-pointer hooks among the 48 globals `compiler-init`
   initializes. The discriminator already exists and is exact — a function's Sym
   is registered with `is-local = 0` (`defn`, cheader, `.nuch declare`), a
   global variable's with `1` (`defvar`, `extern`) — so the fix is one added
   conjunct, and it is *provably inert*: `name-existing-kind` has exactly one
   caller (`guard-name-kind`, which only ever raises), and no program in the
   tree can currently contain the shape it would newly admit. Left out of G-3
   because it is a name-kind change with its own verification, not a
   global-initializer one. `examples/g3-runtime-init.nuc` uses the bare-`ptr`
   escape hatch and says why.
2. **`aref` emits its GEP index as a hardcoded `i64` on every target**, so on
   AVR (16-bit pointers) any index narrower than `i64` produces IR the LLVM
   parser rejects — `'%t3' defined with type 'i32' but expected 'i64'`. It does
   not go through `ptr-int-ir`, which AVR-2 introduced for exactly this class.
   Identical on the committed boot; unrelated to arrays specifically (a plain
   `ptr:ui8` reproduces it). `examples/avr-global-init.nuc` widens its index and
   says why.

**Deliberately not built.**

* **The AVR `.ctors` measurement** (§4.6) — the design's single open question,
  deferred *within* this step by the spec. `none` remains AVR's v1 answer.
* **The `compiler-init` migration and the `g-arena-alloc` conversion.** G-3
  builds the mechanism; G-2b/G-5 convert the compiler. Nothing in `src/` or
  `lib/` has a runtime initializer today, which is why the bootstrap could not
  move.
* **The ordering diagnostic** (§4.2) — G-4. The order rule is implemented and
  documented; what is missing is the refusal for a syntactically-visible
  forward reference.
* **The flip** — rejecting `(defvar g:ptr:T)` — G-5.
* **Deduplicating `__nucleus_init` across translation units.** Not needed: the
  symbol is `internal`, so two Nucleus objects each get their own and both run.
  Worth knowing before anyone makes it external.
* **A second init function per priority level.** `llvm.global_ctors` takes a
  priority and this always emits 65535. There is no shape that wants another
  value, and adding one would need an ordering policy §4.1 deliberately does not
  have.

### G-4 — the ordering diagnostic and the docs rule

* Reject a `defvar` initializer that syntactically names a global whose `defvar`
  has not yet been reached, naming both sites (§4.2).
* `docs/toplevel.md`: state the initialization-order rule, state plainly that it
  is emission order and therefore *import order*, and state — beside the
  existing "reachability, not import order" section — why that is not the rule
  W1 retired.
* `docs/toplevel.md`'s `defvar` entry, and `docs/types.md`: the new initializer
  grammar.

---

#### G-4 as built — 2026-08-02

**Done.** One walk, one per-symbol check, one new `Sym` field, and the docs
paragraph §4.1 asked for.

| Piece | Where | What |
|---|---|---|
| `DEFVAR-DECLARED` / `DEFVAR-REACHED` | `compiler-types.nuc:62`/`63` | the two states; **0** is "not a `defvar` global at all" |
| `Sym.defvar-state` | `compiler-types.nuc:397` | the field |
| the DECLARED mark | `nucleusc.nuc:11806` | in `prescan-defvar-name` |
| the REACHED mark | `nucleusc.nuc:9890` | in `emit-defvar`, on the Sym it registers *after* the `@g = global` line |
| `defvar-blame-forward-ref` | `nucleusc.nuc:9679` | one symbol → silence, or the located both-sites diagnostic |
| `defvar-check-init-order` | `nucleusc.nuc:9719` | the walk, with the three skipped heads |
| the call | `nucleusc.nuc:9848` | `emit-defvar`, inside the run-time-initializer block |

**Question 1 — "has not yet been reached" is EMISSION, and G-0 is what made it a
separate question at all.** Before G-0 the two coincided: a forward-named global
did not resolve, so "reference to an unreached `defvar`" and "undefined name"
were the same event. G-0 registers every reachable file's `defvar` names before
the first form is emitted — *deliberately*, since §4.1's whole argument that this
step is not a re-run of the ordinal rule W1 retired depends on resolution being
order-free. So a successful `scope-lookup` now proves nothing here, and asking
resolution would have produced a check that fires on nothing.

The mechanism separates them **without a second registry**, and the shape is the
reusable part. G-0 already registers each `defvar` name *twice* — once in the
prescan, once at emission — and `scope-define` appends while `scope-lookup`
scans backwards, so a lookup returns the prescan Sym before emission and the
emission Sym after. Marking the two differently makes the state a reference sees
flip at exactly the right instant, for free. Two properties made this the right
choice over the obvious alternative of a list of already-emitted globals:

* **A saved `Sym*` goes stale.** `scope-define` grows the scope by
  `arena-alloc` + `memcpy` into a *new* array, so a pointer captured before a
  growth points into the old buffer. A membership test by pointer identity would
  have been silently wrong for any unit large enough to grow the global scope —
  i.e. all of them. A field travels with the `memcpy`.
* **The 0 state does real work.** A function, an `extern`, a `.nuch`-imported
  global and a `defconst`/`defenum` member all keep the arena's zero and are
  outside the rule by construction, rather than by a list of exclusions the next
  definer-kind would have to be added to. `extern` is *deliberately* outside it:
  its storage belongs to another translation unit and cross-TU initialization
  order is unspecified here for the same reason it is in C++ (§4.1).

The check therefore never reports "undefined" — resolution keeps that answer,
and keeps it order-independent.

**Question 2 — `(addr-of g)` is NOT a read, and the measurement below is why
that is not a convenience.** A global's address is a link-time constant that
requires no initialization to have happened; it is exactly what G-1 folds to a
bare `@g`. Reading the *value* is what gets a zero. So `addr-of`'s operand is
skipped, subtree and all. Two in-tree consequences:

* `examples/g1-const-init.nuc` already ships a forward `(addr-of
  g-later-target)` in a *constant* initializer and must keep compiling.
* `tests/fixtures/g4-addr-of-forward.nuc` pins the **run-time** path, where the
  exemption is a real carve-out rather than a consequence of the check not
  running: the initializer is a call (so it is queued and the check does run) and
  the forward `(addr-of …)` sits in its argument. `run_g4_order` links it and
  asserts the dereferenced value, so a pointer that came out wrong fails rather
  than compiles.

**What the check ran into on this compiler's own source — and the number that
matters for G-5.** As shipped it fires nowhere in `src/` or `lib/`, and that is
not informative on its own: all 178 top-level `defvar`s there have a literal,
`null`, or absent initializer, so **none has a run-time initializer for the
check to examine**. The load-bearing measurement is the forward-looking one,
over the 42 `(set! g-… …)` statements in `compiler-init` that G-5 converts:

* **19 of the 42 syntactically name another global.** In every one of the 19 the
  named global is `g-arena-alloc`, and in every one it is named **inside
  `(addr-of …)`** — the `(vector-new-in (addr-of g-arena-alloc))` shape.
* **With the `addr-of` exemption: 0 rejections.** G-5 is unblocked as written.
* **Without it: 8 rejections** — `g-structs` (`:144`), `g-uniondefs` (`:152`),
  `g-union-templates` (`:154`), `g-struct-templates` (`:157`), `g-enumdefs`
  (`:159`), `g-pending-unions` (`:160`), `g-deferror-name-sids` (`:170`) and
  `g-deferror-msg-sids` (`:171`), each declared above `g-arena-alloc` at
  `nucleusc.nuc:182`. That is precisely §4.1 consequence 2 / §2.10's known
  one-line reorder, which is reassuring about the rule's calibration: the strict
  reading finds exactly the sites the design already knew about, and no others.

**The residual `g-arena-alloc` hazard is real, is the laundered case, and is
already accounted for.** `vector-new-in` reads the handle *through* the pointer
it is given, so an initializer running before `g-arena-alloc`'s own would build
a libc-backed Vector — undetectable here by construction, and exactly why §4.4
item 5 makes a positive `ALLOC-ARENA` assertion part of G-5 rather than trusting
a green `make test`. §2.10's answer dissolves it anyway: once the handle is a
**constant** initializer it is applied by the loader before any initializer runs,
so there is no window. G-5 should keep both — the constant handle *and* the
assertion.

**Placement: the check runs on the RUN-TIME path only.** A constant initializer
is folded from literals, named constants, `(sizeof T)`, `(as T x)` and
addresses, not one of which reads a global's value, so there is nothing there to
check. Confining it to the run-time branch also removes a whole class of false
positive for free: the constant-aggregate grammar's designated **field names**
(`(P (y 9))`) and index cells are selectors, not references, and a walk over
them would have rejected any program with a global spelled like one of its
struct's fields. A non-constant *element* inside a constant aggregate never
reaches the check either — an element must be constant regardless of order, and
it keeps G-2's better "init must be a compile-time constant" wording.

**Two more skipped heads, one of them an admitted false negative.** `quote` and
`quasiquote` subtrees are not walked: the symbols inside a `quote` are *data*,
so walking them would reject `(defvar g:(raw Node) (quote (b c)))` for "naming"
a global it never reads. A quasiquote's `~b` unquote genuinely *is* a read and
is given up with the rest of the subtree — deliberately, because a false
positive breaks a program that compiles today, while a missed diagnosis lands in
a class already documented as incomplete.

**The diagnostics.** Both name both sites at real `file:line:`s; the note's
location comes from the target Sym's `src-file`/`src-line`, which
`sym-set-src-loc` filled during the **prescan** with `g-source-path` set to the
file being walked — which is what makes "name the other site" possible at all
for a `defvar` that has not been emitted yet.

```
demo.nuc:12: error: defvar: the initializer for 'a' names global 'b', whose own
  defvar has not been reached yet -- it still holds its zero at this point
  note: 'b' is declared at demo.nuc:13; initializers run in the order their
  defvars are reached (source order within a file, import order across files), so
  move that defvar above this one -- unless it depends on this one in turn, which
  is a cycle no order satisfies
```

The self-reference case gets its own wording, because "both sites" would
otherwise be the same line printed twice:

```
demo.nuc:6: error: defvar: the initializer for 'g' names 'g' itself, whose defvar
  has not been reached yet -- the slot still holds its zero
  note: a global's initializer runs at the point its own defvar is reached, so it
  cannot read the global it is initializing
```

The advice clause is hedged on purpose: a genuine **cycle** reaches the same
message (§4.2 predicted correctly that it needs no machinery of its own — the
first of the pair always names a global the second has not reached), and
reordering is exactly what cannot fix one (§4.1 consequence 3).

**Verification.**

* `run_g4_order` links and **runs** four programs, asserting exit status: a
  same-file backward reference (42); the cross-file pair in the good import
  order (42) *and* the reversed order refused with both files named at real
  lines — §4.1 consequence 1 made observable; the run-time `(addr-of g)` forward
  (7); and the laundered gap (10).
* Three `run_reject_at` fixtures — forward reference, cycle, self-reference —
  each pinning the error's own location **and** the note's, so one call covers
  both halves of "name both sites".
* Two `run_accepts` fixtures pin the carve-outs as compile-clean, so a later
  stricter walk that swallowed either fails here.
* `tests/fixtures/g4-laundered-call.nuc` pins the **known gap** by value, and
  says so in its header comment: `main` returns `(+ 10 g4-lc-dst)`, so today's
  undetected forward read reads as exit 10 and any future fix reads as 109 and
  fails loudly rather than passing quietly.
* **`make test` 396 → 406 PASS / 0 FAIL** (`NUCLEUS_TEST_JOBS=1`).
  `make abi-test`, `make layout-test`, `make avr-test` green.
* **`make bootstrap` byte-identical on the first pass**, as predicted — the
  check writes to no IR stream and only ever raises, and the `Sym` field is
  compiler-internal state.
* An old-vs-new `--emit-llvm` sweep over every `examples/`, `lib/`, `lib/avr/`
  and `tests/fixtures/` program, against a baseline compiler built from this
  tree with exactly the G-4 edits reverted: **216 byte-identical, 0 differing, 0
  regressed**; the only three programs that changed status are the three new
  rejection fixtures. A second sweep compared **stderr** across the 119
  programs both compilers refuse: **335 diagnostics byte-identical, 3 changed**,
  and the 3 are those same new fixtures. No existing program's IR and no
  existing program's diagnostic moved.

**Deliberately not built.**

* **Macro-expanding the initializer before the walk.** The variadic operator
  macros wrap their tail but keep every operand as a leaf, so `(+ b 1)` is
  already visible without expansion. A macro that *manufactures* a global
  reference out of nothing is undetected, which is the same laundering boundary
  by another route.
* **Distinguishing a `set!` TARGET inside an initializer from a read.** The
  message says "names", not "reads", so it stays true for the pathological
  `(defvar a:i32 (do (set! b 1) 2))`; a write to a not-yet-initialized global is
  its own (worse) ordering bug and refusing it is not wrong.
* **Any use of the new `Sym.defvar-state` beyond this check.** It has exactly
  one reader, on a dying path — the property that made adding it provably inert.
* **The flip and the `compiler-init` migration** — G-5, unchanged.

### G-5 — eliminate `compiler-init`, then flip

This is the step acceptance criterion (A) names, and the flip (B) falls out of
it. Sequenced accept-both → warn → flip, as Phase F was:

1. **accept-both:** G-1..G-3 landed, no rejection yet.
2. **migrate:** apply §2.12 to `src/`+`lib/` —
   * the **3 constant** initializers (`g-arena-alloc` lands in G-2; the two
     late-binding hooks here);
   * the **45 runtime** initializers, with the six value-returning builders
     §4.4 lists and the one `g-arena-alloc` source reorder;
   * **fold `init-generics`** into `g-generics`' builder (declaration order
     already correct, `:266` before `:271`);
   * **delete the 20 dead statements** — a separate commit, since it moves the
     compiler's own IR and needs the standard reconverging refresh;
   * **rule on the three lazily-built erasure registries** (§2.12 D) — eager
     initializer or honest `raw`. G-5 cannot close W6 §1.5 without this;
   * leave `(target-init)` as an explicit call from `main` after argv parsing
     — the one genuinely special case.

   *Verify:* the positive `ALLOC-ARENA` assertion (§4.4); `make test` green;
   `make bootstrap` reconverged.
3. **warn:** a warning at every remaining no-init non-null-typed global,
   anywhere in the tree.
4. **flip:** the warning becomes an error — a `defvar` whose type is `PTR-REF`
   with an element type must be initialized. `defvar-init-ir`'s existing
   `pkind-flow-check` call and `emit-defvar`'s no-init default become one rule.
   This closes `nullability.md` §1.5's remaining half and makes `ptr:T` mean
   non-null at a global as it does everywhere else.

**The port is not a gate on any of these steps** (§4.4). It becomes a useful
second corpus once (2) has proven the machinery on the compiler.

---

#### G-5 as built — 2026-08-02

**Done. `compiler-init` is gone**, not reduced: the function no longer exists.
Its 52 statements resolved almost exactly as §2.12 predicted — 48 globals became
combined declaration+initializations, 20 statements were dead and were deleted,
and exactly one, `(target-init)`, was genuinely special and is now called
directly from `main` (after the argv loop) and from `repl-main`. Acceptance
criterion (A) is met in its strongest form, and (B) — rejecting
`(defvar g:ptr:T)` — is in, closing `nullability.md` §1.5's remaining half.

| Piece | Where | What |
|---|---|---|
| `defvar-require-init` | `nucleusc.nuc:9864` | the flip: PTR-REF + an elem type + no init ⇒ located error |
| the call | `nucleusc.nuc` `emit-defvar`, after `guard-name-kind` | fires only when `init-cell` is null |
| `assert-compiler-arena-backed` | `nucleusc.nuc:708` | §4.4 item 5's positive assertion |
| its two callers | `nucleusc.nuc:13936` (`main`), `repl.nuc:908` | so every suite compile runs it |
| `g-arena-alloc` (constant) | `nucleusc.nuc:698` | `(AllocHandle ALLOC-ARENA null)` |
| `g-current-ns` (moved up) | `nucleusc.nuc:159` | above `g-generics`, whose builder reads it |
| `make-ptr-type` | `type-utils.nuc:22` | `types-init`'s only construct-then-mutate case |
| `build-deferror-sids` | `nucleusc.nuc:734` | one builder, both sid tables |
| `build-binops` | `nucleusc.nuc:2551` | `add-binop` now takes the vector |
| `build-rmacros` / `build-blanket` | `nucleusc.nuc:13258` / `:13274` | ditto for `register-rmacro` |
| `build-special-form-set` / `build-primitive-type-set` | `nucleusc.nuc:13462` / `:13522` | `init-name-sets` split in two |
| `generic-alloc` / `build-generics` | `generics.nuc:45` / `:112` | the `init-generics` fold |
| the want arm in `emit-as` | `nucleusc.nuc` `emit-as` | a prerequisite defect, below |

**The survivor list is exactly one, and it is `(target-init)`** — as §2.12 C
predicted. It is special for two independent reasons, either of which alone
would disqualify it: it **reads argv** (`--target=` / `--mcpu=`, parsed by
`main`'s flag loop, which a load-time initializer cannot see), and it **sets
five globals from one call**, deriving them from each other. That is
configuration, not construction. Nothing else survived: the seven helper
functions (`types-init`, `init-name-sets`, `init-binops`, `init-generics`,
`init-blanket`, `init-rmacros`) are deleted outright, replaced by builders that
are each some global's initializer.

**Ruling on the three lazily-built erasure registries (§2.12 D): EAGER, and two
more with them.** `g-vtable-table`, `g-boxedfn-table` and `g-dyn-table` now have
`(vector-new-in (addr-of g-arena-alloc))` initializers and all six lazy guards
are deleted, as are the two `g-nundo` guards and the `g-include-paths` /
`g-link-args` pair (the same shape, and §2.12 D says so). The reasoning:

* **`raw` would have been a relabelling, not a fix.** These globals are null for
  a while and then never again; spelling that `raw` is *honest*, but it makes
  the nullable type permanent — every read site keeps a null test forever, and
  the type stops carrying the fact that after startup the value is always there.
  §2.11 prices the casts; the standing cost is worse than the count suggests.
* **Eager costs three empty Vector headers**, arena-allocated, in the
  compiler's own process. That is the entire price, and it deletes eleven
  guard sites.
* **For `g-include-paths` / `g-link-args` eager is a repair, not a trade.**
  They were built during argv parsing, before `compiler-init` armed the
  allocator, so they were silently libc-backed for their whole lifetime while
  every other compiler collection was arena-backed (`context/build.md` recorded
  the split as a fact to work around). The constant handle plus a load-time
  initializer removes both halves; the note in `context/build.md` is now
  obsolete and has been rewritten.

**Verification of the migration.** `examples/g5-arena-backed.nuc` +
`tests/expected/g5-arena-backed.out` pin the §2.10 mechanism at the language
level — a constant `AllocHandle` global, a Vector built from it by a startup
initializer, and a read-back of the handle the Vector *copied at construction*
(not a re-read of the global, which is the distinction that matters: a Vector
built before the constant took effect stays libc-backed even once the global
reads ALLOC-ARENA). `assert-compiler-arena-backed` makes the same two assertions
about the compiler's own `g-arena-alloc` and `g-structs`, from `main` and
`repl-main`, so all 410 suite compiles execute it. Both are required: the
example pins the mechanism independently of the compiler's source, the assertion
pins the compiler independently of the example.

**Three premises in §2.12 / §4.4 measured false. All three are load-bearing.**

1. **§2.10's source reorder goes the wrong way.** §2.10/§4.4 item 2 say
   `g-arena-alloc` must move UP, above the first registry at `:144`, so the
   `(vector-new-in (addr-of g-arena-alloc))` initializers do not
   forward-reference it. Upward is **impossible**: a constant struct literal
   needs `AllocHandle`'s *layout*, and `lib/allocator.nuc` is not imported until
   `(import-use vector)` around `:640` — at `:182` the renderer sees a fieldless
   registry entry and dies *"too many initializers for struct 'AllocHandle'"*.
   Upward is also **unnecessary**, for the reason §2.10 itself supplies: a
   constant initializer is applied by the loader, so it has no order at all
   (§4.1 consequence 4), and every reference to it is `(addr-of …)` — an
   address, which G-4 already exempts. So the move is *downward*, to just after
   the collections import.
2. **A SECOND reorder is needed, and it is the one nobody predicted.**
   `build-generics` → `generic-alloc` → `ns-ir-prefix g-current-ns` →
   `strcmp(g-current-ns, "user")`. `g-current-ns` was declared at `:538`,
   `g-generics` at `:271`, so the initializer would have run `strcmp` on a null
   pointer. The dependency is laundered through two calls, so G-4's syntactic
   check cannot see it *by construction* — this is exactly the class §4.2 says
   is "documented, not diagnosed", and here it was a segfault waiting at process
   start. `g-current-ns` moved to `:159`. The old `compiler-init` knew about it
   (its comment says "must be set before init-generics"); the census did not
   carry the comment forward.
3. **The two late-binding hooks CANNOT be constant initializers.** §2.12 A1
   counts them among the 3 constants. A constant `@fn` reference needs the
   callee's name to resolve at the *defvar's own* emission point — and the whole
   reason these hooks exist is that the callee lives in a **later** import: the
   defvar must sit above the file that reads the hook (`union-registry.nuc`)
   while the callee is defined below it (`generics.nuc` / `union-emit.nuc`).
   There is no position that satisfies both. They are run-time initializers
   (`(unsafe/cast ptr f)`), installed by `@__nucleus_init` before `main` — the
   same instant, relative to any source being read, at which `init-blanket` used
   to install them. So the split is **1 constant + 47 runtime**, not 3 + 45.

**And two counts that were merely stale, both by exactly one, both G-3's own
doing.** §2.12 says 51 statements and 41 `set!`; the function had **52** and
**42**. §2.2's census says 53 non-null element-typed no-init globals; there are
**54**. The extra statement and the extra global are the same thing —
`g-init-worklist`, which G-3 added after the census was taken. Every other
number in §2.12 verified exactly: 20 dead statements, 20 `ty-*` singletons, 19
registries set directly in the body, 5 via helpers, 3 lazily-built erasure
registries, 2 at argv time, 4 per function/module.

**A prerequisite defect the migration exposed, fixed at its root: `as` did not
arm the want channel.** `(as (ref (Vector (ref Cleanup))) (vector-new-in …))` in
`scope-new` (`scope.nuc:16`) is a return-only-tyvar generic in `as`-operand
position. `emit-as` emitted its operand without arming `g-want-type`, so the
call resolved against whichever `(Vector T)` instance the unit had stamped
**first**. It read correctly for the whole life of the compiler only because
that call site *was* the first `vector-new-in` emitted; the migration stamped
`(Vector i32)` earlier (`build-deferror-sids`) and it immediately resolved to
`Vector.i32`, caught by `as`'s own reinterpretation check. The `unsafe/cast`
spelling of the same shape takes the wrong vector **with no diagnostic at all**.
`as` names a type at that position exactly as a `let` binding, a `set!` target,
a `return` and a `.set!` field do, and it was the one such position missing from
TC-2's arm list; it now arms with save/restore. Proven inert for every program
in the tree by the sweep below. `scope-new` was additionally rewritten to bind
before it stores, which does not depend on the fix and says where `T` comes
from.

**Bootstrap: the IR moved, deliberately, and the move is fully accounted for.**
Note first that the standard converge cycle in `context/build.md` **cannot** run
here: its first `make` uses the committed `bin/nucleusc`, which predates G-1/G-3
and dies *"defvar: init must be a literal"* on the migrated source. This is
`build.md`'s chicken-and-egg case with a shortcut available — HEAD (pre-G-5) was
already converged and its compiler already has G-3, so the intermediate compiler
C0 exists without eliding anything. Sequence used: C0 compiled the migrated
source to C1; **C1 compiled itself to byte-identical IR** (the fixed-point
proof, independent of any committed artefact); then `make update-bootstrap`,
`make clean && make && make bootstrap`, which passes.

*Per-function normalized diff* of `build/nucleusc.ll` (`%`-names and `@.str.N`
numbers stripped), old = HEAD built in a scratch worktree (itself verified a
fixed point), new = post-G-5:

* **1024 functions byte-identical.** 22 changed, 9 removed, 14 added.
* The 9 removed are the 7 deleted helpers (`compiler-init`, `types-init`,
  `init-name-sets`, `init-binops`, `init-generics`, `init-blanket`,
  `init-rmacros`) plus two monomorphized instances that were re-stamped under a
  different element token.
* The 14 added are the 10 new builders/assertions, `defvar-require-init`,
  `__nucleus_init`, and those two re-stamps.
* The 22 changed are exactly the functions edited — `emit-defvar`, `emit-as`,
  `scope-new`, `generic-new`, `add-binop`, `main`, `repl-main`, the six memo
  lookup/put pairs whose guards were deleted, the three `narrow-*`,
  `add-include-path` / `add-link-arg`, and the two `g-include-paths` /
  `g-link-args` readers. **Nothing else moved.**

*Top-level (non-function) lines*, order-insensitive: **3 removed, 7 added**, and
every one is named:
removed — a duplicate `"user"` string constant (the second
`(set! g-current-ns (intern-str "user"))` collapsed into one initializer), the
`"x86_64-pc-linux-gnu"` string (a deleted dead target pre-set), and
`@g-arena-alloc = global %AllocHandle zeroinitializer`;
added — five `@.str` constants for the two new diagnostics and the assertion
messages, `@g-arena-alloc = global %AllocHandle { i32 1, ptr null }`, and the
`@llvm.global_ctors` entry.

*Old-vs-new `--emit-llvm` sweep*, baseline built from HEAD's source in a scratch
worktree (never from `bin/nucleusc`, which lags — G-0's finding), over every
`examples/`, `lib/`, `lib/avr/` and `tests/fixtures/` program: **218
byte-identical, 0 differing, 0 regressed.** The only status change in the tree
is `tests/fixtures/g5-noinit-ref.nuc`, the new flip fixture. A second sweep
compared **stderr** across the 122 programs both compilers refuse: **0
diagnostics changed.** So no existing program's IR and no existing program's
diagnostic moved — including under the `emit-as` want arm, which is the change
with the widest theoretical blast radius.

**What the flip newly rejected in-repo: nothing outside `src/`.** The warn stage
(step 3) was built first precisely to measure this, and it reported **54 sites,
all in the compiler's own source, zero in `lib/`, `examples/` or
`tests/fixtures/`** — 216 programs compiled clean under the warning. All 54 are
the migration's own corpus, so the flip cost no collateral edits at all. No
declaration was weakened to accommodate it.

**Tests.** `make test` **406 → 410 PASS / 0 FAIL** (`NUCLEUS_TEST_JOBS=1`; the
parallel count wobbles, W9 item 10). The four new units:
`examples/g5-arena-backed.nuc` (values printed, not merely compiled),
`g5-noinit-ref` and `g5-noinit-ref-note` (the flip's error and its note, pinned
at a real `file:line:`), and `g5-noinit-carve-outs` — one `run_accepts` fixture
carrying all four exemptions (`raw`, `?T`, elem-less bare `ptr`, `CStr`), which
is what would fail loudly if the predicate were ever re-derived by hand instead
of asking `ptr-pkind` + `elem`. `make abi-test`, `make layout-test`,
`make avr-test` all green; `make bootstrap` reconverged.

**Deliberately not done.**

* **The 20 dead-statement deletions are not a separate commit.** §5 suggested
  they be one, on the grounds that they move IR on their own. They do — they
  account for two of the three removed top-level lines — but they are not
  separable *in the working tree*: `compiler-init` no longer exists, so there is
  no function left to delete them from. Nothing is committed (per instruction);
  they are enumerable from the per-function diff.
* **The Doom port** (§4.4) — not a gate, and directed not to be converted.
* **The AVR `.ctors` measurement** (§4.6) — still the design's single open
  question. `none` remains AVR's answer and `make avr-test` still pins both
  halves.
* **Retiring the two late-binding hooks.** Finding 3 above shows they are
  structurally forced to be run-time initializers, which weakens the §2.12 A1
  argument that they were a free mechanical win, but the hook *mechanism* is an
  import-graph question, not a global-initialization one.
* **`(defvar g:S)` for a struct `S` still needs no initializer.** An aggregate's
  zero is a valid value of its own type; only a pointer's zero is a value its
  type forbids. Extending the rule to aggregates would be a different (and much
  larger) claim about definite initialization.

**One unrelated hole found in passing, reported not fixed: a `defvar` may be
declared TWICE with no diagnostic.** Two `(defvar g-current-ns:ptr)` forms
(transiently present while moving the declaration) emitted two
`@g-current-ns = global ptr null` lines, which the LLVM parser rejects with an
unlocated error far from the cause. `guard-name-kind` compares NK-VALUE against
NK-VALUE, finds them equal, and says nothing. Same-kind reuse is deliberate for
overloaded `defn` and REPL redefinition, but a batch `defvar` redefinition has
no such justification. Filed in §7.

---

## 6. Non-goals

* **Callee effect summaries / interprocedural initializer dependency analysis.**
  §4.2. Same boundary and same reason as `nullability.md` §9's R2.
* **A computed topological initializer order.** Follows from the above.
* **Running initializers in `compile-time` / `defmacro` JIT modules.** §2.9 —
  they have no program globals; the correct outcome is a diagnostic.
* **Thread-safe / re-entrant initialization.** No threading stage exists;
  `:thread-local` is already reserved-and-unimplemented
  (`design/stage14/attributes.md` §5).
* **Destructors / `.fini_array`.** Not asked for, and the arena idiom's drop is
  a deliberate no-op.
* **Changing what `raw` means, or narrowing a global.** `nullability.md` §4.3
  and §9 own that; a global is explicitly never narrowed (its S3 condition).
* **A new top-level form.** §4.7 — it would be a bootstrap chicken-and-egg for
  no benefit.
* **Converting the Doom port.** Ruled out of scope 2026-08-01 (§4.4). The port
  stays as evidence and as an optional second corpus; it gates nothing.
* **Wrapping or special-casing `main`.** §4.8 — incompatible with
  zero-cost-when-unused, and it would be the first special case in the
  compiler's treatment of a user function name (§2.3). Held in reserve for AVR
  only.
* **Making the placeholder route (Option 7) an ordinary idiom.** It exists as a
  last resort and no current site needs it.

---

## 7. Bugs and gaps found while measuring (reported except where marked FIXED)

**Filed as Stage 15 W9** — see
[stage15-stress-test/overview.md](stage15-stress-test/overview.md). All are
pre-existing and independent of this design; #6 overlaps G-0 and is not filed
twice (G-0 fixes the cause; the message wants a W1c-style note in the interim).
#7 and #8 were added by G-2 (2026-08-02) and are a matched pair. #9 and #10
were added by G-3, #11 and #12 by G-5; **#9 was fixed in the interlude
between G-3 and G-4, and #12 was fixed in G-5 itself** — both marked FIXED
below rather than removed. [stage15-stress-test/progress.md](stage15-stress-test/progress.md)'s
W9 table reconciles this list against three more defects that were never
filed here, found alongside the interlude and documented only inline in
`examples/fnptr-global.nuc`, for a reconciled total of twenty found, two
fixed, eighteen open.

1. **`make lib-objs` / `make lib-so` is broken**, pre-existing, and reproduces on
   the committed boot compiler. Three `lib/*.nuc` files cannot be compiled
   standalone: `lib/arena.nuc` and `lib/node.nuc` die `duplicate definition of
   'arena-init' / 'alloc-node'` (the auto-prepended prelude chain
   prelude→node→arena imports the entry file itself, and the entry file is on no
   dedup list), and `lib/reader.nuc` dies `undefined: stderr`. Directly relevant:
   this is the mode §2.4's multi-TU story depends on.
2. **Two separately compiled Nucleus objects cannot be linked**, because each
   inlines the whole prelude: `build/lib/vector.o` and `build/lib/hashmap.o`
   share 7 duplicate public global definitions (`@g-arena`, `@g-intern-table`, …)
   and `ld` refuses. The `exclude-prelude` route works (§2.4 was measured that
   way), but a non-freestanding library is currently unlinkable.
3. **`--emit-cheader` does not export globals.** A `defvar` appears in the
   `.nuch` as `(extern …)` but has no `extern T name;` line in the generated C
   header, so a C consumer cannot reach it.
4. **`--emit-cheader` emits hyphenated, invalid C identifiers.** Independently
   re-confirmed: `(defstruct My-Rec (a-field i32))` + `(defn my-func (x:i32):i32 …)`
   emits `int32_t a-field;` and `int32_t my-func(int32_t x);` while the struct
   **type** name is correctly sanitized to `My_Rec`.

   **The precision matters: `sanitize-for-c` reaches type names but not field
   names or function names — so the fix is a missed call site, not a missing
   mechanism.** It is applied at exactly three places (`cheader.nuc:1761` in
   `type-name-to-c`, `:1852` for the `defstruct` type name, `:2025` for the
   `defunion` type name) and at none of: `emit-cheader-defstruct`'s field names
   (`:1862`, printed raw), `emit-cheader-defunion`'s arm names and
   `%s_%s` enum tag constants (`:2044`, `:2056`, `:2066`), or
   `emit-cheader-declare`'s prototype name (`:1938`, which routes through
   `ns-ir-base` for the namespace prefix but never through `sanitize-for-c`).

   This breaks C interop for **any** hyphenated name, which is most of them —
   hyphens are the ordinary Nucleus word separator. Related to but distinct from
   #3: #3 is a missing feature, this is a missing call.
5. **`(exclude-prelude)` in an *imported* file dies `unknown top-level form`**
   rather than being ignored or diagnosed as "must be the first form of the
   unit". `strip-exclude-prelude` (`nucleusc.nuc:12375`) is only consulted for
   the entry file.
6. The §2.5 misleading message: `undefined: X — not defined anywhere in this
   compilation unit` for a `defvar`/`defconst`/`defenum` that *is* in the unit
   but has not been processed yet. G-0 fixes the cause; the message should also
   gain a W1c-style note in the interim.

**Two more, found while building G-2 (2026-08-02). Both pre-existing, both
reproduce on the committed boot compiler, neither is fixed here.**

7. **Three `fmt-s` call sites pass TWO substitutions to a one-argument
   helper** — `nucleusc.nuc`'s `call: expected %d args, got %d` (~:4313),
   `(dyn %s): '%s' is not a declared protocol` (~:5824), and
   `BoxedFn call: expected %d args, got %d` (~:6310). This is exactly the
   fixed-arity trap `context/conventions.md` opens with: `snprintf` reads a
   garbage vararg and the compiler **segfaults with no output**. Found by
   grepping after making the identical mistake in new G-2 code (where it did
   segfault, immediately). They survive because these particular diagnostic
   paths appear to be unreachable or near-unreachable today — which is the
   lesson, not the excuse: a fixed-arity violation on a cold error path is
   invisible to a green suite indefinitely. The fix is mechanical (`fmt-i32-i32`
   / `fmt-2s`) but it moves the compiler's own IR, so it belongs in a change
   that is already reconverging.
8. **A wrong-arity call to a solitary `defn` is not diagnosed.** Measured:
   `(defn f (a:i32):i32 …)` called as `(f 1 2)` compiles clean and emits
   `call i32 @f(i32 1, i32 2)` against a one-parameter definition — on
   `build/nucleusc` **and** on `bin/nucleusc`, so it is not new. The
   `call: expected %d args, got %d` check at `nucleusc.nuc:~4311` exists but the
   solitary-`defn` path does not reach it. This is very likely *why* finding 7
   above has gone unnoticed: the diagnostic that would have segfaulted is
   unreachable. The two should be fixed together.

**Two more, found while building G-3 (2026-08-02). Both reproduced on the
committed boot compiler and neither has anything to do with global
initialization; #9 is now fixed, #10 is not.**

9. **FIXED, in the interlude between G-3 and G-4 (2026-08-02).** A `defvar`
   whose declared type is a function-pointer type could not be
   declared at all, with or without an initializer:
   `(defvar g:(fn i32)(i32) null)` dies *"'g' already names a function — a
   symbol may name only one kind of thing"*. `name-existing-kind`
   (`nucleusc.nuc:8703`) classifies **any** global `Sym` whose type is `TY-FN`
   as `NK-FUNCTION`, and since **G-0** `prescan-defvar-name` defines that `Sym`
   before `emit-defvar` runs — so the `defvar` collides with itself. This is a
   G-0 regression, not an old wart; it is on the committed boot because that
   boot post-dates G-0.

   It matters for **G-5**: §2.12 counts two fn-pointer hooks among the 48
   globals `compiler-init` initializes, and they cannot be spelled as typed
   globals until this is fixed (the bare-`ptr` escape hatch works, at the cost
   of the type).

   The discriminator already exists and is exact: a *function*'s Sym is
   registered with `is-local = 0` (`emit-defn` `:10382`, the cheader parser
   `cheader.nuc:908`, the `.nuch` declare importer `nuch.nuc:343`), a *global
   variable*'s with `1` (`emit-defvar` `:9715`, `emit-extern` `:10134`). So the
   fix is one added conjunct on the `TY-FN` test — and it is provably inert:
   `name-existing-kind` has exactly one caller, `guard-name-kind`, which only
   ever raises, and no program in the tree can currently contain the shape the
   change would newly admit.

   **Fixed exactly this way**, plus a second, stacked defect it exposed:
   `defvar-init-ir`'s `null` gate tested `is-ptr-like`, which deliberately
   excludes `TY-FN`, so even with the collision fixed the explicit `null`
   initializer was refused while the slot's implicit zero was already `null`;
   a third by-name arm now admits `null` for `TY-FN` without widening
   `is-ptr-like` itself. `examples/fnptr-global.nuc` and
   `tests/fixtures/w8-fnptr-global-name-collision.nuc` /
   `w8-fnptr-null-still-gated.nuc` pin both halves. Landed in the same commit
   as G-4 (`aa24eae`).

10. **`aref` emits its GEP index as a hardcoded `i64` on every target.** On AVR
    (16-bit pointers) any index narrower than `i64` therefore produces IR the
    LLVM parser rejects: `'%t3' defined with type 'i32' but expected 'i64'`,
    surfacing at the link step rather than as a compiler diagnostic. It does not
    route through `ptr-int-ir` (`type-utils.nuc`), which AVR-2 added for exactly
    this class of "the index/offset width is the *target's*, not 64" decision.
    Reproduces identically on the committed boot and is not array-specific — a
    plain `(defvar g:ptr:ui8)` with an `i32` index does it too.
    `examples/avr-global-init.nuc` widens its index to `i64` and says why.

11. **A `defvar` may be declared TWICE in one unit with no diagnostic**, emitting
    two `@g = global …` lines that the LLVM parser then rejects with an
    unlocated error a long way from the cause. Found by G-5 while relocating a
    declaration (two `(defvar g-current-ns:ptr)` forms were transiently live).
    `guard-name-kind` compares the existing kind NK-VALUE against the new kind
    NK-VALUE, finds them equal, and permits it — the same-kind allowance that
    exists for overloaded `defn` and REPL redefinition, applied where neither
    justification holds. A batch `defvar` redefinition should be a located
    error naming both sites, exactly as W1c's two-files-define-one-global check
    already does across files. Reproduces on the committed boot.

12. **`as` did not arm the want channel — FIXED in G-5**, listed here because it
    is a general typing defect rather than a global-initialization one, and
    because the *class* is worth keeping visible. `(as T expr)` names a type at
    its operand's position exactly as a `let`/`with` binding, a `set!` target, a
    `return` and a `.set!` field do, but `emit-as` emitted the operand without
    setting `g-want-type`. A generic whose type variable appears only in its
    return type therefore resolved against whichever instance the unit had
    stamped **first**. In the `as` spelling that surfaces as `as`'s own
    reinterpretation error; in the `unsafe/cast` spelling it is silent and takes
    the wrong instance. Every other declared-type position was already on TC-2's
    arm list; this one was missed. Proven inert for the whole tree by G-5's
    sweep.

---

## 8. The runtime half — settled: build it

**Question, as the first draft posed it:** is the runtime half (G-3) worth
building at all, or is G-1/G-2 plus a documented explicit `init` function the
right permanent answer?

**Answer: build it.** The first draft could not settle this because it was
weighing the wrong corpus. It reasoned from the Doom port's 1-of-21, concluded
the runtime half was "a compiler-internal convenience", and proposed to decide
after converting the port and re-counting. Both halves of that are now
superseded:

* **The deciding corpus is the compiler's own source, not the port's.**
  Acceptance criterion (A) is "eliminate `compiler-init`, or reduce it to a few
  genuinely special cases", and `compiler-init` is a compiler-internal function.
  The port cannot answer a question about it.
* **On that corpus the count is not 1 of 21; it is 45 of 48** (§2.12). Of the
  globals `compiler-init` constructs, **3** are constant and reachable by the
  static half alone; **45** are `vector-new-in` / `hashmap-new-in` /
  `scope-new` / `intern-str` / `make-type` calls, which is bucket 1a by
  definition. Without G-3, 45 of the 48 stay in `compiler-init` and criterion
  (A) is not met — not partially met, not met for most cases. **G-1/G-2 alone
  cannot eliminate `compiler-init`.**
* **The "already work at zero cost" argument was the wrong frame.** They do
  work. The cost is not runtime, it is that 53 globals in the compiler's own
  source are declared non-null and hold `null` for part of the process — the
  exact unsoundness W6 §1.5 parked, in the corpus that matters most. §2.12 D
  found three *more* in a third spelling, never initialized at all. The
  alternative price is measured at §2.11: **249 flow violations, 197 lines, 10
  files** — ~200 new `unsafe/cast`s in a stage whose headline defect is 2113 of
  them.

**What G-3's price turned out to be, re-priced against the rulings:**

| First draft's objection | Status after the rulings |
|---|---|
| an ordinal initialization rule (§4.1) | **accepted policy**, with source reordering sanctioned; two known reorders, both trivial |
| a per-triple mechanism split (§4.6) | **smaller than feared** — §4.8's zero-cost requirement collapses it to `global_ctors` / `none`, and deletes Option 1's `main`-wrapping apparatus from v1 |
| a migration whose failure mode is silent (§2.10) | **dissolved** — the arena handle is a constant, needs no ordering, and the constant *fixes* a pre-existing silent split at `add-include-path` |

**The port's 20-of-21 finding is not retracted and is not diminished.** It is
real external data, it is why the static half ships first, and it is why G-1/G-2
are worth building on their own merits even though they cannot finish the job.
It has simply stopped being the thing the decision hangs on.

**The one question that remains open** is narrower and is recorded in §4.6: does
a `section ".ctors"` global with avr-gcc's word relocation get walked by
`__do_global_ctors`? If yes, AVR gains an append-only mechanism. If no, AVR
programs with runtime initializers get a located error until someone pays
§4.8's early-decision cost. Neither answer blocks G-0 through G-5.
