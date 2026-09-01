# Stage 17 — migration tooling

Four artifacts, all built and green **before** the first conversion batch
(overview.md Track D). Together they are what makes a ~2,500-site sweep
reviewable instead of hopeful.

The precedent is Stage 16's dot-forms migration
([stage16-ergonomics/dot-forms.md](../stage16-ergonomics/dot-forms.md)), which is
worth reading before starting this one. Its lesson, stated there: the migration
was **compiler-guided rather than regex-guided**, the `--strict-selectors` flag
enumerated **7,254 sites — 5× the sampled estimate** — and it found a class of
site no source sweep could ever reach, because the compiler *synthesizes* the
construct. Both facts apply here verbatim. `context/conventions.md` has a whole
section on the same trap for a different spelling: *"A special-form spelling
sweep must also grep for `intern-symbol "…"` synthesis, not just literal text."*

---

## 1. `make ir-snapshot` / `make ir-verify` — the emitted-output identity gate

> **Built, 2026-09-01, as `scripts/stage17/ir-snapshot.sh {snapshot|verify}`** —
> a script rather than Make targets, because re-baselining has to be a separate
> word (`snapshot` over an existing directory refuses without `--force`) and a
> phony target cannot refuse. 420 inputs, 2,596 artifacts, ~2 min per run.
> Two corrections to what is specified below, both found by running it:
> **`src/nucleusc.nuc` is not in the corpus** (see below), and the reporting
> branch needs `|| true` around its `cmp`/`diff` — they exit non-zero on a
> difference, which under `set -e` + `pipefail` killed the run at the first real
> diff *before it printed anything*, so a failure was indistinguishable from a
> pass with lost output.

The primary gate (overview.md §5.1). Byte-identical bootstrap cannot work for
this stage; **byte-identical compiler output** can, and is stronger.

**Corpus.** Everything the tree can compile: `tests/fixtures/*.nuc` (230),
`examples/*.nuc` (154) and `lib/*.nuc`.

`src/nucleusc.nuc` is deliberately **not** an input, though the first draft of
this section listed it. It is the source being converted, so its emitted IR
moves with every batch by construction and could only be re-baselined, never
verified — which is the opposite of a gate. `make bootstrap` covers exactly that
ground and covers it better, as a fixed point (stage1.ll == stage2.ll) rather
than against a baseline. The Windows cross-emissions moved to `lib/*.nuc` for
the same reason.

**Artifacts per input.** Three emissions, since all three are text the compiler
writes and all three are being converted:

| Flag | Output | Covers |
|---|---|---|
| `--emit-llvm` | LLVM IR | the 928-site emission surface |
| `--emit-cheader` | C header | `src/cheader.nuc`'s writers |
| `--emit-nuch` | `.nuch` | `src/nuch.nuc`'s writers |

Plus both Windows cross-emissions of every `lib/*.nuc` — cheap, and a
cross-target emission difference is a real class of bug that a host-only
snapshot cannot see.

**Protocol.**

```
scripts/stage17/ir-snapshot.sh snapshot   # once → build/snapshot/
… convert a batch …
make && scripts/stage17/ir-snapshot.sh verify
```

`ir-verify` fails on the first differing byte and names the input file, the
artifact and the offset. **No normalization, no whitespace tolerance, no
allowlist.** A diff is a regression until proven otherwise; the whole value of
the gate is that it admits no judgement.

**One caveat to check first.** Diagnostics embed absolute file paths (Stage 15
W1c/W1d added path-bearing notes); IR should not. Verify before relying on the
snapshot that no `--emit-*` output varies with the source's absolute path, and
fix it if it does — a path-dependent artifact is a reproducibility bug in its own
right.

**Refresh points.** The snapshot is re-taken only when a change *intentionally*
moves the output (there should be very few in this stage; C7's `Symbol` flip may
be one if intern ordering shifts the string pool). Every re-take is recorded in
`progress.md` with the reason, so "the gate was re-baselined" can never be a
silent event.

---

## 2. The `fprintf` rewriter

> **Built and used, 2026-09-01, as `scripts/stage17/rewrite-fmt.py`.** C1 needed
> the same machine for the `fmt-*` family first, so the script does that by
> default and the `fprintf stderr` → `eprint` half under `--stderr`; C2's
> `g-out` sites extend it rather than starting over. Measured on C1: **zero
> refusals** across 636 sites — every specifier the compiler actually uses is in
> the table (`%s`, `%d`, `%ld`, `%%`, `%c`, and the three zero-padded hex forms
> for float bit patterns; no `%p`, no `%*`, no `%.*s`). One rule the spec below
> does not state and should: the rewrite is **not transitive in one pass**, since
> a call nested inside another's argument list is consumed as source text. Run it
> to a fixed point.

