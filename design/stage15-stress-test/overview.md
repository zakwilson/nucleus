# Stress testing

This stage involves addressing deficiencies found while attempting to use the Nucleus language for projects other than its own compiler.

## Where the findings came from

The first external project is a **port of Doom** (chocolate-doom → Nucleus),
living at `/home/zak/code/nuc-doom-claude`. Phases 0–5 are complete: core
math/tables, WAD loading, video, the full software renderer, the playsim, monster
AI, damage/pickups/weapons, sector movers, line/sector specials, and the whole
digital-sound and MUS→MIDI music stack. Roughly 25,000 lines of Nucleus across
~60 files in one translation unit, verified bit-exact against the real engine on
demo playback.

That port keeps a curated findings report at
**`/home/zak/code/nuc-doom-claude/NUCLEUS-FINDINGS.md`**. It is the input to this
stage: every item was hit while porting real code, not synthesized to find
faults, and nearly all were confirmed with a deliberate minimal probe. Section
numbers referenced throughout this stage's docs (`§1.1`, `§2.5`, …) are that
file's.

Its own §8 ranks the findings by porter-pain-removed per unit of work. This stage
follows that ranking, with two adjustments: cheap wins that share a code path
with a ranked item get folded into it, and one item (flow typing) is design-only
because it needs a decision before it needs an implementation.

**Not everything here comes from the port.** W7 came out of the author's own
stress testing of the language rather than `NUCLEUS-FINDINGS.md`, and has no `§`
number. It belongs in this stage anyway because it is the same *kind* of finding:
something invisible while writing compiler code and immediate the moment you
write ordinary Nucleus. Later items from that source should be filed here too.

## Why this matters beyond the port

The port is a proxy for "a real C codebase, ported by someone who did not write
the compiler". Three of the findings are things a *new user* hits on day one —
`import-use` of a real C header not working (§1.4–1.6), line-0 diagnostics
(§5.1), and the `defconst` annotation silently registering nothing (§3.2). Those
are disproportionately important relative to their difficulty: they are the first
impressions of the language.

The largest finding (§2.1, cross-file resolution order) is different in kind. It
is not a bug so much as an emergent property of single-pass, import-order-driven
symbol registration — and it took the port *five phases* to state correctly, each
phase recording a different partial symptom. It also dictates that project's file
layout, which is the clearest possible evidence that the compiler is imposing
structure on user code.

## Work items

Each has a spec doc (source of truth) and is dispatched from
[prompt.md](prompt.md), which is the orchestrator's instruction set.

