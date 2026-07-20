# Stage 14 — Colon-paren type sugar: closing the gaps

**Status:** Implemented 2026-07-02 (CP-1, CP-2, CP-3 all landed; example at examples/colon-paren-types.nuc; make test 139/0, make bootstrap byte-identical).

The request: `name:(Type …)` "does not parse for parenthesized types",
forcing the list form `(name (Result i64 i32))`. Ground-verifying that premise
against the current tree shows it is **mostly stale** — the base sugar shipped
in Stage 11 (`fuse-colon-paren`, lib/reader.nuc:782, design/stage11/cleanup.md
§1) and works in every ordinary binding position. What remains are three
sharp-edged gaps around it: the **colon-chain** form, the **return-position
lone colon** (the "colon-paren caveat" that [defn-signature.md](defn-signature.md)
§3 is currently designed *around*), and **silent mis-parses / confusing
diagnostics** when a spelling near-misses the fuse. This doc records the
verified support matrix and designs the closure.

---

## 1. Ground truth — what parses today (all verified 2026-07-02)

The reader fuse: in list context, a freshly-lexed **symbol ending in `:`**
immediately followed by `(` (no whitespace) is fused with the next form into
`(name <paren-form>)` — the canonical list shape `extract-name-and-type`
already accepts.

Verified **working** (compiled and, where applicable, ran):

| Position | Spelling tested |
|---|---|
| `let` binding | `(let (x:(raw Node) null) …)`, multi-binding mixes |
| `let` with template | `(let (r:(Result i64 i32) (h)) (match r …))` |
| `defn` param | `(defn f:i32 (v:(raw Node)) …)` |
| `defn` return (name pos) | `(defn g:(raw Node) () …)`, `(defn h2:(Result i64 i32) () …)` |
| `defvar` | `(defvar gv:(raw Node) null)` |
| `defstruct` field (bare) | `(defstruct S next:(raw Node) v:i32)` |
| `defunion` arm field | `(defunion U (mk a:(raw Node) b:i32) empty)` |
| `defprotocol` sig param | `(defprotocol P (pm:i32 ((self (ref Self)) n:(raw Node))))` |
| method `defn` param | conforming `defn` with `n:(raw Node)` |
| `with` binding | `(with (v:(ref (Vector i32)) (alloca …)) …)` |
| lambda param | `((fn (n:(raw Node)):i32 …) null)` |
| type-expression position | `(cast ref:(Vector i32) p)` |

Verified **broken**:

| # | Spelling | Symptom |
|---|---|---|
| G1 | `v:ref:(Vector i32)` (chain + paren) | fuses to `(v:ref (Vector i32))` — the *interior* colon stays in the name. `defn` param: `unable to parse type expression`; `let`: binds a name literally spelled `v:ref` (`init type mismatch for 'x:raw'`). Recorded as a Stage-11 limitation ("use the list form"). |
| G2 | `(fn (x:i32):(raw Node) …)` (paren type after `)`) | the atom after `)` is a **lone `:`** — len-1, so not a keyword (reader.nuc:~328), falls through to a plain symbol; the fuse then strips its trailing colon leaving an **empty name**, producing `("" (raw Node))` → `unable to parse type expression`. This is the "colon-paren caveat" that forces defn-signature.md §3 to spell parenthesized returns space-separated. |
| G3 | `x: (raw Node)` (whitespace) | no fuse (adjacency required, by design); the orphan `x:` symbol survives to produce remote errors (`let: binding list must be even`). |

Non-goals confirmed fine: the fn-pointer *triple* binding `(f (fn i32) (i32
i32))` and its sugar `f:(fn i32) (i32 i32)` (docs/types.md §Function Pointer
Types) — the fuse joins only `f:`+`(fn i32)`; the params list stays a sibling
element, as that form requires.

## 2. Design

Three additive reader/diagnostic changes, all localized to `fuse-colon-paren`
and one error site. The reader stays type-ignorant — it produces shapes, and
the existing type parser (`parse-type-from-node`, which already handles nested
constructor lists) assigns meaning or rejects.

### CP-1 — chain fuse: `name:k1:…:kN:(T …)` → `(name (k1 (… (kN (T …)))))`

After stripping the trailing `:`, if the remaining spelling still contains
`:`, split it into segments. The first segment is the binding name; each
remaining segment wraps the paren form right-to-left as a unary constructor
application:

- `v:ref:(Vector i32)` → `(v (ref (Vector i32)))`
- `p:ptr:ptr:(fn i32)` → `(p (ptr (ptr (fn i32))))`

