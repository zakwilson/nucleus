#!/usr/bin/env python3
"""Stage 17's residual-C-string tripwire (design/stage17-native-strings/overview.md §5.5).

The compiler's strings are `StrView`/`String`/`Symbol`. What is left of `CStr`
and libc's `str*` family in `src/` is the FFI boundary itself, and that boundary
is small enough to enumerate: scripts/cstr-allowlist.txt records how many times
each token appears in each file, and this fails on any difference in either
direction. A new libc call cannot be added silently, and a conversion that
removes one cannot leave the list describing a compiler that no longer exists.

Comments and string literals are stripped first. Nearly every remaining mention
of `strcmp`/`fprintf`/`snprintf` in `src/` is prose explaining what replaced it,
and an emitted `@printf(` is IR the compiler *writes*, not a call it makes.

    scripts/check-cstr.py            # verify (exit 1 on drift)
    scripts/check-cstr.py --update   # rewrite the allowlist
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ALLOWLIST = ROOT / "scripts" / "cstr-allowlist.txt"

# `CStr` plus every libc entry point that exists to do to a `char*` what
# StrView/String/Symbol do natively, plus the stdio calls `emit` replaced.
TOKENS = [
    "CStr",
    "strlen", "strnlen", "strcmp", "strncmp", "strcasecmp", "strncasecmp",
    "strchr", "strrchr", "strstr", "strdup", "strndup", "strcpy", "strncpy",
    "strcat", "strncat", "strtol", "strtoul", "strtoull", "strtod",
    "atoi", "atol", "sprintf", "snprintf", "sscanf",
    "fprintf", "fputs", "fputc", "open_memstream",
]

# `arena-strndup` is the arena's copy-n-bytes primitive, not libc's; matching it
# as a bare `strndup` would report the one place a StrView is parked in the
# arena as a C-string call.
PREFIXED = re.compile(r"[A-Za-z0-9_?!-]$")


def strip_code(text: str) -> str:
    """Drop `;` comments, `"…"` literals and `\\c` char literals, keeping line count."""
    out = []
    for line in text.split("\n"):
        buf = []
        i, n, in_str = 0, len(line), False
        while i < n:
            c = line[i]
            if in_str:
                if c == "\\":
                    i += 2
                    continue
                if c == '"':
                    in_str = False
                i += 1
                continue
            if c == '"':
                in_str = True
                i += 1
                continue
            if c == ";":
                break
            if c == "\\" and i + 1 < n:      # a `\a` char literal
                i += 2
                continue
            buf.append(c)
            i += 1
        out.append("".join(buf))
    return "\n".join(out)


def counts():
    tally = {}
    for path in sorted((ROOT / "src").glob("*.nuc")):
        code = strip_code(path.read_text())
        for tok in TOKENS:
            hits = 0
            for m in re.finditer(re.escape(tok), code):
                # A token is a call/type only when it starts a name: `arena-strndup`
                # and `sc-strcmp-seam` are other identifiers that contain one.
                if m.start() and PREFIXED.search(code[m.start() - 1]):
                    continue
                hits += 1
            if hits:
                tally[(path.name, tok)] = hits
    return tally


def render(tally):
    lines = [
        "# Stage 17 C8 — the enumerated C-string boundary in src/.",
        "# `<file> <token> <count>`, verified by scripts/check-cstr.py (the",
        "# `cstr-residue` unit of `make test`). Regenerate with --update, and only",
        "# ever alongside the change that moved a count.",
        "",
    ]
    for (f, t), n in sorted(tally.items()):
        lines.append(f"{f} {t} {n}")
    return "\n".join(lines) + "\n"


def load():
    if not ALLOWLIST.exists():
        return {}
    out = {}
    for line in ALLOWLIST.read_text().split("\n"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        f, t, n = line.split()
        out[(f, t)] = int(n)
    return out


def main():
    tally = counts()
    if "--update" in sys.argv:
        ALLOWLIST.write_text(render(tally))
        print(f"cstr-allowlist.txt: {len(tally)} entries, {sum(tally.values())} sites")
        return 0

    want = load()
    bad = []
    for key in sorted(set(want) | set(tally)):
        have, expect = tally.get(key, 0), want.get(key, 0)
        if have != expect:
            bad.append(f"  {key[0]} {key[1]}: {expect} allowed, {have} found")
    if bad:
        print("cstr-residue: src/ C-string boundary does not match the allowlist:")
        print("\n".join(bad))
        print("  (a NEW site is a bug unless it is a real FFI seam; a REMOVED one")
        print("   means running `scripts/check-cstr.py --update` with the change)")
        return 1
    print(f"cstr-residue: {sum(tally.values())} allowed C-string sites in src/, all accounted for")
    return 0


if __name__ == "__main__":
    sys.exit(main())
