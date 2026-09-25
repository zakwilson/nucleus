#!/usr/bin/env python3
"""Stage 21 PK-5a — retire `addr-of` and adopt the pointer-kind / type-sigil sugar.

One paren-aware rewriter, string- and comment-aware, applying the rules of
design/stage21-cleanup/pointer-kind-spellings.md §7 in order to each form.  It
REFUSES rather than guesses: a shape a rule cannot classify is left untouched
and reported, and the refusal list is a deliverable.

    R1  (addr-of X)                  -> &X         everywhere (not under quote)
    R2  (addr-of p 'f)               -> (ref p 'f) everywhere (not under quote)
    R3  (ref X), X not a keyword     -> &X         everywhere but a match pattern
    R4  (ptr X), X a symbol or list  -> &X         type slots only
    R5  ref:T… / ptr:T… token        -> &T…        everywhere but quoted data and a
                                                   binding NAME; a name segment ahead
                                                   of the prefix is already attached
    R6  (Maybe X)                    -> ?X / ?(…)  type slots only
    R7  (Result X Err)               -> !X / !(…)  type slots only
    R8  (name T), T rewritten by R3–R7, name a plain symbol
                                     -> name:T     binding pairs; a rewritten return
                                                   form adjacent to its parameter
                                                   list attaches as `):T`

"Type slot" is what the script can see syntactically (§7): the operand of
`as`/`unsafe/cast`/`cast`/`sizeof`/`alloca`/`make`, `deftype`'s body,
`defcast`'s two types; the type of a binding pair in a `let`/`with` list, a
parameter list, a `defstruct`/`defunion`-arm/anonymous `struct`/`union` field
list, a `defvar`/`extern` name; the return form after a parameter list; and
everything inside one.  A `(Maybe X)`, `(Result X Err)` or `(ptr X)` anywhere
else is refused and listed.

Refusals the design table does not spell out, each a meaning the rewrite
would change (the PK-5a entry in design/progress.md records the counts):
  * R6 over `(raw T)` / `raw:T`: `(Maybe (raw T))` is the value-Maybe,
    `?raw:T` the niche pointer.
  * R1/R3 whose operand is a legacy marker name (`&rest` reads as the marker).
  * a form with a comment inside it (collapsing it would drop the comment).
  * R1/R2 under `quote` (a literal).  Under `quasiquote` only R1, R2, R3 and
    R5 run — the node-identical rules plus the two `addr-of` rules, which
    reach macro bodies (JIT-only) — and an `unquote` operand is code again.
Three refusals are gone with the defects behind them: a paren operand in an
exported slot (PK-4b), R6/R7 over a type variable (the boot predated PK-4b),
and R5 on an `extend` subject (fixed 2026-09-23; design/progress.md).

Usage:
    sugar-sweep.py --dry-run FILE ...     # histogram + refusals, no writes
    sugar-sweep.py FILE ...               # rewrite in place
    sugar-sweep.py --rules R1,R2 FILE ... # a subset (PK-5b's tests/ sweep)

Idempotent: every output spelling is one no rule matches, and a form is
rewritten bottom-up, so one pass is a fixed point; run twice to prove it.
"""

import argparse
import bisect
import re
import sys
from collections import Counter

# ---------------------------------------------------------------------------
# Scanner: the reader's token grammar (lib/read.nuc), spans kept for splicing.
# ---------------------------------------------------------------------------

RMACROS = ("~@", "~", "'", "`", "@", "&")
LEGACY_MARKERS = ("rest", "where", "optional", "repr")
SYM_STOP = set(' \t\n\r()";[]{}')


class Node:
    __slots__ = ("kind", "start", "end", "text", "open", "close", "children",
                 "prefix", "operand", "atom", "form", "form2", "line")

    def __init__(self, kind, start, end, line):
        self.kind = kind          # atom | str | char | list | rmacro | fused
        self.start = start
        self.end = end
        self.line = line
        self.text = None          # atom/str/char: source text
        self.open = self.close = None
        self.children = None      # list
        self.prefix = self.operand = None   # rmacro
        self.atom = self.form = None        # fused: `name:` atom + `(…)` form
        self.form2 = None                   # fused fn pointer: the `(params)` group

    def head(self):
        if self.kind == "list" and self.open == "(" and self.children \
                and self.children[0].kind == "atom":
            return self.children[0].text
        return None


