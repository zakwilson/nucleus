#!/usr/bin/env python3
"""Stage 17 — rewrite the compiler's formatted-output calls.

Three modes, one scanner, because each phase needs the same paren-aware split
and the same format-string decomposition:

    (default)   C1: (fmt-2s "macro '%s': %s" name why)
                     ->  (fstr "macro '" name "': " why)
    --stderr    C1: (fprintf stderr "bad %s\\n" n)  ->  (eprint "bad " n "\\n")
    --writes    C2: (fprintf g-out "  %%v%d = %s\\n" n ty)
                     ->  (emit g-out "  %v" n " = " ty "\\n")
                    plus (printf …), (fputs X S) and (fputc C S).

Paren-aware, not line-oriented: arguments contain nested calls, nested string
literals and escaped quotes.  See design/stage17-native-strings/
migration-tooling.md §2.

It REFUSES rather than guesses.  A site whose format string is not a literal,
whose specifiers the table below does not model, or whose conversion count does
not match its argument count is left untouched and reported.  The refusal list
is a deliverable: it says which shapes the compiler actually uses that a
straightforward rewrite cannot express.

Usage:
    rewrite-fmt.py --dry-run [FILE ...]     # histogram + refusals, no writes
    rewrite-fmt.py FILE ...                 # rewrite in place

Idempotent in every mode: it only matches heads the rewrite removes.  Not
transitive in one pass, though — a call nested in another's argument list is
consumed as source text, so run it to a fixed point.
"""

import argparse
import re
import sys
from collections import Counter

HELPERS = ("fmt-i32-i32", "fmt-i32", "fmt-i64", "fmt-sd", "fmt-s-2i",
           "fmt-2s-i", "fmt-2s", "fmt-3s", "fmt-s")

HEAD_RE = re.compile(r"\((" + "|".join(HELPERS) + r")\s")

# C1's second half: `(fprintf stderr FMT args…)` -> `(eprint pieces…)`. Only
# stderr, and only `eprint` (never `eprintln`): stderr is unbuffered on both
# sides, so ordering against a block-buffered stdout is unchanged, and keeping
# the literal "\n" as a piece means one less transformation to get wrong.
STDERR_RE = re.compile(r"\(fprintf\s+stderr\s")

# C2: the emission surface. `fwrite` is not here — its four sites are all in
# src/repl.nuc and already pass a length, so they are hand-converted with C5.
WRITES_RE = re.compile(r"\((fprintf|printf|fputs|fputc)\s")

# `fputc` takes a byte, `emit` takes text. Spelling the common ones as literal
# pieces keeps the converted site readable; anything else goes through `Char`.
FPUTC_LIT = {
    "10": r'"\n"', "32": '" "', "34": r'"\""', "40": '"("', "41": '")"',
    "48": '"0"', "58": '":"', "92": r'"\\"', "110": '"n"', "114": '"r"',
    "116": '"t"',
}

# specifier -> how to spell the argument as a piece.
DIRECT = {"%s", "%d", "%ld", "%c"}
SPEC_RE = re.compile(r"%(?:%|016lX|04lX|016lx|02X|ld|[sdc])")


def render_arg(spec, arg):
    if spec == "%c":
        return "(as Char (as ui32 %s))" % arg
    if spec == "%016lX":
        return "(hexu %s 16)" % arg
    if spec == "%04lX":
        return "(hexu %s 4)" % arg
    if spec == "%02X":
        return "(hexu %s 2)" % arg
    if spec == "%016lx":
        return "(hex %s 16)" % arg
    return arg


def skip_atom(s, i):
    """Index just past the token starting at i (which is not whitespace)."""
    n = len(s)
    if s[i] == '"':
        i += 1
        while i < n and s[i] != '"':
            i += 2 if s[i] == "\\" else 1
        return i + 1
    if s[i] == "(":
        d = 0
        while i < n:
            c = s[i]
            if c == ";":
                while i < n and s[i] != "\n":
                    i += 1
                continue
            if c == '"':
                i += 1
                while i < n and s[i] != '"':
                    i += 2 if s[i] == "\\" else 1
                i += 1
                continue
            if c == "\\":            # a char literal such as \( or \)
                i += 2
                continue
            if c == "(":
                d += 1
            elif c == ")":
                d -= 1
                if d == 0:
                    return i + 1
            i += 1
        return -1
    if s[i] == "\\":                  # char literal: \a, \newline, \u{41}
        i += 1
        if i < n and s[i] == "u" and i + 1 < n and s[i + 1] == "{":
            while i < n and s[i] != "}":
                i += 1
            return i + 1
        while i < n and (s[i].isalnum() or s[i] in "_-"):
            i += 1
        return max(i, 0)
    while i < n and s[i] not in ' \t\n()";':
        i += 1
    return i


def split_call(s, start):
    """(head, [arg-source, ...], end) for the call whose '(' is at `start`."""
    end = skip_atom(s, start)
    if end < 0:
        return None
    i = start + 1
    j = skip_atom(s, i)
    head = s[i:j]
    args = []
    i = j
    while i < end - 1:
        if s[i] in " \t\n":
            i += 1
            continue
        if s[i] == ";":
            while i < end and s[i] != "\n":
                i += 1
            continue
        j = skip_atom(s, i)
        if j <= i:
            return None
        args.append(s[i:j])
        i = j
    return head, args, end