> **Built and used for C2, 2026-09-01, as the same script's `--writes` mode.**
> One new specifier (`%02X`); `fputs` and `fputc` have their two operands
> swapped, and `fputc`'s byte is spelled as a literal piece where it is a known
> printable. Zero refusals on the first 284 sites.
>
> **The output shape is `(emit S …)`, not the `(write S (str …))` below.** `str`
> allocates and drops a `String`, and this is the compiler's hottest output
> path; `emit` formats into one process-wide buffer and issues one `fwrite`,
> allocating nothing. See `src/strfmt.nuc` for the mark that keeps one shared
> buffer safe.

A script (`scripts/stage17/rewrite-writes.py`) that converts

```lisp
(fprintf g-out "  %%v%d = load %s, ptr %%p%d, align %d\n" n ty n al)
```

to

```lisp
(write g-out (str "  %v" n " = load " ty ", ptr %p" n ", align " al "\n"))
```

**It must be paren-aware, not a regex.** Arguments contain nested calls, nested
string literals and escaped quotes. Reuse a small S-expression scanner; do not
try to do this with line-oriented matching.

**Transformation rules.**

1. Split the format literal at each conversion specifier.
2. `%%` → a literal `%`. This is the single most important rule in the script:
   the compiler's format strings are dense with `%%v`, `%%p5`, `%%fp` because
   LLVM local names are `%`-sigilled, and every one must lose exactly one `%`.
3. Map specifiers to arguments positionally:
   `%s`, `%d`, `%c`, `%zu`, `%p` → the argument verbatim; `%.9g` / `%.17g` →
   the argument wrapped in the float-precision adverb.
4. Adjacent literal fragments merge; empty fragments are dropped; a form with no
   conversions becomes `(write S "…")` with no `str`.
5. `fputs` → `(write S "…")`; `fputc` → `(write S "c")`.

**It must refuse rather than guess.** Bail out, leave the site untouched, and
report it, on: a non-literal format string; a specifier the table does not model
(`%*`, `%.*s`, flags/width combinations); an arity mismatch between conversions
and arguments; a nested `fprintf` in an argument. **The refusal list is itself a
deliverable** — it says which shapes the compiler actually uses that a
straightforward rewrite cannot express, and those become either `str` features or
hand conversions with a note.

**Operating modes.** `--dry-run` prints the specifier histogram and the refusal
list without touching files. `--file F --range A:B` scopes a batch. Re-running on
already-converted source is a no-op (idempotent by construction: it only matches
`fprintf`/`fputs`/`fputc` heads).

**Expected yield.** ~90% of the 928 sites. The residue is hand-converted; if the
yield is much lower, the script is wrong and fixing it is cheaper than converting
100+ sites by hand.

---

## 3. `--strict-cstr` — the enumerator (temporary compiler modification)

A compiler flag that exists only for this stage and is removed at C8. It reports
every site where a `CStr`- or `ptr`-as-string value is produced or consumed
outside a declared C-interop seam:

```
src/generics.nuc:1842: strict-cstr: CStr argument to 'scope-lookup' (not an FFI seam)
src/nucleusc.nuc:4424: strict-cstr: ptr-as-string returned by 'intern-str'
```

**Why this is not optional.** Three reasons, all learned the expensive way:

1. **Grep cannot see synthesized strings.** The compiler builds AST nodes headed
   by `(intern-symbol "…")` and constructs names programmatically; a text sweep
   for `CStr` finds none of them. This exact blindness is documented in
   `context/conventions.md` and cost a missed migration in Stage 14's UN-5.
2. **`ptr` is not a spelling you can grep for.** Most of the compiler's C strings
   are typed `ptr`, which also means everything else. Only the type checker knows
   which `ptr` is a string.
3. **Completeness is a claim.** C6 and C8 both assert "there are no non-FFI C
   strings left". Without an enumerator that is an assertion about greps.

**Allowlist.** A per-file, per-symbol table (the §2.7 list in overview.md), read
from a checked-in file so additions are reviewable diffs. Modes: report-only
(default, from C1 so the count is visibly monotonic downward) and
`--strict-cstr=error` (from C8).