class Refuse(Exception):
    pass


def skip_ws(s, i):
    n = len(s)
    while i < n:
        c = s[i]
        if c in " \t\n\r":
            i += 1
        elif c == ";":
            while i < n and s[i] != "\n":
                i += 1
        else:
            break
    return i


def open_segment(atom):
    """PK-2's fuse gate over the lexer-expanded spelling (mid-atom `&` is `ref:`)."""
    state = True
    for c in atom.replace("&", "ref:"):
        if c == ":":
            state = True
        elif c not in "?!":
            state = False
    return state


class Parser:
    def __init__(self, src, path):
        self.s = src
        self.path = path
        self.i = 0
        self.nl = [j for j, c in enumerate(src) if c == "\n"]

    def line_at(self, i):
        return bisect.bisect_right(self.nl, i - 1) + 1

    def parse_all(self):
        out = []
        while True:
            self.i = skip_ws(self.s, self.i)
            if self.i >= len(self.s):
                return out
            out.append(self.form())

    def form(self):
        s, i = self.s, self.i
        c = s[i]
        line = self.line_at(i)
        if c == "(":
            return self.list_("(", ")")
        if c == "[":
            return self.list_("[", "]")
        if c == "{":
            return self.list_("{", "}")
        if c == "#" and s.startswith("#{", i):
            return self.list_("#{", "}")
        if c in ")]}":
            raise Refuse("%s:%d: unexpected %s" % (self.path, line, c))
        if c == "&" and any(s.startswith("&" + m, i) and
                            (i + 1 + len(m) >= len(s) or s[i + 1 + len(m)] in SYM_STOP)
                            for m in LEGACY_MARKERS):
            return self.atom()
        for p in RMACROS:
            if s.startswith(p, i):
                n = Node("rmacro", i, -1, line)
                n.prefix = p
                self.i = i + len(p)
                n.operand = self.form()
                n.end = n.operand.end
                return n
        if c == '"' or (c == "c" and s.startswith('c"', i)):
            return self.string()
        if c == "\\":
            return self.char()
        return self.atom()

    def list_(self, open_, close):
        s = self.s
        n = Node("list", self.i, -1, self.line_at(self.i))
        n.open, n.close = open_, close
        n.children = []
        self.i += len(open_)
        while True:
            self.i = skip_ws(s, self.i)
            if self.i >= len(s):
                raise Refuse("%s:%d: unterminated %s" % (self.path, n.line, open_))
            if s[self.i] == close:
                self.i += 1
                n.end = self.i
                return n
            n.children.append(self.form())

    def string(self):
        s, i = self.s, self.i
        n = Node("str", i, -1, self.line_at(i))
        if s[i] == "c":
            i += 1
        i += 1
        while i < len(s) and s[i] != '"':
            i += 2 if s[i] == "\\" else 1
        if i >= len(s):
            raise Refuse("%s:%d: unterminated string" % (self.path, n.line))
        n.end = self.i = i + 1
        n.text = s[n.start:n.end]
        return n

    def char(self):
        s, i = self.s, self.i
        n = Node("char", i, -1, self.line_at(i))
        i += 1
        if s.startswith("u{", i):
            while i < len(s) and s[i] != "}":
                i += 1
            i += 1
        else:
            # `\(` is one char; a named char (`\newline`) runs to a delimiter.
            i += 1
            while i < len(s) and s[i] not in SYM_STOP:
                i += 1
        n.end = self.i = i
        n.text = s[n.start:n.end]
        return n

    def atom(self):
        s, i = self.s, self.i
        n = Node("atom", i, -1, self.line_at(i))
        j = i
        while j < len(s) and s[j] not in SYM_STOP:
            j += 1
        if j == i:
            raise Refuse("%s:%d: cannot tokenize %r" % (self.path, n.line, s[i:i + 8]))
        n.end = self.i = j
        n.text = s[i:j]
        # PK-2: an open final segment fuses with an immediately following `(`.
        if j < len(s) and s[j] == "(" and open_segment(n.text):
            f = Node("fused", i, -1, n.line)
            f.atom = n
            f.form = self.list_("(", ")")
            f.end = f.form.end
            # A function-pointer type is two groups: `x:(fn ret)(params)`.
            if f.form.head() == "fn" and self.i < len(s) and s[self.i] == "(":
                f.form2 = self.list_("(", ")")
                f.end = f.form2.end
            return f
        return n


