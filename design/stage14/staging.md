# Stage 14 — staging order across the workstreams

The twelve stage-14 designs — [colon-paren-types.md](colon-paren-types.md)
(CP-1..3, **done 2026-07-02**), [macro-conditional-casts.md](macro-conditional-casts.md)
(MC-1..4, **done 2026-07-03**), [int-widening.md](int-widening.md)
(LW-1..5, **done 2026-07-03** except the LW-5 tree-wide cast sweep),
[symbol-mangling.md](symbol-mangling.md) (SM-1..5, **done 2026-07-03**),
[native-strings.md](native-strings.md) (NS-1..6),
[defn-signature.md](defn-signature.md) (S1..4),
[type-safety.md](type-safety.md) (14.1..14.7),
[unsafe-namespace.md](unsafe-namespace.md) (UN-1..5),
[attributes.md](attributes.md) (AT-1..3),
[target-typed-constructors.md](target-typed-constructors.md) (TC-1..5),
[avr-targets.md](avr-targets.md) (AVR-0..8), and
[riscv-linux.md](riscv-linux.md) (RV-0..5) — each carry local sequencing;
this doc fixes the cross-doc order.

## Dependency edges (from the individual docs)

- **CP-2 → S1**: the lone-colon fuse makes `(defn f (params):(Maybe i32))`
  legal, retiring defn-signature's parenthesized-ret exception. Landing CP-2
  first means S1 ships without the space-separated caveat and S3's ~1,150
  rewrites are written in final syntax once.
- **MC-1/MC-2 → 14.3**: signature retyping enlarges the mixed bare-vs-typed
  join class; join absorption must exist first or 14.3 manufactures new
  `collapse-to-void` failures.
- **S1–S4 → 14.3**: both edit the same signature lines; the syntax move must
  be finished before the type-annotation pass rewrites those lines, or every
  line is touched twice.
- **CP-1 → 14.x (soft)**: the chain fuse `v:ref:(Vector T)` currently
  mis-fuses silently (the Stage-11 guidance "use the list form" exists
  *because* of this). Fixing it first lets the type-safety phases use the
  terse spelling safely.
- **LW-1 → 14.3 (soft)**: type-safety's signature retyping mints new
  literal-vs-`usize`/typed-param call sites; landing the template-tier
  widening first prevents a fresh crop of cast requirements. LW-5's
  tree-wide cast sweep must stay out of S3's quiet-tree window (and runs
  per-file regardless). LW-1+LW-2 are atomic (node-type↔emit lockstep).
- **MC-1 → NS-3**: the literal flip's free `StrView`↔`ptr` coercion creates
  a new mixed-branch join class (`(if c "a" some-ptr)`); MC-1's join
  absorption must exist first — and absorb `StrView`↔`ptr` alongside
  bare↔`(raw Node)` — or NS-3 manufactures new join-collapse failures.
- **NS-3 → 14.3**: any string param 14.x wants to retype to `StrView` needs
  literals to already *be* `StrView` so callers pass `"…"` bare — the same
  enabling-change-before-retyping shape as LW-1 → 14.3.
- **S → NS-5**: NS-5's string-param retyping edits the same signature lines
  as S3/14.3; it runs after S, out of S3's quiet-tree window, folded into or
  immediately after 14.x.
- **NS → UN-4**: NS-4's `c"…"` and explicit `StrView`↔`CStr` cast spellings
  land before UN-4's cast-split sweep so it renames them once.
- **{MC-3, LW-5, 14.2/14.3} → UN-4**: the `cast` split sweep must follow the
  cast-*deletion* work (macro casts, vestigial int casts, ceremonial pointer
  casts), or it renames thousands of casts that are about to be deleted.
  UN-1/UN-2 are additive and edge-free; UN-3 carries one reconverging refresh.
- **{MC-1, LW-1/2, SM} → TC-1/TC-2 (all landed)**: TC's want channel extends
  LW's shared dying/non-dying resolver, TC-5's branch distribution feeds
  MC-1's `type-join`, and TC edits resolution in the file SM just renamed
  through. A completeness review of the MC/LW landings is TC's natural
  precursor (TC-0).
- **TC-4 → 14.1/14.3 (soft)**: TC-4 deletes `mkvec`/`mkhash`/`make-vec` and
  rewrites the registry-construction sites 14.1 is about to retype; landing
  TC-4 first means 14.1 edits final-form constructor lines once. TC-4 also
  deletes casts, upstream of UN-4's sweep. TC-4 is a discrete refresh window
  and stays out of S3's quiet tree; TC-1/2/3/5 are additive/byte-identical
  and slot into the small band.
- **AT — declaration attributes**: no edges to the backbone (declaration-form
  parsing only; zero volatile spellings in src/lib, so additive and
  byte-identical). Slots anywhere outside S3's quiet-tree window. One soft
  outward edge: **AT-1 before AVR-4**, so the hand-written MMIO device
  register files are written in the final `(ptr :volatile T)` spelling once;
  AVR-5/AVR-6 may extend the attribute registry (ISR fn-attrs, `:section`).
- **AVR / RISC-V**: no edges to any of the above — they touch target/link
  plumbing and emission-width helpers, not the type-annotation surface. Soft
  rules: AVR-2 and MC-2 both touch quasiquote emission (helper-IR strings vs
  result typing) — land in either order, not in the same change; AVR-1/AVR-3
  and RV-1/RV-2 share the `Target` cpu/features fields, the
  `LLVMCreateTargetMachine` threading, and the triple-keyed link driver —
  **whichever lands first implements the shared plumbing** (riscv-linux.md
  §4 recommends RV first: smaller delta, CI-verifiable under qemu).

