#!/usr/bin/env python3
"""Rewrite cons-cell AST access onto lib/nucleus/node.nuc's list API.

Stage 21, design/stage21-cleanup/ast-as-collection.md §8.3: every consumer of a
Node list must go through the API before the representation can change. This
converts the regular shapes and REFUSES the rest, printing them for hand
conversion — a wrong guess here is a silent miscompile, so the script never
guesses.

  scripts/stage21/list-api-sweep.py [--apply] FILE...

Rules (all of them span-preserving — untouched text stays byte-identical):

  (X 'car)                  -> (node-first X)
  (X 'cdr)                  -> (node-rest X)
  (make-cell A null L)      -> (node-list1 A L)
  (make-cell A (make-cell B null L) L)
                            -> (node-list2 A B L)        [up to node-list5]
  (make-cell A B L)         -> (node-cons A B L)

A make-cell chain is flattened only while every cell carries the SAME line
expression, since node-listN applies one line to all of them.

Refused (reported, never rewritten): a `set!` of 'car/'cdr (the list is being
built or mutated in place — that is a builder, and which builder is a judgement
the author has to make).
"""

import re
import sys

ATOM = re.compile(r"[^\s()\[\]{};\"]+")


class Node:
    __slots__ = ("kind", "text", "start", "end", "items")

    def __init__(self, kind, text, start, end, items=None):
        self.kind = kind          # 'list' | 'atom' | 'string'
        self.text = text          # source text of this node
        self.start = start
        self.end = end
        self.items = items or []  # child nodes, for a list


def parse(src):
    """Every form in `src`, as a tree of Nodes carrying source spans."""
    pos = 0
    n = len(src)

    def skip_trivia(i):
        while i < n:
            c = src[i]
            if c in " \t\r\n":
                i += 1
            elif c == ";":
                while i < n and src[i] != "\n":
                    i += 1
            else:
                break
        return i

    def read_form(i):
        i = skip_trivia(i)
        if i >= n:
            return None, i
        c = src[i]
        if c in "([{":
            # `#{` reads as one opener; the reader macro prefix is part of the atom
            start = i
            i += 1
            items = []
            while True:
                i = skip_trivia(i)
                if i >= n:
                    raise SyntaxError("unterminated form at %d" % start)
                if src[i] in ")]}":
                    i += 1
                    break
                child, i = read_form(i)
                if child is None:
                    raise SyntaxError("unterminated form at %d" % start)
                items.append(child)
            return Node("list", src[start:i], start, i, items), i
        if c == '"':
            start = i
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == '"':
                    i += 1
                    break
                i += 1
            return Node("string", src[start:i], start, i), i
        if c in ")]}":
            raise SyntaxError("stray %r at %d" % (c, i))
        m = ATOM.match(src, i)
        if not m:
            raise SyntaxError("cannot read at %d: %r" % (i, src[i:i + 20]))
        # A reader-macro prefix (' ` ~ ~@ & @ ?) binds to the form after it; the
        # atom regex already swallows the simple cases, and a prefix directly in
        # front of a `(` is handled here.
        end = m.end()
        atom = src[i:end]
        if atom in ("'", "`", "~", "~@", "&", "@", "?", "#"):
            inner, j = read_form(end)
            if inner is not None and inner.start == end:
                return Node("atom", src[i:inner.end], i, inner.end, [inner]), j
        return Node("atom", atom, i, end), end

    forms = []
    while True:
        pos = skip_trivia(pos)
        if pos >= n:
            break
        form, pos = read_form(pos)
        if form is None:
            break
        forms.append(form)
    return forms


def walk(forms):
    for f in forms:
        yield f
        if f.items:
            yield from walk(f.items)


def head_is(node, name):
    return (node.kind == "list" and node.items
            and node.items[0].kind == "atom" and node.items[0].text == name)


def selector(node, sel):
    """(X 'sel) — a two-element list whose second element is that quoted name."""
    return (node.kind == "list" and len(node.items) == 2
            and node.items[1].kind == "atom" and node.items[1].text == "'" + sel)


