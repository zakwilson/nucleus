#!/usr/bin/env python3
"""Generate docs/stdlib.md's "no import needed" availability tables by
PROBING build/nucleusc — never by hand-curation.

Stage 15 W4e (design/stage15-stress-test/diagnostics.md §W4e). Ground truth:
docs/stdlib.md used to open with "these are registered at compiler startup,
so no (import-use ...) is needed" and hand-list functions under stdio/stdlib/
string/ctype/unistd. Both halves of that claim are wrong: `close`/`dup2`/`dup`
(unistd) and `isspace`/`isdigit` (ctype) are NOT pre-declared (`unknown:
<name>`), while `getenv`/`remove`/`fopen`/`fwrite`/`fclose`/`snprintf`/
`strncmp`/`strstr`/`memcmp`/`strcasecmp` all resolve silently and were
undocumented.

The actual mechanism (verified by reading, not assumed): nothing is
"registered at compiler startup". `lib/prelude.nuc` (auto-imported into every
program unless `(exclude-prelude)`) directly `(import-use "string.h")`s, and
ALSO `(import-use node)` -> `lib/node.nuc` -> `(import-use arena)` ->
`lib/arena.nuc`, which itself `(import-use "stdio.h")` + `(import-use
"stdlib.h")` + `(import-use "string.h")`. So the "no import needed" set is
exactly whatever a C header import of stdio.h + stdlib.h + string.h resolves
to via `clang -E -x c -include <hdr> /dev/null` on the BUILD HOST's C library
(see context/build.md's "Import system" section) — host- and libc-dependent
by construction (glibc vs musl differ), not a fixed list. `ctype.h` and
`unistd.h` are NOT in this transitive chain at all, which is why every name
claimed under those two sections was simply false.

This script:
  1. Preprocesses stdio.h/stdlib.h/string.h with the same `clang -E` invocation
     the compiler's own C-header importer uses, and extracts every top-level
     `extern`-or-not function declaration (glibc's musl-incompatible `extern`
     assumption is exactly what context/build.md's musl note warns about —
     parsing here does not require `extern`, matching the compiler's own
     parser).
  2. Also collects every name currently claimed in docs/stdlib.md's tables (so
     a name that stops being available, or was NEVER available like `close`,
     is caught and reported instead of silently vanishing from the candidate
     set).
  3. Compiles a minimal one-line probe `(defn main ():i32 (<name>) (return
     0))` for the union of both sets with the real `build/nucleusc` and
     classifies AVAILABLE vs NOT by whether stderr contains `unknown: <name>`
     — a different error (arity, type) still means available (verified: a
     zero-arg call to a 2-arg libc function like `strcasecmp` compiles clean,
     i.e. header-imported externs are not arity-checked; do not read "it
     compiled" as "the rendered signature below is exact" — the signature
     columns are a best-effort simplified reading of the header declaration,
     scoped no further than that).
  4. Regenerates the tables between the BEGIN/END GENERATED markers in
     docs/stdlib.md, grouped by header, sorted alphabetically within each
     group. Hand-written prose (the framing paragraph above the markers, and
     everything from the `---` StrView section onward) is left untouched.

Usage:
  scripts/gen-stdlib-table.py            regenerate docs/stdlib.md in place
  scripts/gen-stdlib-table.py --check    compare a fresh probe against the
                                         committed doc; see `check_against_committed`
                                         for the exact (deliberately
                                         host-tolerant) pass/fail rule.
  scripts/gen-stdlib-table.py --print    print the generated block to stdout
                                         without touching any file.
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DOC_PATH = REPO_ROOT / "docs" / "stdlib.md"
BEGIN_MARKER = "<!-- BEGIN GENERATED: availability (scripts/gen-stdlib-table.py) -->"
END_MARKER = "<!-- END GENERATED -->"

# The three headers actually transitively reachable with zero explicit
# (import-use ...) in a user program — see the module docstring. Order here
# is the order sections are emitted in the doc.
HEADERS = [("stdio.h", "stdio"), ("stdlib.h", "stdlib"), ("string.h", "string")]

NUCLEUSC = Path(os.environ.get("NUCLEUSC", REPO_ROOT / "build" / "nucleusc"))

# --- C declaration -> simplified Nucleus-doc type spelling ------------------
# Matches the granularity the hand-written table already used (e.g. `isspace`
# was documented as `(i32) -> i32`, not `(int) -> int`): every pointer kind
# collapses to `ptr`, every <=64-bit integer kind to i32/i64 by width, float/
# double to f32/f64. This is deliberately coarse — the same simplification the
# existing table already made — not a claim about exact C type identity.
_SCALAR_TYPES = {
    "int": "i32", "signed int": "i32", "signed": "i32", "unsigned int": "i32",
    "unsigned": "i32", "short": "i32", "short int": "i32",
    "unsigned short": "i32", "unsigned short int": "i32", "char": "i32",
    "signed char": "i32", "unsigned char": "i32", "_Bool": "i32",
    "long": "i64", "long int": "i64", "unsigned long": "i64",
    "unsigned long int": "i64", "long long": "i64", "long long int": "i64",
    "unsigned long long": "i64", "unsigned long long int": "i64",
    "size_t": "i64", "ssize_t": "i64", "__ssize_t": "i64",
    "off_t": "i64", "__off_t": "i64", "off64_t": "i64",
    "time_t": "i64", "clock_t": "i64",
    "int8_t": "i32", "uint8_t": "i32", "int16_t": "i32", "uint16_t": "i32",
    "int32_t": "i32", "uint32_t": "i32", "__uint32_t": "i32",
    "int64_t": "i64", "uint64_t": "i64",
    "intptr_t": "i64", "uintptr_t": "i64",
    "wchar_t": "i32",
    "float": "f32",
    "double": "f64",
}
# Typedefs that are semantically pointers even though no literal '*' appears
# at the parameter site (glibc hides the pointer inside the typedef).
_PTR_TYPEDEFS = {"locale_t", "__compar_fn_t", "comparison_fn_t"}
# Types this script declines to render a signature for at all (struct-by-value
# return/params, va_list, long double) -- the candidate is dropped from the
# generated doc rather than guessing (see module docstring point 3).
_UNSUPPORTED_TYPES = {
    "div_t", "ldiv_t", "lldiv_t", "cookie_io_functions_t",
    "__gnuc_va_list", "va_list", "long double", "FILE",
}
_TYPE_KEYWORDS = {"int", "char", "long", "short", "double", "float", "void",
                  "unsigned", "signed", "_Bool"}


class Unsupported(Exception):
    """Raised when a declaration's return/param type has no confident
    simplified spelling; the candidate is dropped, not guessed at."""


def _clean_leaf(text):
    text = re.sub(r"\s+", " ", text).strip()
    for kw in ("__extension__", "const", "restrict", "__restrict"):
        text = re.sub(rf"\b{kw}\b", "", text)
    return re.sub(r"\s+", " ", text).strip()


def simplify_param(argtext):
    a = re.sub(r"\s+", " ", argtext).strip()
    if a == "void":
        return None  # the lone `void` parameter means "no parameters"
    if "..." in a:
        return "..."
    if "*" in a or "[" in a:
        return "ptr"
    cleaned = _clean_leaf(a)
    toks = cleaned.split()
    if not toks:
        raise Unsupported(argtext)
    if len(toks) >= 2 and toks[-1] not in _TYPE_KEYWORDS:
        typ = " ".join(toks[:-1])  # strip the trailing parameter name
    else:
        typ = " ".join(toks)
    if typ in _SCALAR_TYPES:
        return _SCALAR_TYPES[typ]
    if typ in _PTR_TYPEDEFS:
        return "ptr"
    if typ in _UNSUPPORTED_TYPES:
        raise Unsupported(typ)
    raise Unsupported(typ)


def simplify_return(rettype):
    r = _clean_leaf(rettype.replace("extern", ""))
    if "*" in r:
        return "ptr"
    if r == "void":
        return "void"
    if r in _SCALAR_TYPES:
        return _SCALAR_TYPES[r]
    if r in _PTR_TYPEDEFS:
        return "ptr"
    raise Unsupported(r)


# --- clang -E based header harvesting ---------------------------------------

def preprocess_header(hdr):
    out = subprocess.run(
        ["clang", "-E", "-x", "c", "-include", hdr, "/dev/null"],
        capture_output=True, text=True,
    )
    return out.stdout


def _strip_directives(text):
    return "\n".join(l for l in text.splitlines() if not l.startswith("#"))


def _split_statements(text):
    """Split preprocessed C text on top-level ';' (paren/brace/bracket depth
    0), so a declaration wrapped across physical lines becomes one chunk."""
    stmts, buf, depth = [], [], 0
    for c in text:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == ";" and depth == 0:
            stmts.append("".join(buf))
            buf = []
        else:
            buf.append(c)
    if "".join(buf).strip():
        stmts.append("".join(buf))
    return stmts


def _split_args(argtext):
    args, buf, depth = [], [], 0
    for c in argtext:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            args.append("".join(buf))
            buf = []
        else:
            buf.append(c)
    if "".join(buf).strip():
        args.append("".join(buf))
    return [a.strip() for a in args if a.strip()]


def _find_func_decl(stmt):
    """If `stmt` (one top-level ';'-terminated chunk) is a function
    declaration, return (rettype_text, name, argtext); else None. Handles the
    `name (args) __attribute__((...)) __asm__(...)` trailer shape by taking
    the FIRST identifier-immediately-followed-by-'(' in the statement (the
    declarator), since any attribute/asm trailer comes after it."""
    s = stmt.strip()
    if not s:
        return None
    for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", s):
        name = m.group(1)
        if name in ("__attribute__", "__asm__", "__asm", "__extension__"):
            continue
        start = m.end() - 1
        depth, end = 0, None
        for j in range(start, len(s)):
            if s[j] == "(":
                depth += 1
            elif s[j] == ")":
                depth -= 1
                if depth == 0:
                    end = j
                    break
        if end is None:
            return None
        rettype = s[: m.start()].strip()
        if not rettype or "typedef" in rettype or "{" in rettype or "}" in rettype:
            continue
        return (rettype, name, s[start + 1 : end])
    return None


def harvest_header(hdr):
    """Returns {name: (params_simplified_list_or_None, ret_simplified)} for
    every function declared (directly or transitively) when clang preprocesses
    `hdr` — skipping reserved (leading-'_') names and any declaration whose
    type this script can't confidently simplify (see Unsupported)."""
    text = _strip_directives(preprocess_header(hdr))
    result = {}
    for stmt in _split_statements(text):
        decl = _find_func_decl(stmt)
        if not decl:
            continue
        rettype, name, argtext = decl
        if name.startswith("_") or name in result:
            continue
        try:
            ret = simplify_return(rettype)
            raw_args = _split_args(argtext)
            params = []
            for a in raw_args:
                p = simplify_param(a)
                if p is not None:
                    params.append(p)
        except Unsupported:
            continue
        result[name] = (params, ret)
    return result