| | Item | Findings | Size | Doc |
|---|---|---|---|---|
| **W1** | Whole-unit signature resolution | §2.1 §2.2 §2.3 §2.4 | Large | [resolution.md](resolution.md) |
| **W2** | `node-type` ↔ `emit` literal-operand lockstep (**done**. **W2a** — §1.2/§1.3 and the binop half of §3.6. **W2b** — §3.1: a `defconst`/`defenum` name now behaves like the literal it stands for, and a constant too large for `i32` no longer wraps. **W2c** — the §3.8 doc correction folded into W2b's doc pass. **W2d** — §3.6 in full: the general coercion chokepoint had no float case at all, which rejected an `f32` target in eight positions *and* silently miscompiled a `float` call argument; a float literal now adapts at every typed target with no instruction, a value narrows silently via `fptrunc` (Option A, matching the integer policy), and `(defvar g:f32 3.14)` no longer emits an LLVM-invalid constant) | §1.2 §1.3 §3.1 §3.6 §3.8 | Medium | [literal-typing.md](literal-typing.md) |
| **W3** | C header interop (**W3a done** — §1.6: an opaque forward-declared C type (`struct Foo;`, `typedef struct Foo Foo;`, and `FILE`) now registers layout-less, is usable as `ptr:Foo` everywhere including a `defn` signature, is refused by value at six sites with the misuse's line *and* the header:line it was declared on, and is upgraded in place by a later definition. **W3b done** — §1.5 turned out to be a *type-qualifier position* defect, not a `void` one: an east qualifier (`int const *p`) ended the type and started a phantom second parameter, which was invalid IR only in the `void` spelling and silently wrong-ABI in every other; qualifiers are now accepted wherever C allows them, and a recognized declaration the importer cannot describe is skipped with a `<header>:<line>:` warning instead of emitted. `SDL2/SDL.h` imports, links and runs. **W3c done** — §1.4 was much broader than "`off_t`'s chain degrades somewhere": **no scalar typedef resolved at all** (`c-parse-type` returned `ptr` for every non-builtin name; only `size_t`/`ssize_t` worked, hardcoded), so `lseek`'s `off_t` return *and* parameter, `getline`/`ftello`'s `ssize_t`/`off_t`, SDL's `Uint8`/`Uint32`, and struct **layouts** (`%timeval`, `%__fpos_t`, `%Mix_Chunk`) were all silently wrong. Typedefs now resolve transitively through a flat table filled at the point each `typedef` is parsed (chains cost one lookup; cycles are impossible by construction), covering scalar/pointer/function-pointer/enum/struct-alias shapes, with `enum` added as a declaration specifier and glibc's `__extension__ typedef` consumed. A typedef the parser cannot follow is never a silent `ptr` — which finally makes W3b's deferred "unresolved type names" gate arm implementable. **Precedence:** an explicit `(declare …)` now beats a header-derived one *in both orders* (measured, it was silent **first**-wins, not the spec's "last wins"), with a mismatch warning naming both sources; the explicit declaration is emitted at the point of first need, since suppression alone leaves the name undefined between the import and the declare. Two pre-existing defects surfaced and were fixed: the C-header `declare` emitter never applied the aggregate C ABI (unreachable until typedefs resolved — `div`/`ldiv`/`fopencookie`), and the cheader path never set `StructDef.emitted`, so a C union with a struct member was never defined while the struct containing it referenced it. Warning policy split into two tiers: the volume W3b measured at zero became 165 the moment typedefs resolved (149 `long double`), so parse failures stay loud at import while "Nucleus has no such type" is reported at the point of *use*. Also took W3b's deferred musl `struct Tag *f(int);` fallback. Ladder closed: rung 1 runnable end-to-end (`examples/cheader-posix.nuc`), rung 2 and rung 3 reached. **W3c fallout, fixed** — the precedence rule surfaced that `declare`'s parameter list **ignored every written type unless the parameter was named**, silently emitting `i32`, so a bare-list declaration that agreed with a header "conflicted" with it and the corrupted signature won; an unnamed parameter is now parsed as a type operand, an unresolvable one is a located error rather than a default, and `&rest`/`&optional` are refused in a declaration. The only part of W3 that changed the compiler's own IR (its own `(declare repl_print_f64 (ptr):void)` had been declaring an `i32`). **All of W3 is now done**) | §1.4 §1.5 §1.6 | Medium | [cheader.md](cheader.md) |
| **W4** | Diagnostics: locations and silent failures | §5.1 §5.2 §5.3 §3.2 §6.1 §6.2 | Medium | [diagnostics.md](diagnostics.md) |
| **W5** | Ergonomic gaps and the union crash (**W5a/W5b/W5c/W5d/W5f done** — §4.4 `\xHH` string escapes; §4.3 unary `bit-not` as a macro over `(bit-xor x -1)`, and W4a's stopgap suggestion removed with it; §3.7 `CStr`-typed `defvar`; §3.9+§3.10 array-literal ergonomics; §1.1 the union/function-pointer segfault — which was **not a union bug at all** but a colon-paren *reader* gap: a function-pointer type is two paren groups and the fuse absorbed one, so the stray `()` read as a NULL node that ten sites dereferenced. Only W5e remains, sequenced after W1) | §1.1 §2.5 §4.3 §4.4 §3.7 §3.9 §3.10 | Medium | [ergonomics.md](ergonomics.md) |
| **W6** | Nullability flow typing (**design only**) | §3.3 | Design | [nullability.md](nullability.md) |
| **W7** | The bare-symbol selector always means "field name" (**done** — provenance: the author's own stress testing, *not* the Doom port's `NUCLEUS-FINDINGS.md`, but the same class of finding the stage exists to collect). `(m k)` / `(get m k)` on a `HashMap` died with `no field 'k' on struct 'HashMap.cstr.i32'` because `selector-literal-sym` classifies a selector by node kind alone and `emit-get-with-callee` had **no edge from its symbol branch back to its value branch**; `(invoke m k)` could not serve as the escape hatch because `invoke` never fell back to `get`. **Shipped:** a bare symbol demotes to a value selector when the callee provably has no such field and the name is a **local** (locals only — every function is in the global scope, so demoting on globals would re-interpret `(sd name)`); `invoke` falls back to `get`, making it the always-a-value spelling paired with `'sym` as always-a-name; and the "no field" diagnostic names the shadowing local. **Zero blast radius, measured** — A/B-diffing emitted IR for every example against the pre-change compiler gives 135 byte-identical, 0 differing, 1 newly compiling. 297→300 tests. Blast radii for the rejected alternatives were measured the same way: scope-first would silently re-interpret **79** sites in `src/` and turn `get-dispatch-test.nuc`'s `(= (self key) key)` into infinite recursion; the `invoke`-symmetric rule costs **26** lines. **Deferred to its own stage:** *marked selectors* (a field name must be written `'field`), the recommended end state — **~3,800** sites, 0 currently quoted. `:field` is **rejected**: keywords are designed as HashMap keys, so `(m :name)` would be ambiguous exactly on the type that motivated them. | — | Small (done) / Large for the end state | [selector-ambiguity.md](selector-ambiguity.md) |

Deferred to a later stage, with reasons, in [prompt.md](prompt.md) §7: struct
packing (§4.1) and fixed-size array fields (§4.2) — both real gaps, both wanting
a layout-attribute design that overlaps
[stage14/attributes.md](../stage14/attributes.md).

## Ordering

**W4 first, then W2, then W3, then W5, then W1.** Cheapest-and-most-isolated
first, matching this repo's established practice — and with one specific
motivation: **W4 makes every later item easier to debug.** Chasing a resolution
bug (W1) with line-0 errors is materially worse than chasing it with real
locations, and the port's own experience bears that out.

W1 is last despite being ranked first, because it is the only item that changes
*when* things happen rather than *what* they compute, so it carries the highest
risk to the bootstrap fixed point. It should land against a green tree with the
diagnostics already improved.

W6 is a document and can be written at any point. W7 likewise — it is written,
and its implementation is independent of every other item (it touches only
`emit-get-with-callee`/`emit-invoke-with-callee` and, in the recommended variant,
`lib/hashmap.nuc`).

## Definition of success for the stage

Beyond the per-item accept criteria: the Doom port should be **re-verifiable
against the improved compiler with its workarounds removed**. Specifically, after
W1 and W2 land, that port should be able to drop the load-bearing import ordering
in `src/g_game.nuc` and its `(as ui32 SOME_DEFCONST)` comparison casts and still
build, with both demo gates bit-exact. That is the real regression test for this
stage, and it lives outside this repo — see [prompt.md](prompt.md) §6.