# ---------------------------------------------------------------------------
# Roles (what a position means) and the rewrite.
# ---------------------------------------------------------------------------

V, T, BINDER, BL, PL, ARM, SIG, PAT, RET, Q, QQ, OPT, MATCHARM, NAME, TLIST = (
    "V", "T", "BINDER", "BL", "PL", "ARM", "SIG", "PAT", "RET", "Q", "QQ", "OPT",
    "MATCHARM", "NAME", "TLIST")
STRUCTURAL = {BL, PL, ARM, SIG, OPT, MATCHARM, TLIST}

TYPE_OPERAND_HEADS = {"as", "unsafe/cast", "cast", "sizeof", "alloca", "make"}
LAMBDA_HEADS = {"fn", "vfn", "mfn", "cfn"}
DEFN_HEADS = {"defn", "defn-", "declare"}

PREFIX_RE = re.compile(r"^(:?)([?!]*)((?:(?:ref|ptr):)+)(.*)$")

ALL_RULES = frozenset("R1 R2 R3 R4 R5 R6 R7 R8".split())


class Rewriter:
    def __init__(self, src, path, stats, refusals, rules=ALL_RULES):
        self.s = src
        self.path = path
        self.stats = stats
        self.refusals = refusals
        self.rules_on = rules
        self.changed = 0

    # -- helpers ------------------------------------------------------------

    def on(self, rule):
        return rule in self.rules_on

    def refuse(self, node, why):
        self.refusals.append((self.path, node.line, why))

    def hit(self, rule):
        self.stats[rule] += 1
        self.changed += 1

    def orig(self, node):
        return self.s[node.start:node.end]

    def gaps_clean(self, node):
        """No comment survives inside a form a rule collapses to a sigil."""
        s = self.s
        prev = node.start + len(node.open)
        for c in node.children:
            if ";" in s[prev:c.start]:
                return False
            prev = c.end
        return ";" not in s[prev:node.end - 1]

    def splice(self, node, texts, gaps=None):
        """The list's own text with each child replaced, gaps kept verbatim
        (or overridden: `gaps[i]` replaces the gap before child i)."""
        s = self.s
        out = [node.open]
        prev = node.start + len(node.open)
        for i, (c, t) in enumerate(zip(node.children, texts)):
            out.append(gaps[i] if gaps and i in gaps else s[prev:c.start])
            out.append(t)
            prev = c.end
        out.append(s[prev:node.end - 1])
        out.append(node.close)
        return "".join(out)

    @staticmethod
    def is_keyword(n):
        return n.kind == "atom" and n.text.startswith(":") and len(n.text) > 1

    @staticmethod
    def is_plain_symbol(n):
        return (n.kind == "atom" and ":" not in n.text
                and not n.text[0].isdigit() and n.text[0] not in "-+.")

    @staticmethod
    def sigil_form(text):
        return text.startswith(("&", "?", "!"))

    @staticmethod
    def raw_operand(opnode):
        if opnode.kind == "list" and opnode.head() == "raw":
            return True
        return opnode.kind == "atom" and re.match(r"^[?!]*raw:", opnode.text) is not None

    # -- the walk -----------------------------------------------------------

    def rw(self, n, role):
        k = n.kind
        if k == "str" or k == "char":
            return n.text
        if k == "atom":
            return self.rw_atom(n, role)
        if k == "rmacro":
            return self.rw_rmacro(n, role)
        if k == "fused":
            return self.rw_fused(n, role)
        return self.rw_list(n, role)

    def r5(self, text, role, node):
        """R5 on one atom spelling; None when it does not apply."""
        if not self.on("R5"):
            return None
        m = PREFIX_RE.match(text)
        if not m:
            return None
        colon, sig, chain, rest = m.groups()
        if role == BINDER:
            self.refuse(node, "R5: binding named by a pointer-kind prefix: %s" % text)
            return None
        if role in (Q, PAT, NAME):
            self.stats["skip: R5 under quote / in a pattern / a definer name"] += 1
            return None
        self.hit("R5 ref:/ptr: token -> &")
        return colon + sig + "&" * chain.count(":") + rest

    def rw_atom(self, n, role):
        t = n.text
        if t.startswith((":", "?", "!", "r", "p")):
            new = self.r5(t, role, n)
            if new is not None:
                return new
        return t

    def rw_rmacro(self, n, role):
        p = n.prefix
        if p == "'":
            inner = Q
        elif p == "`":
            inner = QQ
        elif p in ("~", "~@"):
            inner = V if role == QQ else role
        elif p == "&":
            inner = T if role in (T, RET) else role if role in (Q, QQ) else V
        else:                       # `@` deref
            inner = role if role in (Q, QQ) else V
        return p + self.rw(n.operand, inner)

    def rw_fused(self, n, role):
        """`name:(T)` — an open-segment atom fused with the form after it."""
        a, f = n.atom, n.form
        if role in (BINDER, RET, T):
            frole = T
        elif role in (Q, QQ, PAT, NAME):
            frole = role
        else:
            self.refuse(n, "fused atom+form outside a binding/type slot: %s(" % a.text)
            frole = V
        head = a.text
        m = PREFIX_RE.match(a.text)
        if m and m.group(4) == "":
            new = self.r5(a.text, role, n)
            if new is not None:
                head = new
        out = head + self.rw(f, frole)
        if n.form2 is not None:
            out += self.s[f.end:n.form2.start] + self.rw(n.form2, TLIST if frole == T else frole)
        return out

    def rw_list(self, n, role):
        ch = n.children
        if n.open != "(":
            # [..] {..} #{..} literals: elements are values (or data).
            inner = role if role in (Q, QQ, PAT) else V
            return self.splice(n, [self.rw(c, inner) for c in ch])
        if not ch:
            return self.splice(n, [])
        if role == RET:
            role = T
        if role == Q:
            if n.head() == "addr-of":
                self.refuse(n, "R1/R2 under quote (a literal)")
            return self.splice(n, [self.rw(c, Q) for c in ch])
        if role in (PAT, NAME):
            return self.splice(n, [self.rw(c, role) for c in ch])
        if role == QQ:
            inner = V if n.head() in ("unquote", "unquote-splice") else QQ
            texts = [self.rw(ch[0], QQ)] + [self.rw(c, inner) for c in ch[1:]]
            return self.rules(n, QQ, texts)

        roles = self.child_roles(n, role)
        texts = [self.rw(c, r) for c, r in zip(ch, roles)]

        # R8 for the return slot: `(params) ?X` -> `(params):?X` when adjacent.
        gaps = {}
        for i, r in enumerate(roles):
            if r == RET and i > 0 and self.on("R8") and texts[i] != self.orig(ch[i]) \
                    and self.sigil_form(texts[i]):
                gap = self.s[ch[i - 1].end:ch[i].start]
                if gap.strip() == "":
                    gaps[i] = ":"
                    self.hit("R8 (params) T -> (params):T")
        if role in STRUCTURAL:
            return self.splice(n, texts, gaps)
        if role == BINDER:
            if len(ch) == 2 and self.on("R8") and self.is_plain_symbol(ch[0]) \
                    and texts[1] != self.orig(ch[1]) and self.sigil_form(texts[1]) \
                    and self.gaps_clean(n):
                self.hit("R8 (name T) -> name:T")
                return texts[0] + ":" + texts[1]
            return self.splice(n, texts)
        return self.rules(n, role, texts, gaps)

    # -- rule application on a list whose children are already rewritten ----

    def rules(self, n, role, texts, gaps=None):
        ch = n.children
        h = n.head()
        nargs = len(ch) - 1
        op = ch[1] if nargs >= 1 else None

        if h == "addr-of" and (self.on("R1") or self.on("R2")):
            if nargs == 1 and not self.on("R1"):
                pass
            elif nargs == 2 and not self.on("R2"):
                pass
            elif nargs == 1:
                if not self.gaps_clean(n):
                    self.refuse(n, "R1: comment inside the form")
                elif op.kind == "atom" and op.text in LEGACY_MARKERS:
                    self.refuse(n, "R1: `&%s` reads as the legacy marker" % op.text)
                else:
                    self.hit("R1 (addr-of x) -> &x")
                    return "&" + texts[1]
            elif nargs == 2:
                self.hit("R2 (addr-of p 'f) -> (ref p 'f)")
                return self.splice(n, ["ref"] + texts[1:], gaps)
            else:
                self.refuse(n, "R1/R2: addr-of with %d operands" % nargs)

        if h == "ref" and nargs == 1 and self.on("R3") and not self.is_keyword(op):
            if op.kind == "rmacro" and op.prefix == "~@":
                self.refuse(n, "R3: splice operand")
            elif not self.gaps_clean(n):
                self.refuse(n, "R3: comment inside the form")
            elif op.kind == "atom" and op.text in LEGACY_MARKERS:
                self.refuse(n, "R3: `&%s` reads as the legacy marker" % op.text)
            elif op.kind in ("str", "char"):
                self.refuse(n, "R3: literal operand")
            else:
                self.hit("R3 (ref X) -> &X")
                return "&" + texts[1]

        if role == QQ:
            return self.splice(n, texts, gaps)

        if h == "ptr" and nargs == 1 and self.on("R4") and not self.is_keyword(op) \
                and op.kind in ("atom", "list", "rmacro", "fused"):
            if role != T:
                self.refuse(n, "R4: (ptr X) outside a type slot")
            elif not self.gaps_clean(n):
                self.refuse(n, "R4: comment inside the form")
            else:
                self.hit("R4 (ptr X) -> &X")
                return "&" + texts[1]
        elif h == "ptr" and nargs >= 2 and not self.is_keyword(op):
            self.stats["skip: (ptr ptr …) multi-operand"] += 1

        if h == "Maybe" and nargs == 1 and self.on("R6"):
            if role != T:
                self.refuse(n, "R6: (Maybe X) outside a type slot")
            elif not self.gaps_clean(n):
                self.refuse(n, "R6: comment inside the form")
            elif self.raw_operand(op):
                self.refuse(n, "R6: (Maybe (raw T)) is the value-Maybe, ?raw:T the niche")
            else:
                self.hit("R6 (Maybe X) -> ?X")
                return "?" + texts[1]

        if h == "Result" and nargs == 2 and self.on("R7"):
            if ch[2].kind == "atom" and ch[2].text == "Err":
                if role != T:
                    self.refuse(n, "R7: (Result X Err) outside a type slot")
                elif not self.gaps_clean(n):
                    self.refuse(n, "R7: comment inside the form")
                else:
                    self.hit("R7 (Result X Err) -> !X")
                    return "!" + texts[1]
            else:
                self.stats["skip: (Result X E) with E != Err"] += 1

        return self.splice(n, texts, gaps)

    # -- which role each child of a list gets ------------------------------

    def child_roles(self, n, role):
        ch = n.children
        h = n.head()
        m = len(ch)
        roles = [V] * m

        if role == T:
            # Inside a type everything is a type, except an anonymous
            # struct/union's field list and a LIST of parameter types: the
            # `(params)` group of `((fn ret) (params))` / `(BoxedFn (params) ret)`
            # is `(ptr i32)` = two parameters, not a pointer type.
            if h in ("struct", "union"):
                return [V] + [BINDER] * (m - 1)
            if h == "fn":
                return [V] + [T] * (m - 1)
            if ch[0].kind == "list" and ch[0].head() == "fn":
                return [T] + [TLIST] * (m - 1)
            if h == "BoxedFn":
                return [V, TLIST] + [T] * (m - 2)
            return [T] * m

        if role == TLIST:
            return [T] * m

        if role == BL:
            # (name val name val …); a binder is a symbol or a (name T) pair,
            # and a `:volatile`-style attribute keyword prefixes a binder.
            out = []
            slot = 0
            for c in ch:
                if slot % 2 == 0 and self.is_keyword(c):
                    out.append(V)
                    continue
                out.append(BINDER if slot % 2 == 0 else V)
                slot += 1
            if slot % 2:
                self.refuse(n, "let/with: odd binding list")
                return roles
            return out

        if role == PL:
            out = []
            mode = "param"
            for c in ch:
                if c.kind == "atom" and c.text == ":where":
                    mode = "where"
                    out.append(V)
                elif c.kind == "atom" and c.text == ":optional":
                    mode = "opt"
                    out.append(V)
                elif self.is_keyword(c):
                    out.append(V)
                elif mode == "param":
                    out.append(BINDER)
                elif mode == "opt":
                    out.append(OPT)
                else:
                    out.append(V)
            return out

        if role == OPT:
            return [BINDER] + [V] * (m - 1)

        if role == ARM:
            # (arm field… [:repr mode])
            out = [V]
            i = 1
            while i < m:
                if self.is_keyword(ch[i]):
                    out.append(V)
                    if i + 1 < m:
                        out.append(V)
                        i += 1
                else:
                    out.append(BINDER)
                i += 1
            return out

        if role == SIG:
            if m >= 2:
                roles[1] = PL
            if m >= 3:
                roles[2] = RET
            return roles

        if role == MATCHARM:
            return [PAT] + [V] * (m - 1)

        if role == BINDER:
            if m == 2:
                return [V, T]
            if m == 3 and ch[1].kind == "list" and ch[1].head() == "fn":
                return [V, T, T]        # the fn-pointer triple (name (fn ret) (params))
            self.refuse(n, "binding pair with %d elements" % m)
            return roles

        if role == NAME:
            return [NAME] * m

        # role == V: classify by head.
        if h in TYPE_OPERAND_HEADS:
            if m >= 2:
                roles[1] = T
        elif h in ("let", "with"):
            if m >= 2:
                roles[1] = BL
        elif h in DEFN_HEADS or h == "defmacro":
            if m >= 3:
                roles[2] = PL
            if m >= 4 and h != "defmacro":
                roles[3] = RET
        elif h in LAMBDA_HEADS:
            if m >= 2:
                roles[1] = PL
            if m >= 3:
                roles[2] = RET
        elif h == "defprotocol":
            roles[1] = NAME
            for i in range(2, m):
                if ch[i].kind == "list":
                    roles[i] = SIG
        elif h == "defstruct":
            roles[1] = NAME
            for i in range(2, m):
                roles[i] = BINDER
        elif h == "defunion":
            roles[1] = NAME
            for i in range(2, m):
                if ch[i].kind == "list":
                    roles[i] = ARM
        elif h == "deftype":
            roles[1] = NAME
            if m >= 3:
                roles[2] = T
        elif h in ("defvar", "extern"):
            for i in range(1, m):
                if not self.is_keyword(ch[i]):
                    roles[i] = BINDER
                    break
        elif h == "defcast":
            if m >= 3:
                roles[1] = roles[2] = T
        elif h == "match":
            for i in range(2, m):
                if ch[i].kind == "list":
                    roles[i] = MATCHARM
        elif h == "extend":
            if m > 1:
                roles[1] = T
        return roles


