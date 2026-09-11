#!/usr/bin/env python3
"""Throwaway analysis behind design/stage20-macros/overview.md §1.2 and §3.1.

Not tooling — not wired into the build. Run from the repo root to re-derive the
numbers when the tree moves:

    python3 design/stage20-macros/census.py runs      # §1.2 sibling-run census
    python3 design/stage20-macros/census.py arity     # §3.1 operator arities

The s-expression reader below is deliberately crude: it needs structure and
leaves, not meaning, so reader macros (`'`, `` ` ``, `~`) stay as atoms and no
desugaring happens.
"""

import glob
import re
import sys
from collections import Counter

TOK = re.compile(r'''
    (?P<ws>\s+)
  | (?P<comment>;[^\n]*)
  | (?P<str>c?"(?:\\.|[^"\\])*")
  | (?P<char>\\\S)
  | (?P<open>[\(\[\{]|\#\{)
  | (?P<close>[\)\]\}])
  | (?P<atom>[^\s\(\)\[\]\{\};"]+)
''', re.X)


class Node:
    __slots__ = ('kind', 'val', 'kids', 'line')

    def __init__(self, kind, val, kids, line):
        self.kind, self.val, self.kids, self.line = kind, val, kids, line


def parse(text):
    pos, line, stack, top = 0, 1, [], []
    while pos < len(text):
        m = TOK.match(text, pos)
        if not m:
            pos += 1
            continue
        pos = m.end()
        line += m.group(0).count('\n')
        if m.lastgroup in ('ws', 'comment'):
            continue
        if m.lastgroup == 'open':
            n = Node('list', m.group(0), [], line)
            (stack[-1].kids if stack else top).append(n)
            stack.append(n)
        elif m.lastgroup == 'close':
            if stack:
                stack.pop()
        else:
            n = Node('atom', m.group(0), [], line)
            (stack[-1].kids if stack else top).append(n)
    return top


def shape(n):
    """Structural skeleton: leaves become holes, list heads are kept."""
    if n.kind == 'atom':
        return '_'
    return '(' + ' '.join(
        k.val if (k.kind == 'atom' and i == 0) else shape(k)
        for i, k in enumerate(n.kids)) + ')'


def size(n):
    return 1 if n.kind == 'atom' else 1 + sum(size(k) for k in n.kids)


def leaf_diffs(a, b):
    """Leaf positions that differ between two same-shape nodes."""
    d = 0

    def walk(x, y):
        nonlocal d
        if x.kind == 'atom' and y.kind == 'atom':
            d += x.val != y.val
            return
        if x.kind != y.kind or len(x.kids) != len(y.kids):
            d += 99
            return
        for p, q in zip(x.kids, y.kids):
            walk(p, q)

    walk(a, b)
    return d


def sources(*globs):
    for pat in globs:
        for path in sorted(glob.glob(pat)):
            yield path, parse(open(path).read())


def runs():
    """§1.2 — runs of >=3 consecutive sibling forms with identical structure."""
    found = []

    def scan(nodes, path):
        i = 0
        while i < len(nodes):
            n = nodes[i]
            if n.kind != 'list':
                i += 1
                continue
            j, run = i + 1, [n]
            while j < len(nodes) and nodes[j].kind == 'list' and shape(nodes[j]) == shape(n):
                run.append(nodes[j])
                j += 1
            if len(run) >= 3 and size(n) >= 4:
                found.append((len(run), size(n),
                              max(leaf_diffs(run[0], r) for r in run[1:]),
                              path, n.line, shape(n)))
            for r in run:
                scan(r.kids, path)
            i = j

    for path, forms in sources('src/*.nuc', 'lib/*.nuc'):
        scan(forms, path)

    print(f"runs (>=3 sibling forms, same shape, >=4 nodes): {len(found)}")
    print(f"forms covered: {sum(r[0] for r in found)}")
    print("by varying leaf count:", dict(sorted(Counter(r[2] for r in found).items())))
    print()
    found.sort(key=lambda r: -(r[0] * r[1]))
    print("  n  sz holes  site")
    for c, sz, v, p, l, s in found[:40]:
        print(f"{c:3d} {sz:3d}  {v:3d}  {p}:{l}  {s[:95]}")


RIGHT = {'+', '*', 'and', 'or'}   # right-fold: (op a (op b c))
LEFT = {'-', '/'}                 # left-fold:  (op (op a b) c)


def arity():
    """§3.1 — n-ary operator call sites, and what a fold rewrite would cost."""
    cnt = Counter()

    def walk(n):
        if n.kind != 'list':
            return
        if n.kids and n.kids[0].kind == 'atom' and n.kids[0].val in RIGHT | LEFT:
            cnt[(n.kids[0].val, len(n.kids) - 1)] += 1
        for k in n.kids:
            walk(k)

    for _, forms in sources('src/*.nuc', 'lib/*.nuc', 'tests/*.nuc', 'examples/*.nuc'):
        for t in forms:
            walk(t)

    def today(op, n):
        # A right-fold operator's 1-arg base case is itself an expansion.
        return (1 if n == 0 else n) if op in RIGHT else (1 if n <= 2 else n - 1)

    def delegate(op, n):
        return 2                       # operator macro + one mfold expansion

    def keep_base(op, n):
        # 0/1/2-ary arms spelled out in the operator macro, N>=3 delegated.
        return 1 if n <= 2 else 2

    t = sum(c * today(*k) for k, c in cnt.items())
    d = sum(c * delegate(*k) for k, c in cnt.items())
    b = sum(c * keep_base(*k) for k, c in cnt.items())
    by_arity = Counter()
    for (_, ar), c in cnt.items():
        by_arity[ar] += c

    print("sites:", sum(cnt.values()))
    print("by op:", dict(Counter({o: sum(c for (oo, _), c in cnt.items() if oo == o)
                                  for o, _ in cnt})))
    print("by arity:", dict(sorted(by_arity.items())))
    print("arity >= 3 sites:", sum(c for (_, ar), c in cnt.items() if ar >= 3))
    print(f"expansions today            : {t}")
    print(f"expansions, full delegation : {d}  ({d - t:+d})")
    print(f"expansions, base cases kept : {b}  ({b - t:+d})")


if __name__ == '__main__':
    {'runs': runs, 'arity': arity}[sys.argv[1] if len(sys.argv) > 1 else 'runs']()