The reader does **not** validate that segments are pointer-kind constructors —
`a:Foo:(T)` fuses to `(a (Foo (T)))` and the type parser rejects it naturally
(`unknown type`), the same division of labor the atom-form chains
(`x:ptr:Node`, split lazily by `split-typed`) already use. An empty interior
segment (`a::(T)`) is a reader error naming the atom.

This turns today's G1 silent-wrong-name hazard into the spelling users
actually reach for, and retires the "use the list form" Stage-11 memo.

### CP-2 — lone-colon fuse: `:(T …)` → the paren form itself

When the trailing-colon token is a **bare `:`** (len 1), fuse to the paren
form directly — no pair, no name:

- `(fn (x:i32):(ref T) …)` reads as `(fn (x:i32) (ref T) …)` — exactly the
  space-separated `NODE-CELL` return form `fn-parse-ret-type`
  (src/nucleusc.nuc:3092) already accepts, so **no emitter changes**.
- Same for a colon-led **keyword with a trailing colon** followed by `(`:
  `:ptr:(Vector T)` (a `NODE-KEYWORD` carrying `ptr:`) fuses to
  `(ptr (Vector T))` via the CP-1 segment rule with an empty name part.
  (Today that keyword+list pair silently mis-parses in ret position.)

This dissolves the **colon-paren caveat**: after CP-2,
`(defn next (params):(Maybe i32) …)` under the defn-signature.md new style is
spelled with the same `:` discipline as scalar returns, instead of the
space-separated exception its §3 currently mandates. Sequence CP-2 **before or
with defn-signature S1** and update that doc's §3/S3 accordingly (the S3
mechanical rewrite can then emit `):(…)` uniformly).

### CP-3 — diagnostics for the near-misses

- **Whitespace miss (G3):** keep adjacency required (the sigil binds tight,
  matching `:keyword` lexing; and fusing across whitespace could rewrite
  quoted data at a distance). Instead, error clearly where the orphan
  surfaces: when a binding-position name (via `extract-name-and-type` /
  `desugar`) is a symbol with a **trailing colon**, die with
  `binding name ends in ':' — write name:(Type) with no space, or (name Type)`.
  A trailing-colon symbol in *value/quoted* positions stays legal (quoted
  data safety), so the reader itself stays silent.
- CP-1's empty-segment case (`a::(…)`) errors at the reader with the atom
  spelling in the message.

### Explicitly out of scope

- **Fusing inside quoted data is unchanged** (pre-existing): the fuse fires
  syntactically, quote or no quote — `'(foo:(bar))` reads as `'((foo (bar)))`
  today and after this work. Quoted-data authors space the paren. Document
  it (it is currently undocumented).
- **`~sym:(Type)` in quasiquote templates**: the unquote wraps the bare
  `sym:` atom before the fuse sees it (`(unquote sym:)` is a cell, not a
  symbol), so templates keep using the `(name type)` list form — consistent
  with the existing `~sym:type` limitation (context/macros-jit.md). A
  template-side fix would live in quasiquote, not the reader; defer.
- **`!`/`?` sugar + paren** (`h:!(Vector i32)`): the atom doesn't end in `:`,
  so the fuse never sees it; the `!T`/`?T` sugars remain atom-internal.
  Spell such returns in list form. Revisit only if demand appears.

## 3. Implementation notes

- All changes live in `fuse-colon-paren` (lib/reader.nuc:782) plus one
  diagnostic in `extract-name-and-type`/`desugar` (src/nucleusc.nuc). The
  fuse's gating (`g-peek-valid == 0`, freshly-lexed symbol, raw next char is
  `(`) is unchanged; CP-1/CP-2 only extend what is done with the matched
  atom's spelling.
- `lib/reader.nuc` is a COMPILER_DEPS source import — the compiler binary
  changes, but since no existing source uses the new spellings, **stage1 ==
  stage2 holds without re-baselining** (same property the Stage-11 fuse
  landing verified). Gates: `make test`, `make bootstrap`, plus a new
  `examples/colon-paren-types.nuc` exercising the matrix in §1 **plus** the
  CP-1/CP-2 forms, with expected output.
- IR-identity spot-check à la the CStr migration: a file spelled with
  chain-sugar vs list forms must emit byte-identical IR (the fuse output *is*
  the list form; only the module-id header may differ).

## 4. Docs (with implementation)

- docs/types.md §Colon-paren binding sugar: add the chain form and the
  ret-position `):(…)` form; add the quoted-data caveat; fix the section to
  state adjacency is required and what the error looks like when it isn't.
- design/stage14/defn-signature.md §3 + S3: add an **Update:** note that
  CP-2 retires the space-separated-parenthesized-ret exception (leave the
  original discussion in place per conventions).
- design/progress.md Known-constraints bullet (Stage-11 "use the list form"
  memo): mark superseded when CP-1 lands.