def build(fmt_literal, args):
    """`fstr` pieces, or a string explaining the refusal."""
    body = fmt_literal[1:-1]
    pieces = []          # list of ('lit', text) / ('arg', source)
    lit = []
    ai = 0
    i = 0
    n = len(body)
    while i < n:
        if body[i] == "\\":
            lit.append(body[i:i + 2])
            i += 2
            continue
        if body[i] != "%":
            lit.append(body[i])
            i += 1
            continue
        m = SPEC_RE.match(body, i)
        if not m:
            j = body.find(" ", i)
            return "unmodelled specifier %r" % body[i:(j if j > 0 else i + 6)]
        spec = m.group(0)
        i = m.end()
        if spec == "%%":
            lit.append("%")
            continue
        if ai >= len(args):
            return "more conversions than arguments"
        if lit:
            pieces.append(("lit", "".join(lit)))
            lit = []
        pieces.append(("arg", render_arg(spec, args[ai])))
        ai += 1
    if lit:
        pieces.append(("lit", "".join(lit)))
    if ai != len(args):
        return "more arguments (%d) than conversions (%d)" % (len(args), ai)
    if not pieces:
        return "empty format string"
    return ['"%s"' % t if k == "lit" else t for k, t in pieces]


def writes_pieces(head, args, stats):
    """`emit` operands (sink first), or a string explaining the refusal."""
    if head == "fputs":
        if len(args) != 2:
            return "fputs arity"
        return [args[1], args[0]]
    if head == "fputc":
        if len(args) != 2:
            return "fputc arity"
        c = FPUTC_LIT.get(args[0]) or "(as Char (as ui32 %s))" % args[0]
        return [args[1], c]
    fi = 1 if head == "fprintf" else 0
    # `printf` writes the C header and .nuch emissions; the sink is the same
    # FILE*, so buffering and therefore interleaving are unchanged.
    sink = args[0] if head == "fprintf" else "(as ptr stdout)"
    if len(args) <= fi or not args[fi].startswith('"'):
        return "non-literal format"
    for sp in SPEC_RE.finditer(args[fi]):
        stats[sp.group(0)] += 1
    res = build(args[fi], args[fi + 1:])
    if isinstance(res, str):
        return res
    return [sink] + res


def rewrite(src, path, stats, refusals, dry_run, stderr_mode=False,
            writes_mode=False, line_range=None):
    out = []
    i = 0
    changed = 0
    lo, hi = line_range or (0, 1 << 30)
    head_re = WRITES_RE if writes_mode else STDERR_RE if stderr_mode else HEAD_RE
    call = "emit" if writes_mode else "eprint" if stderr_mode else "fstr"
    while True:
        m = head_re.search(src, i)
        if not m:
            out.append(src[i:])
            break
        start = m.start()
        parts = split_call(src, start)
        if parts is None:
            refusals.append((path, line_of(src, start), "unbalanced call"))
            out.append(src[i:start + 1])
            i = start + 1
            continue
        head, args, end = parts
        if not lo <= line_of(src, start) <= hi:
            out.append(src[i:end])
            i = end
            continue
        if stderr_mode:
            args = args[1:]          # drop the `stderr` operand
        out.append(src[i:start])
        i = end
        if writes_mode:
            res = writes_pieces(head, args, stats)
        elif not args or not args[0].startswith('"'):
            res = "non-literal format"
        else:
            for sp in SPEC_RE.finditer(args[0]):
                stats[sp.group(0)] += 1
            res = build(args[0], args[1:])
        if isinstance(res, str):
            refusals.append((path, line_of(src, start), res))
            out.append(src[start:end])
            continue
        col = start - (src.rfind("\n", 0, start) + 1)
        one = "(%s " % call + " ".join(res) + ")"
        if col + len(one) <= 96 or len(res) == 1:
            out.append(one)
        else:
            # Greedy fill at the same column the call opened at, so a wrapped
            # site still reads as one argument list rather than a column.
            pad = " " * (col + len(call) + 2)
            lines, cur = [], res[0]
            for piece in res[1:]:
                if len(pad) + len(cur) + 1 + len(piece) <= 96:
                    cur += " " + piece
                else:
                    lines.append(cur)
                    cur = piece
            lines.append(cur)
            out.append("(%s " % call + ("\n" + pad).join(lines) + ")")
        changed += 1
    return ("".join(out) if not dry_run else src), changed


def line_of(s, i):
    return s.count("\n", 0, i) + 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--stderr", action="store_true",
                    help="rewrite (fprintf stderr …) into (eprint …) instead")
    ap.add_argument("--writes", action="store_true",
                    help="C2: rewrite fprintf/printf/fputs/fputc into (emit …)")
    ap.add_argument("--range", metavar="A:B",
                    help="only sites whose head is on lines A..B (inclusive), "
                         "so a 400-site file converts as reviewable regions")
    a = ap.parse_args()
    rng = tuple(int(x) for x in a.range.split(":")) if a.range else None

    stats = Counter()
    refusals = []
    total = 0
    for path in a.files:
        src = open(path).read()
        new, changed = rewrite(src, path, stats, refusals, a.dry_run, a.stderr,
                               a.writes, rng)
        total += changed
        if not a.dry_run and new != src:
            open(path, "w").write(new)
        if changed:
            print("%-24s %4d rewritten" % (path, changed))

    print("\n%d sites rewritten" % total)
    if stats:
        print("specifiers:", ", ".join("%s=%d" % kv for kv in stats.most_common()))
    if refusals:
        print("\n%d refused:" % len(refusals))
        for path, ln, why in refusals:
            print("  %s:%d  %s" % (path, ln, why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