# --- probing build/nucleusc --------------------------------------------------

def probe_available(name, tmpdir):
    src = Path(tmpdir) / f"probe_{name}.nuc"
    src.write_text(f"(defn main ():i32 ({name}) (return 0))\n")
    proc = subprocess.run(
        [str(NUCLEUSC), "-I", str(REPO_ROOT / "lib"), "--emit-llvm", str(src)],
        capture_output=True, text=True, cwd=REPO_ROOT,
    )
    src.unlink(missing_ok=True)
    return f"unknown: {name}" not in proc.stderr


def probe_all(names):
    """Returns {name: bool available}. Compiler invocations are independent
    (one throwaway file each) so they run concurrently, matching
    tests/run-tests.sh's own bounded-parallel-job convention."""
    results = {}
    with tempfile.TemporaryDirectory() as tmpdir:
        workers = int(os.environ.get("NUCLEUS_TEST_JOBS", os.cpu_count() or 4))
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
            futs = {ex.submit(probe_available, n, tmpdir): n for n in names}
            for fut in concurrent.futures.as_completed(futs):
                results[futs[fut]] = fut.result()
    return results


# --- doc parsing / generation -----------------------------------------------

def extract_current_names(doc_text):
    """Names currently claimed available anywhere in the doc's availability
    tables — from the marked generated region if present, else (first-ever
    run) everything above the first '---' rule, which is where the
    hand-curated tables lived before this script existed."""
    if BEGIN_MARKER in doc_text and END_MARKER in doc_text:
        region = doc_text.split(BEGIN_MARKER, 1)[1].split(END_MARKER, 1)[0]
    else:
        region = doc_text.split("\n---\n", 1)[0]
    return set(re.findall(r"^\|\s*`([A-Za-z_][A-Za-z0-9_.]*)`\s*\|", region, re.M))


