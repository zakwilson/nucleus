#!/usr/bin/env python3
"""Count nested backticks: a ` whose enclosing form is already inside a `.

Tracks paren depth and the depth at which each open quasiquote started, skipping
line comments, string literals and char literals.
"""
import sys, glob
hits = 0
files = 0
for path in sorted(sum((glob.glob(p) for p in sys.argv[1:]), [])):
    t = open(path, errors='replace').read()
    i, depth, qq = 0, 0, []   # qq: paren depths at which a ` is pending/open
    n = len(t)
    seen = False
    while i < n:
        c = t[i]
        if c == ';':
            while i < n and t[i] != '\n': i += 1
        elif c == '"':
            i += 1
            while i < n and t[i] != '"':
                if t[i] == '\\': i += 1
                i += 1
            i += 1
        elif c == '#' and i + 1 < n and t[i+1] == '\\':
            i += 3
        elif c == '`':
            if qq:
                hits += 1
                if not seen:
                    seen = True
                    print(f"{path}:{t.count(chr(10), 0, i)+1}: nested backtick")
            qq.append(depth)
            i += 1
        elif c == '(':
            depth += 1; i += 1
        elif c == ')':
            depth -= 1
            while qq and qq[-1] >= depth: qq.pop()
            i += 1
        else:
            i += 1
    files += 1
print(f"scanned {files} files, {hits} nested backticks")