def chain(node, src):
    """A make-cell chain as (elements, tail, line) or None.

    `tail` is None when the chain ends in `null`; otherwise it is the node the
    chain conses onto. Flattening stops at a cell whose line differs. Each
    element carries the source text in front of it, so a chain written over
    several lines is rewritten over several lines.
    """
    if not head_is(node, "make-cell") or len(node.items) != 4:
        return None
    line = node.items[3].text
    elems = [node.items[1]]
    gaps = [src[node.items[0].end:node.items[1].start]]
    prev_end = node.items[1].end
    cur = node.items[2]
    while True:
        if cur.kind == "atom" and cur.text == "null":
            return elems, None, line, gaps
        inner = None
        if head_is(cur, "make-cell") and len(cur.items) == 4:
            inner = cur
        elif (cur.kind == "list" and len(cur.items) == 3
              and cur.items[0].kind == "atom" and cur.items[0].text == "as"
              and cur.items[1].text in ("raw:Node", "ptr")
              and head_is(cur.items[2], "make-cell") and len(cur.items[2].items) == 4):
            # (as raw:Node (make-cell …)) — the cast is the old call's return
            # type, and node-listN's own result carries it instead.
            inner = cur.items[2]
        if inner is None or inner.items[3].text != line or len(elems) >= 5:
            gaps.append(src[prev_end:cur.start])
            return elems, cur, line, gaps
        elems.append(inner.items[1])
        gaps.append(src[prev_end:cur.start])
        prev_end = inner.items[1].end
        cur = inner.items[2]


def rewrite(src, path, problems):
    edits = []          # (start, end, replacement)
    covered = []        # spans already rewritten, so a parent skips its children

    def inside_edit(node):
        return any(s <= node.start and node.end <= e for s, e in covered)

    forms = parse(src)
    for node in walk(forms):
        if node.kind != "list" or inside_edit(node):
            continue
        if head_is(node, "set!") and len(node.items) == 3:
            place = node.items[1]
            if selector(place, "car") or selector(place, "cdr"):
                # The place stays as written: only its OWNER knows which builder
                # replaces it. Cover the span so the selector rule below does not
                # rewrite a place into a call, which is not assignable.
                covered.append((place.start, place.end))
                problems.append((path, line_of(src, node.start),
                                 "set! of a cell field: " + one_line(node.text)))
                continue
        c = chain(node, src)
        if c is not None:
            elems, tail, line, gaps = c
            # A flattened chain loses one nesting level per cell, so a gap that
            # broke the line is re-indented to this form's own continuation
            # column instead of the deeper one it was written at.
            indent = " " * (column_of(src, node.start) + 2)
            gaps = [("\n" * g.count("\n") + indent) if "\n" in g else g
                    for g in gaps]
            args = "".join(g + e.text for g, e in zip(gaps, elems))
            if tail is None:
                rep = "(node-list%d%s %s)" % (len(elems), args, line)
            elif len(elems) == 1:
                rep = "(node-cons%s%s%s %s)" % (args, gaps[-1], tail.text, line)
            else:
                problems.append((path, line_of(src, node.start),
                                 "make-cell chain onto a tail: "
                                 + one_line(node.text)))
                continue
            edits.append((node.start, node.end, rep))
            covered.append((node.start, node.end))
            continue
        for sel, fn in (("car", "node-first"), ("cdr", "node-rest")):
            if selector(node, sel):
                edits.append((node.start, node.end,
                              "(%s %s)" % (fn, node.items[0].text)))
                covered.append((node.start, node.end))
                break

    out = []
    pos = 0
    for start, end, rep in sorted(edits):
        if start < pos:          # a parent rewrote this span already
            continue
        out.append(src[pos:start])
        out.append(rep)
        pos = end
    out.append(src[pos:])
    return "".join(out), len(edits)


def column_of(src, pos):
    return pos - (src.rfind("\n", 0, pos) + 1)


def line_of(src, pos):
    return src.count("\n", 0, pos) + 1


def one_line(text):
    t = " ".join(text.split())
    return t if len(t) <= 90 else t[:87] + "..."


def main(argv):
    apply_ = "--apply" in argv
    paths = [a for a in argv if not a.startswith("--")]
    problems = []
    total = 0
    for path in paths:
        src = open(path).read()
        count = 0
        while True:
            new, n = rewrite(src, path, problems if count == 0 else [])
            if n == 0:
                break
            count += n
            src = new
        total += count
        if apply_ and count:
            open(path, "w").write(src)
        print("%-32s %3d rewritten%s" % (path, count, "" if apply_ else " (dry run)"))
    if problems:
        print("\n%d site(s) need hand conversion:" % len(problems))
        for path, line, what in problems:
            print("  %s:%d  %s" % (path, line, what))
    print("\ntotal %d" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
