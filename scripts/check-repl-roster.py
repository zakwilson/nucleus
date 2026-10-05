#!/usr/bin/env python3
"""The REPL session roster is spelled once (design/stage20-macros/overview.md §2.6).

`repl-snapshot` and `repl-restore` used to spell all 54 globals four times over.
Stage 20 M5 collapsed that to two tables held by `over-repl-globals` and
`over-repl-registries`, which is half the fix: a field added to `defstruct
ReplState` with no row in either table still compiles, and still leaks that
global's value between prompts with nothing failing. This is the other half.

Exact, and in both directions. Every `ReplState` field must appear as exactly
one table row, in the struct's own order — so the tables stay diffable against
the struct top to bottom — and no row may name a field the struct dropped.
`globals-len` and `n-link-claims` are exempt: the first is a field of the
`Scope` `g-globals` points at, the second needs its index unwound, so both are
saved and restored beside the tables.

    scripts/check-repl-roster.py     # verify (exit 1 on drift)
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "src" / "repl.nuc"

TABLES = ["over-repl-globals", "over-repl-registries"]

# Saved and restored by hand: `(st 'globals-len)` pairs with a Scope field, not
# with a `g-` global, so no two-column row can express it.
# `n-link-claims` truncates a list whose HashMap index must be unwound with it.
EXEMPT = {"globals-len", "n-link-claims"}

TOK = re.compile(r'''
    (?P<skip>\s+|;[^\n]*|c?"(?:\\.|[^"\\])*"|\\\S)
  | (?P<open>\()
  | (?P<close>\))
  | (?P<atom>[^\s();"]+)
''', re.X)


def parse(text):
    """Crude reader: structure and leaves, no meaning. Reader macros stay atoms."""
    stack, top = [], []
    for m in TOK.finditer(text):
        if m.lastgroup == "skip":
            continue
        here = stack[-1] if stack else top
        if m.lastgroup == "open":
            node = []
            here.append(node)
            stack.append(node)
        elif m.lastgroup == "close":
            if stack:
                stack.pop()
        else:
            here.append(m.group(0))
    return top


def find(node, pred):
    """First subform satisfying pred, depth first."""
    if pred(node):
        return node
    if isinstance(node, list):
        for kid in node:
            hit = find(kid, pred)
            if hit is not None:
                return hit
    return None


def struct_fields(forms):
    d = find(forms, lambda n: isinstance(n, list) and n[:2] == ["defstruct", "ReplState"])
    if d is None:
        die("no `(defstruct ReplState …)` in src/repl.nuc")
    # `name:Type`, or `(name (raw …))` for a type the colon form cannot spell.
    return [(f[0] if isinstance(f, list) else f.split(":")[0]) for f in d[2:]]


def table_rows(forms, name):
    """The `(field global)` rows of the macmap `name` expands to."""
    b = find(forms, lambda n: isinstance(n, list) and len(n) > 2 and n[0] == name
             and n[1] == ["spec"])
    if b is None:
        die(f"no `({name} (spec) …)` macrolet binding in src/repl.nuc")
    m = find(b[2:], lambda n: isinstance(n, list) and n[:1] == ["macmap"])
    if m is None or len(m) != 3:
        die(f"{name} no longer expands to a two-argument `macmap`")
    rows = m[2]
    for r in rows:
        if not (isinstance(r, list) and len(r) == 2
                and all(isinstance(c, str) for c in r)):
            die(f"{name}: `{unparse(r)}` is not a (field global) row")
    return [(r[0], r[1]) for r in rows]


def unparse(n):
    return n if isinstance(n, str) else "(" + " ".join(unparse(k) for k in n) + ")"


def die(msg):
    print(f"check-repl-roster: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    forms = parse(SOURCE.read_text())
    fields = struct_fields(forms)
    rows = [r for t in TABLES for r in table_rows(forms, t)]

    seen = [f for f, _ in rows]
    dupes = {f for f in seen if seen.count(f) > 1}
    if dupes:
        die("named by more than one row: " + ", ".join(sorted(dupes)))

    unknown = [f for f in seen if f not in fields]
    if unknown:
        die("rows naming no ReplState field: " + ", ".join(unknown))

    missing = [f for f in fields if f not in seen and f not in EXEMPT]
    if missing:
        die("ReplState fields no table row covers, so a prompt leaks them: "
            + ", ".join(missing)
            + "\n  add a row to over-repl-globals or over-repl-registries in src/repl.nuc")

    stale = sorted(EXEMPT - set(fields))
    if stale:
        die("exempt in this script but gone from ReplState: " + ", ".join(stale))

    want = [f for f in fields if f not in EXEMPT]
    if seen != want:
        die("the tables are no longer in ReplState's field order, so they cannot"
            " be diffed against it:\n  struct: " + " ".join(want)
            + "\n  tables: " + " ".join(seen))

    print(f"check-repl-roster: {len(rows)} rows cover every ReplState field but "
          + ", ".join(sorted(EXEMPT)))


if __name__ == "__main__":
    main()