**Implementation note.** This is a reporting pass over types the compiler already
computes, not new analysis — the shape is `--strict-selectors`, which was a gate
on an existing routing decision. Keep it that cheap; if it starts needing its own
dataflow, the design is wrong.

---

## 4. The `CFile` dual-path shim

```lisp
(defstruct CFile fp:ptr)          ; wraps a FILE*
(extend CFile Writer)             ; write-str → fwrite on fp
```

This is what makes C2 incremental. With it, `g-out` and the seven other stream
globals become `(dyn Writer)` **before** a single call site changes — every
existing `fprintf g-out` keeps working because the underlying `FILE*` is still
there, reachable for the not-yet-converted sites. Each site then flips to
`(write g-out …)` independently, against the identity gate, in whatever batch
size is comfortable.

**Removal criterion, and it is strict:** `CFile` is deleted when the last
`fprintf` in `src/` is gone. It must not survive into the finished stage as a
"convenient escape hatch" — a retained shim is how a conversion ends up 95% done
forever. The residual-`CStr` tripwire (overview.md §5.5) covers `CFile` too.

---

## 5. `make bench-selfcompile` — the throughput gate

Wall-clock for `nucleusc --emit-llvm src/nucleusc.nuc`, best-of-N, plus
allocation counts. Run **per phase**, recorded in `progress.md`, not once at the
end — a 5% regression per phase across seven phases is a 40% regression that
nobody attributed to anything.

Two baselines matter separately:

- **Emission throughput** (C2/C3): what `BufWriter` exists to protect.
- **Intern probe cost** (B4/C7): `Symbol`'s table is on a hotter path than
  emission, and B4 gates on it *before* C7 commits the substrate.

---

## 6. Working discipline

- **Batch size:** one surface, one file, one reviewable diff. `src/nucleusc.nuc`
  (492 emission sites) splits further by region.
- **Every batch ends green:** `make ir-verify` + `make test` + `make bootstrap`.
  A batch that cannot go green is fixed forward, never reverted — per AGENTS.md,
  `git restore` / `git checkout <file>` / `git reset --hard` are prohibited.
  A failing build is a source error at a named file and line; read it and fix it.
- **One refresh window at a time.** `make update-bootstrap` is only run at a
  stable milestone, and never while another item's window is open. Check
  [stage16-ergonomics/deferred.md](../stage16-ergonomics/deferred.md) for
  in-flight Stage 16 work before opening the first one.
- **Findings go in the register as they happen**, not at the end
  ([library-gaps.md](library-gaps.md)). A gap noticed and worked around silently
  is the one failure mode that makes the whole stage worthless.

---

## 7. Delegation plan

This stage is large by any measure, so per AGENTS.md the orchestrating session
plans the split and does none of the work itself. Every prompt that has an agent
write or modify compiler code must direct it to read `context/conventions.md`
first — and for this stage, also the "string-type lattice" section specifically,
plus this document and library-gaps.md.

| Work | Agent | Chunking |
|---|---|---|
| A1 `!void`, A3 `(Maybe Struct)` in JIT | **principal-systems-architect** | one each; both are template-stamp internals with bootstrap risk |
| A2 `!T` shape retirement | focused-task-implementer | one chunk |
| B0 gap closure | focused-task-implementer | one chunk per lettered group in library-gaps.md |
| B1–B3 `fmt`/`io`/`file` | systems-impl-engineer | one library per chunk; each is a self-contained design already written in native-io.md |
| B4 `intern`/`Symbol` | principal-systems-architect | one chunk — representation choice + hot-path benchmark |
| D1, D2, D5 tooling | focused-task-implementer | one chunk each |
| D3 `--strict-cstr` | systems-impl-engineer | one chunk (touches the type checker) |
| C1–C6 conversion | focused-task-implementer | one chunk per file per surface; the script does the bulk, the agent handles refusals and the gate |
| C7 substrate | principal-systems-architect | one chunk, undivided — macro ABI moves with it |
| C8 close-out, docs | api-docs-writer + one architect pass on conventions.md | docs and progress separate from the conventions rewrite |
| Every gate run | build-test-runner | after each batch |

**Dispatch one implementation agent at a time**, even where chunks look
independent — the shared bootstrap artifacts and the single snapshot baseline
mean two concurrent conversions cannot both be attributed when the gate fails.