def format_sig(params, ret):
    inner = ", ".join(params) if params else ""
    return f"({inner}) -> {ret}"


def build_generated_block(harvested, available_names):
    lines = [BEGIN_MARKER, ""]
    by_section = {section: [] for _, section in HEADERS}
    placed = set()
    for hdr, section in HEADERS:
        for name, (params, ret) in harvested.get(hdr, {}).items():
            if name in available_names and name not in placed:
                by_section[section].append((name, format_sig(params, ret), f"<{hdr}>"))
                placed.add(name)
    for hdr, section in HEADERS:
        rows = sorted(by_section[section], key=lambda r: r[0])
        if not rows:
            continue
        lines.append(f"## {section}")
        lines.append("")
        lines.append("| Function | Signature | C Header |")
        lines.append("|----------|-----------|----------|")
        for name, sig, hdrcol in rows:
            lines.append(f"| `{name}` | `{sig}` | `{hdrcol}` |")
        lines.append("")
    while lines and lines[-1] == "":
        lines.pop()
    lines.append("")
    lines.append(END_MARKER)
    return "\n".join(lines), placed


def harvest_all():
    return {hdr: harvest_header(hdr) for hdr, _ in HEADERS}


def compute(doc_text):
    """Runs the full probe + harvest and returns (block_text, available_set,
    claimed_before_set, harvested)."""
    harvested = harvest_all()
    claimed_before = extract_current_names(doc_text)
    header_candidates = set()
    for hdr, _ in HEADERS:
        header_candidates |= set(harvested[hdr].keys())
    candidates = header_candidates | claimed_before
    probed = probe_all(candidates)
    available_names = {n for n, ok in probed.items() if ok}
    block, placed = build_generated_block(harvested, available_names)
    # Names available but with no confidently-derivable signature (e.g. a
    # doc-claimed name that isn't one of the 3 enumerated headers at all) are
    # available-but-unplaced; surfaced to stderr, never silently dropped.
    unplaced_available = available_names & candidates - placed
    return block, available_names, claimed_before, unplaced_available


