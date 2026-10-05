# Core link names: the `nuc_` prefix

Stage 23 follow-on to [ambient-namespaces.md](ambient-namespaces.md) §8. Ruled
2026-10-05 and **built the same day** (§6). **Reverses D-IR.**

## 1. The problem

A user `defvar`/`defn` whose link name matches a core one gives an LLVM or link
error with no source location (AN-2 Open). Structs get a located refusal
(`struct-link-name-unique`).

**Root cause.** Every definition has a registry key and a link name. The
duplicate checks compare keys, and keys differ: `nucleus.arena/g-arena-used`
against `g-arena-used`. LLVM compares link names, and under D-IR `ns-ir-prefix`
answers `""` for both `user` and every `nucleus.*` namespace. So both definitions
are `@g-arena-used`, and the first thing to notice is LLVM's IR parser.

Probes against the AN-4 compiler:

| Program | Result |
|---|---|
| `(import-use nucleus.arena) (defvar g-arena-used:i64 7)` | `failed to parse generated IR: d1.nuc:529:1: redefinition of global '@g-arena-used'`. 529 is an IR line, labelled with the `.nuc` path. |
| `defn node-int (v:i64)` beside core's `node-int (v:i64)` | Located "duplicate definition": R2 keys generics by bare name, and the two methods share the empty prefix. |
| `defn node-int (v:i32)` beside core's | Compiles, and core's `@node-int` becomes `@node_int.i64`. A core link name depends on the user program. Overloading `node-list-new` the same way made `quote` fail with "needs the node runtime" though it was imported. |
| `defn` named like a core `defvar` | Located (one symbol, one kind). |
| `(import-use "stdio.h") (defn printf (s:i64):i64 s)` | Compiles silently. The header's `declare` is dropped and the program's `@printf` takes libc's symbol. |
| `(ns app) (extern environ:ptr)` | Emits `@app__environ`: a hand-written extern takes the namespace prefix. |
| `(ns app) … (defn main …)` | Emits `@app__main`; the link fails with "undefined reference to `main'". |

Core definitions are `weak_odr` and a root file's are strong, so across separately
compiled objects the collision would be a silent replacement rather than an
error (not tested).

## 2. Rulings (2026-10-05)

- **E: the core libraries link under one reserved prefix, `nuc_`.** A core link
  name is `nuc_` + today's name: `@nuc_node-push`, `@nuc_g-arena-used`. One
  prefix, not one per library. All core names already coexist in one bare link
  space, so a flat prefix keeps today's uniqueness guarantee exactly.
- **Types too:** `%nuc_Node`, and `struct nuc_Node` in the C headers. Breaking the
  C API is fine before version 0.
- **Foreign symbols are not prefixed.** A core `extern` of a C global
  (`stderr`, `environ`) and a C-header declaration keep the C name.
- **Boot refreshes are fine.**
- **A and C are in scope** (§4.3, §4.4): a located link-name uniqueness check,
  and a correct location on IR-parse errors.

**B is not a separate mechanism.** `finalize-generics` already decides solitary
versus mangled per *emitted prefix* (W9 item 23,
`generic-user-methods-with-prefix`). Under E, core and `user` have different
prefixes, so a core method stays solitary `@nuc_node-int` whatever the user adds,
and `methods-share-symbol-space` stops pairing them as duplicates. B becomes a
test (§5).

## 3. Not addressed

- A user definition that interposes a libc symbol the unit never declared
  (`(defn time …)` without `time.h`). The compiler cannot see it.
- A name overloaded *between core libraries* can still be solitary in one
  program and mangled in another, depending on which core libraries are loaded.
  This is unchanged from today; per-library prefixes would fix it, and the
  ruling chose one prefix.

## 4. Design

### 4.1 CL-1: the prefix

- **`ns-ir-prefix`** answers the core prefix for `core-ns?`. **`ns-compose`** is
  the one place that joins prefix and base (7 call sites, and `mangle-fn-name`
  goes through it), so it joins the core prefix with no `__`: `nuc_` + base.
  Struct registration (`abi.nuc`, `ns-ir-prefix (key-namespace name)`), method
  prefixes, `.nuch` re-resolution and the C header (`ns-ir-base`) all follow.
- **The compiler's hand-written core names go through one `core-link-name`.**
  Functions: `alloc-node`, `node-list-new`, `node-push`, `node-extend`,
  `node-at`, `node-len`, `node-first`, `node-rest`, `intern-symbol`,
  `symbol-intern-bytes`, `drop`, `invoke`. That is the `@`-string census of
  `src/` intersected with core definitions; re-run it when building. Types:
  audit hand-written `%StrView`, `%String`, `%AllocHandle` and `%Vector.ptr`. The
  macro-JIT `declare`s (`macro-jit-declare-raw`) and `host-exports?` take the
  same names.
