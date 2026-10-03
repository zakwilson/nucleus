# Macro-produced definitions — examination (2026-10-02)

The question: should the restriction "a macro cannot emit an `extend` together with
its methods" (`docs/macros.md:558`) be removed before ED-4
([ed4-struct-codecs.md](ed4-struct-codecs.md))? **Yes.** It is a symptom of a wider
gap: a definition that only a macro produces is not registered as a method at all.
A small prototype closes it, and existing programs compile unchanged under it.
It should land as ED-4.1, before any of the EDN work.

**Built 2026-10-03 as ED-4.1** (§6, "As built").

## 1. What actually happens today

Probes, compiled with the baseline compiler (the scratch build of this tree):

| Probe | Result |
| --- | --- |
| A macro emits `(do (defn area …) (extend Sq Shape))`, in either order | `type 'Sq' does not conform to protocol 'Shape'` |
| A macro emits an overload of a hand-written `area` | The macro's `area` **shadows** the hand-written one: `(area &c)` fails with `argument 1 has type &Circ, which does not match parameter type &Sq` |
| Two expansions each emit an `area` overload | The second replaces the first; the same type error |
| A macro emits a generic template, `(defn twice (x:T :where (Any T)) …)` | **Silently dropped**: `unknown: twice — not defined anywhere` |
| The same overload emitted twice | An LLVM crash, `invalid redefinition of function 'area'`, instead of the duplicate-definition diagnostic |
| One expansion defines a protocol and `extend`s it | `extend: unknown protocol` |

**Cause.** Methods are registered only by the pre-scan:
`prescan-defn-signatures` (`src/nucleusc.nuc:17711`) calls
`generic-register-method` and then `finalize-generics`. The pre-scan walks a
file's top-level list before any form is dispatched, and
`toplevel-expand-macro` (`:18497`) splices an expansion in later. So a
macro-produced `defn` reaches `emit-defn` with no `Generic`:
- it takes the fallback path that binds a plain `@name` in `g-globals`
  (`:15437`), which is why it shadows and cannot overload;
- if it is a template, it returns early because "it is registered in prescan"
  (`:15270`), which is why it vanishes.

The `extend` check reads the registry, so it never sees the method. The
restriction is a consequence of when registration happens, not a design
decision: no doc gives any other reason for it.

## 2. The fix: register an expansion's definitions when it is spliced

**The prototype** (scratch copy only; not in the tree). `toplevel-expand-macro`
runs the file pre-scan's own sequence over the forms it is about to splice, before
any of them is dispatched:

```lisp
(defn late-prescan (forms:?&Node):void
  (set! g-late-prescan 1)
  (prescan-protocols forms)
  (prescan-struct-names forms)
  (prescan-defn-signatures forms)
  (prescan-value-names forms)
  (set! g-late-prescan 0))
```

**One rule in `finalize-generics`: never rename a method that already has a
symbol.**
- **Why.** Late registration re-finalizes the generic (`generic-add-method`
  clears `finalized`). Its comment, "safe: before any of the affected methods'
  bodies are emitted" (`src/generics.nuc:254`), no longer holds once emission has
  started.
- **The change.** While `g-late-prescan` is set, both renaming sites (`:892`,
  `:1011`) skip a method whose `ir-name` is already set. The duplicate check still
  runs. `ir-fixed` cannot be reused for this, because it also exempts imported
  methods from that check.
- **Effect:** a hand-written solitary `area`, already called as `@area`, keeps
  that symbol. The macro's overload becomes `@area.pSq`.

**Order of the pre-scans.** It has to mirror the file pre-scan's order (protocols
→ struct names → signatures → values). With signatures alone, an expansion whose
`defn` names a struct the same expansion defines fails with `unknown type`.

**Results** (prototype vs. baseline):

| Probe | Result |
| --- | --- |
| Every row of §1 | Fixed. A real duplicate now gets the proper diagnostic. |
| An `extend` with a genuinely missing method | Still refused |
| One expansion with a `defunion`, `defprotocol`, `defstruct`, method, `extend` and generic | Works |
| **The ED-4 shape:** a codec namespace with a protocol, a generic and a derive macro; a `geom` namespace with structs; a `geomenc` companion that runs `(import geom g) (derive-enc g/Pt) (derive-enc g/Qt)`; `main` calls the generic | Works (`202 204`). The baseline refuses it at `geomenc.nuc:4`. |
| `make test` | 1246 passed, the same 5 known LLVM-22 data-layout failures |
| `make bootstrap` | PASS |
| Baseline and prototype compilers on the same input | **Byte-identical IR** for `src/nucleusc.nuc` and every `examples/*.nuc`. The change does nothing to existing programs. |

## 3. What remains, and why

- **Forward references are kept.** A macro-produced definition is still not
  visible to forms *above* its expansion. A `defn` on line 5 that calls an
  `area` produced on line 9 still fails. Lifting this means expanding top-level
  macros during the pre-scan. That conflicts with the compile-time mirror (Stage
  20 L4–L6): a macro body may call program helpers, and those must already be
  emitted when it runs. It is not needed for ED-4, since a companion library
  imports the types above its `derive-edn` call and the program imports the
  companion. It is documented as ordinary definition order, as it is now.
