#!/usr/bin/env python3
"""Stage 21 item 7 BP-4 — move the unchecked kind from `raw` onto `ptr`.

    (raw T) -> (ptr T)    x:raw:T -> x:ptr:T    ?raw:T -> ?ptr:T    x:raw -> x:ptr
    (array raw N) / (as raw x) / (unsafe/cast raw x) -> ptr

Runs after BP-3 taught the compiler that `(ptr T)` is unchecked
(design/stage21-cleanup/ptr-is-unchecked.md §5). It assumes no VARIABLE is named
`raw` — rename those first; every other `raw` in code is then a type. A quoted
`'raw` is data (the compiler's own reserved-name checks) and is kept.

Code is always rewritten; `--in-strings` also rewrites string literals (tests/
embeds programs there) and `--comments` the exact spellings in comments.

Usage: raw-sweep.py [--dry-run] [--in-strings] [--comments] FILE ...
"""

import argparse
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from importlib import import_module

split = import_module("ptr-sweep").split

B = r"(?:(?<=[\s(:?!&`~@\[{])|^)"
RULES = [
    re.compile(B + r"raw(?=:[A-Za-z_(?!&*])", re.M),                 # raw:T segment
    re.compile(r"(?<=\()raw(?= )"),                                   # (raw T)
    re.compile(r"(?<=:)raw(?=[\s)\]]|$)", re.M),                      # x:raw
    re.compile(r"(?<=\(array )raw(?=[\s)])"),                         # (array raw N)
    re.compile(r"(?<=\(as )raw(?=[\s)])"),
    re.compile(r"(?<=\(unsafe/cast )raw(?=[\s)])"),
    re.compile(r"(?<=\(sizeof )raw(?=\))"),
]


def sweep_text(t):
    n = 0
    for r in RULES:
        t, k = r.subn("ptr", t)
        n += k
    return t, n


def sweep(src, in_strings, comments):
    out, hits = [], 0
    for kind, t in split(src):
        if kind == "code" or (kind == "str" and in_strings) or (kind == "comment" and comments):
            t, k = sweep_text(t)
            hits += k
        out.append(t)
    return "".join(out), hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--in-strings", action="store_true")
    ap.add_argument("--comments", action="store_true")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    total = 0
    for f in a.files:
        src = open(f).read()
        new, hits = sweep(src, a.in_strings, a.comments)
        if hits:
            print("%-44s %d" % (f, hits))
            total += hits
            if not a.dry_run:
                open(f, "w").write(new)
    print("%d sites" % total)


if __name__ == "__main__":
    sys.exit(main())
