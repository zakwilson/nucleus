# Stage 14 — staging order across the six workstreams

The six stage-14 designs — [colon-paren-types.md](colon-paren-types.md)
(CP-1..3), [macro-conditional-casts.md](macro-conditional-casts.md)
(MC-1..4), [defn-signature.md](defn-signature.md) (S1..4),
[type-safety.md](type-safety.md) (14.1..14.7),
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

1. **CP — colon-paren-types (CP-1 → CP-2 → CP-3).** Smallest, additive,
   stage1==stage2 without re-baselining; unblocks S1 and removes the
   silent-wrong-name trap before any mass annotation work.
2. **MC — macro-conditional-casts (MC-1 → MC-2 → MC-3 → MC-4).** Independent
   of CP/S; expected near-byte-identical; removes the join-collapse failure
   class before signatures start gaining types.
3. **S — defn-signature (S1 → S2 → S3 → S4).** The tree-wide mechanical
   rewrite (S3) wants a quiet tree: nothing else in flight during that
   window. Lands the final signature syntax before 14.3 edits the same
   lines.
4. **T — type-safety (14.1 → 14.7).** The long haul, now fully unblocked.
   14.1/14.2 have no dependency on MC/S and *may* be pulled forward in
   parallel with items 1–2 if throughput matters, but the serial placement
   keeps refresh windows discrete and is the default.

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
the work that would enlarge the class; independent hardware track runs beside
the backbone rather than in it; one reconverging refresh at a time.