- **Symbol naming depends on order, for late methods only.**
  - In one namespace, the first macro-produced `enc` keeps the solitary symbol
    (`@geomenc__enc`), and later ones are mangled (`@geomenc__enc.pgeom__Qt`).
    Hand-written overloads are all mangled.
  - This is deterministic, and `.nuch` export reads each method's real `ir-name`
    (`defn-form-mangled-name`, `src/generics.nuc:1533`), so header and object
    agree.
  - The alternative, always mangling a macro-produced method, would change the
    symbol of every existing macro-produced solitary function and make it
    uncallable from C. Not worth it.
- **A function-pointer reference** to a name that has gone from solitary to
  overloaded through a late method still finds the old solitary binding in
  `g-globals`. A value reference to an overloaded name is already an edge case.
  ED-4.1 should test it and either remove that binding when the generic becomes
  mangled or refuse the reference.
- **The REPL** does not accept a top-level macro that expands to a `defn` at all:
  `unknown: defn`, with or without the change. A separate gap, out of scope.
- **Top-level `macrolet` bodies** (`emit-toplevel-macrolet`, `:18477`) have the
  same invisibility. The same `late-prescan` call on the spliced body fixes them.

## 4. A separate bug this turned up: `(do …)` expansions vanish from a namespaced `.nuch`

`apply-leading-ns` (`src/nucleusc.nuc:18291`) hands the dispatch loop
`(node-rest forms)`, which is a **new list header**. `node-splice-at`
(`lib/node.nuc:160`) replaces that header's `elems`, so a `(do …)` expansion
spliced into it never reaches the caller's list. `emit-nuch-header` (`:20313`)
reads the caller's list, so it sees the original macro call and exports nothing
for it.

- **Without `(ns …)`** both derived definitions appear in the header.
- **With `(ns …)`** neither does, and the same happens on the baseline.
- **A single-form expansion survives,** because `node-set-at` writes into the
  shared array.

Every companion library is namespaced, so under separate compilation its header
would lack the derived codecs. The program would then fail to compile or link
against that header.

**Fix:** have `emit-nuch-header` (and the C-header writer, which should be checked
the same way) read the list the dispatch loop actually walked, or splice without
replacing a header the caller does not hold. **Test:** a namespaced library whose
macro expands to `(do (defn …) (defn …))`, compiled with `--emit-nuch` and
imported through its header.

## 5. Plan

Fold into ED-4.1 ([ed4-struct-codecs.md](ed4-struct-codecs.md) §3):

1. `late-prescan`, plus the never-rename rule (§2), for top-level macro expansions
   and top-level `macrolet` bodies.
2. The function-pointer binding check (§3).
3. The `.nuch` splice bug (§4).
4. Tests:
   - each row of §1 and §2, in `tests/suite-s22.nuc` or a macros suite;
   - the duplicate-definition diagnostic for a macro-produced pair;
   - the three-namespace companion shape, compiled as one unit **and** through
     `.nuch`.
5. Docs: `docs/macros.md:554-562` loses the `extend` restriction and keeps the
   forward-reference rule; `context/conventions.md` gets one line on the
   never-rename rule.
6. Gates: `make test`, `make bootstrap`, the dump-ast corpus, and a byte-identical
   self-IR check against the previous compiler.

## 6. As built (2026-10-03)

All five plan items landed as §2–§4 describe:

- **`late-prescan`** (`src/nucleusc.nuc`, beside `toplevel-expand-macro`) runs at
  both call sites in `toplevel-expand-macro` and over a top-level `macrolet` body.
- **`late-renamable?` and `generic-unbind-solitary`** (`src/generics.nuc`), plus
  `scope-unbind-ir` (`src/scope.nuc`). A hidden binding's key becomes `#unbound`,
  a name no source spelling can reach; the `Sym` itself stays, because its
  address may already be held.
- **The function-pointer case behaves as for written overloads:** after a late
  overload, `area` as a value is `undefined: area`.
- **`g-root-forms`:** the walked root list, which `--emit-nuch` and
  `--emit-cheader` now read.
- **Tests:**
  - in `tests/suite-s22.nuc`:
    - `s22-macro-extend-either-order`
    - `s22-macro-overloads`
    - `s22-macro-template`
    - `s22-macro-definition-kinds`
    - `s22-macrolet-body-extend`
    - `s22-macro-overload-not-a-value`
    - `s22-macro-companion-source`
    - `s22-macro-companion-nuch` (three namespaces, compiled separately and linked)
  - diagnostics manifest rows `s22-macro-dup-defn` and `s22-macro-extend-missing`.
  - The extend, macrolet and header cases fail on the previous compiler.
- **Gates:**
  - `make test`: 1256 passed, plus the 5 known LLVM-22 data-layout failures;
  - `make bootstrap` PASS;
  - `check-headers` clean (89 headers);
  - dump-ast corpus: only the edited sources' own dumps differ;
  - the previous and new compilers emit **identical IR for 215 inputs** (the
    compiler, every example, every `lib/*.nuc`).
- **Docs:** `docs/macros.md` (top-level macros, `macmap`) and
  `context/conventions.md` (the top-level-expansion entry).