- **`extern` splits into two meanings.** Today it does both:
  - a `.nuch` re-declaring a Nucleus global (`(extern (g-arena ptr))` in
    `arena.nuch`) needs the defining namespace's prefix;
  - a hand-written foreign global (`(extern stderr:ptr)` in six core files)
    must stay bare.
  
  Both currently go through `ns-ir-base` (the `NUCH-*` modes at
  `nucleusc.nuc:15924`). Prefix only in the `.nuch` modes. This also fixes the
  `@app__environ` bug.
- **`main` is always `@main`,** in any namespace. This is the same class of bug
  (a link name that must be fixed), and cheap to fix while this code is open.
- **Already in the reserved space:** the compiler's synthesized `@nuc_err_names`
  and `@nuc_err_messages`. They need no change.
- **C headers:** regenerate with `scripts/check-headers.sh --fix`. Function names
  become `nuc_node_push`; types become `struct nuc_Node`.
- **Boot.** The JIT resolves macro callees against the compiler's own
  `-rdynamic` exports, so the first compiler built by the old boot exports bare
  core names while emitting `nuc_` ones. Refresh the boot, then re-converge.

### 4.2 CL-2: the reservation

Refuse every non-core definition whose computed link name starts with `nuc_`, at
the definition's line. Check the link name, not the spelling, so the check also
catches a namespace whose prefix composes to `nuc_…`. Refuse `(ns nuc_…)` and a
`set-ir-prefix` that composes to `nuc_…` once, at that form. Externs and
C-header declarations are exempt: a foreign library may own such names.

Collateral: `tests/abi/callee.nuc` and `interop.nuc` define `nuc_pair_make` and
three more, called from `driver.c`. Rename them.

### 4.3 CL-3 (option A): located link-name uniqueness

E removes core-versus-user collisions. These remain reachable:

- two namespaces composing the same prefix (`set-ir-prefix`);
- a `user` name spelled like a composed one (`app__x` against `app/x`);
- a namespace with `(set-ir-prefix null)` against `user`;
- a definition against a C declaration (the `printf` probe).

The fix is two indexes: one for globals (`@`), one for types (`%`). Each maps a
link name to (key, file, line). They are filled at the production sites: method
`ir-name` finalization, `emit-defvar`, `defconst` storage and struct
registration. A definition whose link name is already held by a **different
key** is refused with `die-at`, naming both sites and suggesting a rename or an
`(ns …)`. The same key is a REPL redefinition and passes. The type index
absorbs `struct-link-name-unique`.

**C declarations (default taken; overturnable as D-CDECL):** a definition whose
link name matches a C-header or `extern` declaration in the unit is allowed when
its LLVM signature equals the declaration's, because that is how a program
implements its own header. Otherwise it is refused, naming the header. Today the
mismatched case silently drops the declaration.

### 4.4 CL-4 (option C): IR-parse diagnostics

Both `LLVMParseIRInContext` sites (`compile-and-link`, and the JIT at
`nucleusc.nuc:16406`) name the memory buffer after the source file. So LLVM's
`<buffer>:line:col` prints an IR line against a `.nuc` path. Name the buffer
`<generated IR for FILE>` and suggest `--emit-llvm` to inspect it. After CL-3,
this is a backstop for compiler bugs, not a user-facing path.

## 5. Phases and gates

| Phase | Delivers | Gates |
|---|---|---|
| **CL-4** | Buffer naming at both parse sites | suite |
| **CL-1** | Core prefix, `core-link-name`, extern split, `@main`, headers regenerated, boot refreshed | suite; bootstrap converged from a clean `build/`; IR corpus identical after normalizing `@nuc_`/`%nuc_` to bare, with every other diff listed; examples 162/162; `check-headers.sh` clean |
| **CL-2** | Reservation refusals; ABI test renames | suite; `make abi-test` |
| **CL-3** | Global and type link-name indexes; C-declaration rule | suite; corpus unchanged |

CL-4 is independent and goes first. CL-2 and CL-3 need CL-1.

**Tests**, from the §1 probes:

- the `defvar` collision compiles and runs (prints 7);
- a same-signature user `node-int` coexists with core's. The bare call in the
  user file either resolves by lookup order or gets a located ambiguity; it is
  never a link error. Pin whichever happens and record it here;
- a different-signature overload leaves core's symbol `@nuc_node-int` (B);
- `quote` works beside a user `node-list-new` overload;
- `(ns app)` with `extern environ` and `main` links and runs;
- the `printf` mismatch is refused, located; a matching-signature definition of a
  header-declared function is accepted;
- a `nuc_` definition, `(ns nuc_x)` and `(set-ir-prefix "nuc_x")` are refused;
- two namespaces with one `set-ir-prefix` and the same `defvar` are refused,
  located.

**Docs:** link names and the `nuc_` reservation in the namespaces and C-interop
docs. Add to `context/conventions.md`: compiler-written core names go through
`core-link-name`.

## 6. As built (2026-10-05)

All four phases. Suite 1321 passed + the 5 known LLVM-datalayout failures
(9 new tests: 4 `cl1-*`, 2 `cl2-*`, 2 `cl3-*`, plus the re-pointed
`an2-core-link-name-collision`). Bootstrap converged, and a clean `build/` gives
boot == stage1 == stage2. Examples 162/162. `make abi-test` passes.
Self-compile time went from 7.67 s to 7.88 s (+3%, three runs each).

