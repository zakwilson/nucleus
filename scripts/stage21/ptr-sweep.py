#!/usr/bin/env python3
"""Stage 21 item 7 BP-2 — vacate the typed `ptr` spelling.

Every non-null `ptr:T` chain segment becomes `&T`, so `(ptr T)` can take over
the unchecked kind (design/stage21-cleanup/ptr-is-unchecked.md §5). A `ptr:`
segment followed by more chain is rewritten wherever it starts a segment:

    cc:ptr:Node -> cc:&Node    ?ptr:T -> ?&T    ptr:ptr:T -> &&T    x:ptr:ptr -> x:&ptr

A final bare `ptr` (`p:ptr`) is the untyped pointer and is kept.

Code outside strings and comments is always rewritten. `--in-strings` also
rewrites inside string literals (tests/ embeds programs there) and, there only,
a two-element `(ptr X)` list — the `(ptr A B …)` fn parameter-list shape is
left alone. `(ptr X)` lists in code are sugar-sweep.py R4's job.

Usage: ptr-sweep.py [--dry-run] [--in-strings] FILE ...
"""

import argparse
import re
import sys

SEG = re.compile(r"(?:(?<=[\s(:?!&'`~@\[{])|^)ptr:(?=[A-Za-z_(?!&*])", re.M)


def sweep_code(text):
    return SEG.subn("&", text)


def balanced_end(s, i):
    """End index of the form starting at s[i] (symbol or list), or -1."""
    if s[i] == "(":
        depth = 0
        j = i
        while j < len(s):
            if s[j] == "(":
                depth += 1
            elif s[j] == ")":
                depth -= 1
                if depth == 0:
                    return j + 1
            elif s[j] in '"\\':
                return -1
            j += 1
        return -1
    j = i
    while j < len(s) and s[j] not in ' \t\n()"\\;':
        j += 1
    return j if j > i else -1


def sweep_list2(text):
    out, n, i = [], 0, 0
    while True:
        k = text.find("(ptr ", i)
        if k < 0:
            out.append(text[i:])
            return "".join(out), n
        if k > 0 and text[k - 1] not in " \t\n(:'`&?!":
            out.append(text[i:k + 5])
            i = k + 5
            continue
        e = balanced_end(text, k + 5)
        if e > 0 and e < len(text) and text[e] == ")" and not text[k + 5] == ":":
            out.append(text[i:k] + "&" + text[k + 5:e])
            i = e + 1
            n += 1
        else:
            out.append(text[i:k + 5])
            i = k + 5


def split(src):
    """Yield (kind, text) chunks: code, str, comment, char."""
    i, n, start = 0, len(src), 0
    while i < n:
        c = src[i]
        if c == '"':
            if i > start:
                yield "code", src[start:i]
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            yield "str", src[i:j + 1]
            i = start = j + 1
        elif c == ";":
            if i > start:
                yield "code", src[start:i]
            j = src.find("\n", i)
            j = n if j < 0 else j
            yield "comment", src[i:j]
            i = start = j
        elif c == "\\":
            if i > start:
                yield "code", src[start:i]
            j = i + 2
            while j < n and src[j] not in ' \t\n\r()";[]{}':
                j += 1
            yield "char", src[i:j]
            i = start = j
        else:
            i += 1
    if start < n:
        yield "code", src[start:]


def sweep(src, in_strings):
    out, hits = [], 0
    for kind, t in split(src):
        if kind == "code":
            t, k = sweep_code(t)
            hits += k
        elif kind == "str" and in_strings:
            t, k = sweep_code(t)
            hits += k
            t, k = sweep_list2(t)
            hits += k
        out.append(t)
    return "".join(out), hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--in-strings", action="store_true")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    total = 0
    for f in a.files:
        src = open(f).read()
        new, hits = sweep(src, a.in_strings)
        if hits:
            print("%-44s %d" % (f, hits))
            total += hits
            if not a.dry_run:
                open(f, "w").write(new)
    print("%d sites" % total)


if __name__ == "__main__":
    sys.exit(main())