def parse_file(path, refusals):
    try:
        return Parser(open(path).read(), path).parse_all()
    except Refuse as e:
        refusals.append((path, 0, "unparsed file: %s" % e))
        return None


def rewrite_file(path, src, stats, refusals, rules=ALL_RULES):
    tree = parse_file(path, refusals)
    if tree is None:
        return src, 0
    rw = Rewriter(src, path, stats, refusals, rules)
    out = []
    prev = 0
    for n in tree:
        out.append(src[prev:n.start])
        out.append(rw.rw(n, V))
        prev = n.end
    out.append(src[prev:])
    return "".join(out), rw.changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--rules", default=None,
                    help="comma-separated subset of R1..R8 to apply (default: all); "
                         "PK-5b sweeps tests/ with R1,R2 so fixture spellings stay")
    a = ap.parse_args()
    rules = ALL_RULES
    if a.rules is not None:
        rules = frozenset(r.strip().upper() for r in a.rules.split(","))
        bad = rules - ALL_RULES
        if bad:
            sys.exit("unknown rule(s): %s" % ", ".join(sorted(bad)))

    stats = Counter()
    refusals = []
    total = 0
    for path in a.files:
        src = open(path).read()
        new, changed = rewrite_file(path, src, stats, refusals, rules)
        total += changed
        if not a.dry_run and new != src:
            open(path, "w").write(new)
        if changed:
            print("%-40s %5d rewritten" % (path, changed))

    print("\n%d sites rewritten" % total)
    for k, v in sorted(stats.items()):
        print("  %-48s %6d" % (k, v))
    if refusals:
        print("\n%d refused:" % len(refusals))
        for path, ln, why in refusals:
            print("  %s:%d  %s" % (path, ln, why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