**CL-4.** `compile-and-link` names its LLVM buffer `<generated IR for FILE>`,
and the message suggests `--emit-llvm`. The JIT parse site already named its
buffer `<compile-time>` and blamed the form's line, so it is unchanged. No test:
CL-3 left no user-reachable trigger.

**CL-1.**
- **Prefix.** `ns-ir-prefix` answers `g-core-ir-prefix` (`nuc_`) for
  `core-ns?`, and `ns-compose` joins that one prefix with no separator.
- **`main`.** `def-compose` wraps `ns-compose` for top-level names and keeps
  `main` bare. It is used by `ns-ir-base` and both solitary sites in
  `finalize-generics`.
- **Hand-written names.** These go through `core-link-name`:
  - the census found 10 names, at 47 sites: `alloc-node`, `node-list-new`,
    `node-push`, `node-extend`, `node-at`, `node-len`, `node-first`,
    `node-rest`, `intern-symbol` and `symbol-intern-bytes`;
  - `drop` and `invoke` appeared only in comments;
  - no hand-written `%` type string named a core type (the census hits were
    comments).
- **`extern` split.** `emit-extern-mode` takes `from-header`. A `.nuch`
  re-declaration composes the namespace prefix, and a hand-written extern links
  as its own name.
- **C headers.**
  - A core struct's C tag is its link name (`cheader-type-c`, and
    `type-name-to-c` for a registered struct).
  - An instance's C name is its stamp's link name (`nuc_Vector_i32`).
  - 46 headers were regenerated. The `.nuch` files changed too, because a
    `defmethod` carries its mangled link name.
- **Boot.**
  - The old boot built a stage1 that exported bare core names while emitting
    `nuc_` ones. A temporary shim in `jit-add-module-rt` (`@nuc_` → `@` when the
    host lacked `nuc_alloc-node`) let stage1 build stage2, which was already a
    fixed point.
  - The shim was deleted before the final convergence.
  - Not covered by the shim, and moot once the boot was refreshed: stage1's CT
    mirror asks `host-exports?` directly, so stage1 could not run some macros
    in programs (`with-handler`, `macrolet`). It still compiled `src/`.

**Deltas from §4:**
- **The node-runtime check.**
  - `require-node-runtime` asked `core-global`. A program overload of
    `node-list-new` makes the name registry-dispatched, so the solitary global
    is never bound and the check refused `quote`.
  - `core-method-loaded?` now looks for the core method by its link name, in a
    file reached for real.
- **Same-signature overloads.** A `user` `node-int (v:i64)` beside core's is a
  located ambiguity at the bare call ("ambiguous overload for 'node-int' under
  argument widening"). It is not a link error. Pinned by
  `cl1-same-signature-ambiguous`.
- **Core type names spread into program symbols.** A mangled token names a type
  by its link name, so they now appear in names such as `@n_q.pnuc_Vector.i32`
  and stamps such as `%nuc_Maybe.nuc_Vector.i32`. This is required: a `user`
  `Vector` and core's `Vector` must mangle apart.

**CL-2.** Each definition kind is checked at the site that writes its link
name:
- functions in `defn-link-check`, at `emit-defn`'s `define`. It asks the
  method's `src-ns`, because the current namespace is the stamping file's for a
  template instance;
- globals in `global-link-check`, from `emit-global-def`;
- types in `struct-link-name-unique`, now also called for `defunion`. Its core
  exemption is keyed on the type's own namespace, not the current one.

A private definer is exempt. So is the file-private prefix `a_p1__`, even when
a file is named `nuc_…`. `emit-ns` and `emit-set-ir-prefix` refuse a prefix
that is `nuc` or begins with `nuc_`.

**CL-3.**
- **Index.** `g-link-claim-index` maps an `@` name to a `LinkClaim`, and is
  filled only for program IR. Identity:
  - a function's is its generic key, so a REPL redefinition or a template's
    re-emission passes;
  - a global's is `ns/name`.
- **C declarations** are recorded first, from `cheader` function registration
  and hand-written externs, with their LLVM signature (`fn-link-sig`). A
  definition that matches takes over the claim; one that does not is refused,
  naming the header and line. The takeover appends a new claim rather than
  editing the declaration's.
- **REPL rollback.** Each claim records the claim it replaced in the index
  (`prev`). `ReplState.n-link-claims` saves the count, and
  `link-claims-truncate` drops the newest claims first, pointing each link
  name back at its `prev` or removing it. This is an exact undo. The field is
  exempt in `check-repl-roster.py`, since unwinding the index is more than
  plain truncation. Pinned by `cl3-repl-rollback-drops-claim`.
- **Types** keep `struct-link-name-unique`'s scan of `g-structs`. A separate
  index was not worth it at this size.

**Open:**
- `--emit-llvm` output still carries the bare `ModuleID`. Only the in-memory
  parse buffer was renamed.