## Proposed order

**Serial backbone** (each item ends with its keep-green/byte-identity gate
and, where needed, one reconverging refresh — never two refresh windows in
flight):

1. **CP — colon-paren-types (CP-1 → CP-2 → CP-3). ✅ Done 2026-07-02**
   (byte-identical, no re-baseline; S1 unblocked).
2. **MC — macro-conditional-casts (MC-1 → MC-2 → MC-3 → MC-4).** Independent
   of CP/S; expected near-byte-identical; removes the join-collapse failure
   class before signatures start gaining types.
3. **LW — int-widening (LW-1+LW-2 → LW-3 → LW-4 → LW-5).** Small and
   independent (generic-resolution + call/return emit paths — no overlap
   with MC's join sites or S/T's signature surfaces); slots here on the
   small-before-big principle and to precede 14.3 (see edges). LW-5's
   per-file cast sweep can trail into later slots but not S3's window.
4. **SM — symbol-mangling (SM-1 → SM-5).** Small and independent
   (`finalize-generics` naming helpers, repl.nuc, export emitters — LW
   touches generic *resolution*, SM touches generic *naming*; no shared
   lines, order between LW and SM free). Byte-identical gate on SM-1 (no
   `?`/`!` names in src/; hyphens untouched is the invariant).
   **NS-1 + NS-2 (native-strings substrate) interleave in this small band**
   — additive/dormant, byte-identical, no refresh window; their only edge
   is MC-1 landing first (item 2).
4½. **TC — target-typed-constructors (TC-1+TC-2 → TC-3 → TC-4 → TC-5).**
   Prerequisites (MC-1, LW-1/2, SM) all landed. TC-1/2/3/5 are additive and
   byte-identical (small band); TC-4 (stdlib constructors + compiler
   adoption + `mkvec`/`mkhash` retirement) is one reconverging refresh,
   scheduled before 14.1 retypes the same construction sites (see edge) and
   outside S3's window. TC-5 may move ahead of TC-4 if refresh windows are
   scarce — they are independent.
5. **S — defn-signature (S1 → S2 → S3 → S4).** The tree-wide mechanical
   rewrite (S3) wants a quiet tree: nothing else in flight during that
   window. Lands the final signature syntax before 14.3 edits the same
   lines.
6. **NS — native-strings flip (NS-3 → NS-4).** The literal type flips
   `CStr` → `StrView` in its own discrete refresh window: after S (the
   flip touches no signature lines and stays out of S3's quiet tree) and
   before T retypes string params to `StrView`. Byte-identical bootstrap
   gate via target-aware emission, proven by the `build/nucleusc.ll`
   before/after diff; only lib/examples IR moves.
7. **T — type-safety (14.1 → 14.7).** The long haul. 14.1/14.2 have no
   dependency on MC/LW/SM/S/NS and *may* be pulled forward in parallel
   with items 2–4 if throughput matters, but the serial placement keeps
   refresh windows discrete and is the default. String-param retyping
   targets `StrView` (NS-3 landed); **NS-5's selective adoption folds into
   or immediately follows 14.x**, with NS-6 closing the workstream out.
8. **UN — unsafe-namespace (UN-4 → UN-5), the tail.** The `cast` split
   sweep runs after the deletion work has left only genuine casts (see
   edge), then the bare spellings become hard errors — the stage's
   close-out. **UN-1/UN-2/UN-3 land much earlier**: they are
   additive-plus-one-refresh, slot between backbone items 2–4 wherever no
   other refresh is in flight (and outside S3's window), and flip the
   new-code convention so later phases write surviving casts in final
   spelling as they go.

**Parallel track — hardware targets (RISC-V, then AVR):**

- **RV-0 + AVR-0 immediately** (one container Dockerfile change + rebuild
  covers both toolchains): long lead time, zero conflict, and they gate
  everything else in those docs. RV-0 also carries the `repl.nuc`
  hardcoded-triple fix, a live aarch64-host bug worth landing on its own.
- **RV-1 → RV-2 before AVR-1..3**: RISC-V implements the shared
  cpu/features/link-driver plumbing as the smaller, qemu-CI-verifiable
  delta; AVR then layers its 16-bit/Harvard specifics on top. RV-3 and
  AVR-4+ schedule freely afterwards.
- The track interleaves with the backbone subject to: (a) its reconverging
  refreshes don't overlap another item's refresh window; (b) the AVR-2/MC-2
  quasiquote-adjacency rule above; (c) stay out of the S3 quiet-tree
  window. If strictly serial instead, slot the track after S4 — before or
  interleaved with T's later phases. The AVR-2 fixes (`ptr-int-ir` ternary,
  descriptor-parameterized qq helpers) are worth landing early regardless:
  they are the long-standing 32-bit blockers.

## Rationale in one line each

Additive-and-small before tree-wide rewrites; tree-wide rewrites before the
long refactor that edits the same lines; failure-class removal (MC-1) before
the work that would enlarge the class; the literal flip (NS-3) after the
signature rewrite that would otherwise touch the same lines twice and before
the retyping pass that targets it; the spelling migration (UN-4) after the
deletions that shrink it; independent hardware track runs beside the backbone
rather than in it; one reconverging refresh at a time.