def regenerate(doc_text):
    block, available, claimed_before, unplaced = compute(doc_text)
    if BEGIN_MARKER in doc_text and END_MARKER in doc_text:
        pre = doc_text.split(BEGIN_MARKER, 1)[0]
        post = doc_text.split(END_MARKER, 1)[1]
    else:
        # First-ever run: insert the markers right after the framing
        # paragraph(s), replacing the legacy hand-curated tables entirely
        # (everything from the first '## ' section header up to the first
        # '---' rule).
        head, _, rest = doc_text.partition("\n---\n")
        pre = re.split(r"\n##\s", head, maxsplit=1)[0].rstrip("\n") + "\n\n"
        post = "\n---\n" + rest
    new_text = pre + block + "\n" + post
    added = available - claimed_before
    removed = claimed_before - available
    return new_text, added, removed, unplaced


def check_against_committed():
    """Host-dependence design decision (see design/stage15-stress-test/
    diagnostics.md, W4e as built): availability is host/libc-dependent by
    construction (musl vs glibc, per context/build.md), so requiring the fresh
    probe to match the committed doc byte-for-byte would fail spuriously on a
    host with a leaner libc. Instead: fail ONLY if a name the COMMITTED doc
    currently claims is available no longer probes as available on THIS host
    — that is the actual finding (a false claim), and it is host-independent:
    a name either regressed or it was always false. A host that finds
    ADDITIONAL available names beyond the committed doc, or is simply missing
    some the committed doc doesn't (yet) list, is not a failure — that is
    exactly the kind of divergence a stricter exact-match check would get
    spuriously wrong on e.g. an Alpine/musl runner.
    """
    if not NUCLEUSC.exists():
        print(f"ERROR: {NUCLEUSC} not found -- run `make` first", file=sys.stderr)
        return 2
    doc_text = DOC_PATH.read_text()
    if BEGIN_MARKER not in doc_text:
        print("FAIL: docs/stdlib.md has no generated-availability markers -- "
              "run scripts/gen-stdlib-table.py to create them", file=sys.stderr)
        return 1
    committed_block = doc_text[doc_text.index(BEGIN_MARKER):
                                doc_text.index(END_MARKER) + len(END_MARKER)]
    committed_names = extract_current_names(doc_text)
    block, available, _claimed_before, unplaced = compute(doc_text)
    false_claims = sorted(n for n in committed_names if n not in available)
    if false_claims:
        print("FAIL: docs/stdlib.md claims these are available without "
              "import, but they no longer probe as available on this host: "
              + ", ".join(false_claims))
        return 1
    fresh_names = set(re.findall(r"^\|\s*`([A-Za-z_][A-Za-z0-9_.]*)`\s*\|",
                                  block, re.M))
    if block == committed_block:
        print("OK: exact match (%d functions)" % len(committed_names))
        return 0
    added = sorted(fresh_names - committed_names)
    removed_note = sorted(committed_names - fresh_names)
    note = []
    if added:
        note.append(f"{len(added)} additionally available on this host: {', '.join(added[:10])}"
                     + (" ..." if len(added) > 10 else ""))
    if removed_note:
        note.append(f"{len(removed_note)} committed name(s) not reachable on this host "
                     f"(host/libc divergence, not a false claim): {', '.join(removed_note[:10])}")
    if unplaced:
        note.append(f"available but no confident signature (left out of the table): "
                     f"{', '.join(sorted(unplaced))}")
    print("OK: host-diverged from the committed table, no false claims. "
          + ("; ".join(note) if note else "")
          + " -- consider regenerating with scripts/gen-stdlib-table.py")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                     help="compare against the committed doc; see check_against_committed")
    ap.add_argument("--print", dest="print_only", action="store_true",
                     help="print the generated block to stdout; do not touch any file")
    args = ap.parse_args()

    if args.check:
        sys.exit(check_against_committed())

    if not NUCLEUSC.exists():
        print(f"ERROR: {NUCLEUSC} not found -- run `make` first", file=sys.stderr)
        sys.exit(2)

    doc_text = DOC_PATH.read_text()
    if args.print_only:
        block, _avail, _claimed, _unplaced = compute(doc_text)
        print(block)
        return

    new_text, added, removed, unplaced = regenerate(doc_text)
    DOC_PATH.write_text(new_text)
    if added:
        print(f"added ({len(added)}): {', '.join(sorted(added))}", file=sys.stderr)
    if removed:
        print(f"removed ({len(removed)}): {', '.join(sorted(removed))}", file=sys.stderr)
    if unplaced:
        print(f"available but not rendered (no confident signature): "
              f"{', '.join(sorted(unplaced))}", file=sys.stderr)
    print(f"docs/stdlib.md regenerated: {DOC_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
