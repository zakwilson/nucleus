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
| **W2** | `node-type` ↔ `emit` literal-operand lockstep | §1.2 §1.3 §3.1 §3.6 | Medium | [literal-typing.md](literal-typing.md) |
| **W3** | C header interop | §1.4 §1.5 §1.6 | Medium | [cheader.md](cheader.md) |
| **W4** | Diagnostics: locations and silent failures | §5.1 §5.2 §5.3 §3.2 §6.1 §6.2 | Medium | [diagnostics.md](diagnostics.md) |
| **W5** | Ergonomic gaps and the union crash | §1.1 §2.5 §4.3 §4.4 §3.7 §3.9 §3.10 | Medium | [ergonomics.md](ergonomics.md) |
| **W6** | Nullability flow typing (**design only**) | §3.3 | Design | [nullability.md](nullability.md) |

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

W6 is a document and can be written at any point.

## Definition of success for the stage

Beyond the per-item accept criteria: the Doom port should be **re-verifiable
against the improved compiler with its workarounds removed**. Specifically, after
W1 and W2 land, that port should be able to drop the load-bearing import ordering
in `src/g_game.nuc` and its `(as ui32 SOME_DEFCONST)` comparison casts and still
build, with both demo gates bit-exact. That is the real regression test for this
stage, and it lives outside this repo — see [prompt.md](prompt.md) §6.
