# Syntactic sugar and reader macros

## Reader macros

#### Designer:

The hardcoded `'` / `` ` `` / `~` / `~@` should be converted to entries in a user-extensible reader macro table with `def-rchar` being analogous to Common Lisp `set-macro-character`. `@` is added as a reader macro for `deref`.

#### Robot:

The `def-rchar` proposal is clean and well-motivated. Hardcoding `'`, `` ` ``, `~`, `~@` is the right call during bootstrap, but making them user-extensible is a natural next step. Adding `@` for `deref` is a good first user-facing case — `@p` reading as `(deref p)` is immediately useful and proves the mechanism works.

One thing to consider: reader macros that consume multiple tokens or do lookahead (like `~@`) need the table to support multi-character dispatch. Worth deciding upfront whether `def-rchar` supports single-character only (with `~@` as a special two-char entry) or whether there's a more general prefix-matching scheme.

#### Designer:

It's probably best to have a more generalized `def-rmacro` that takes an arbitrary string rather than a single character.

## Type syntax

#### Designer:

Types have a non-sexp syntax that's currently treated as part of a symbol's name. `(defn main:int () ...)` offers a familiar syntax for many developers, but it means macros don't have a clean way to interact with types. It also doesn't have support for function pointers, and Nucleus needs them for both feature-completeness and C interop. Pointers have a C-like `*` prefix, which is ugly in Nucleus and also doesn't play well with macros.

It is a core requirement for macros to be able to manipulate types.

The canonical form will become a positional type argument which may be a list or a symbol. `(defn foo int (bar (ptr fn Sym)) ...)` for example with various qualifiers in the list.

There should be a condensed format for readability. I have two options in mind:

`(defn foo:int (bar:ptr:fn:Sym) ...)` which is a superset of the current syntax, but requires special handling, probably with an idempotent `desugar` step.

`(defn $foo:int ($bar:ptn:fn:Sym) ...)` - a simple reader macro.

#### Robot:

The canonical sexp form is the right foundation. The question is which sugar to layer on top. Here are the options as I see them, including two alternatives beyond the two proposed:

**Option A: Canonical positional form only** — `(defn foo int (bar (ptr fn Sym)) ...)`

Pros:
- Types are ordinary sexps — macros manipulate them with the same tools they use for everything else. No special casing.
- Function pointer types compose naturally: `(ptr fn (ptr i8) i32)` reads as "pointer to function from ptr-to-i8 returning i32."
- No ambiguity in the reader or parser. A symbol is a symbol; a list is a list.
- The `.nuch` header format gets cleaner — declarations are just data.

Cons:
- Verbose for common cases. `(defn main int (argc i32 argv ptr) ...)` is wordier than `(defn main:int (argc:i32 argv:ptr) ...)`.
- Breaks all existing code. Every `defn`, `defvar`, `let`, `for`, `dotimes` — and every macro that emits them — needs updating.
- Parameter lists become harder to scan visually. In `(bar (ptr fn Sym))`, it's not immediately obvious whether `(ptr fn Sym)` is a type annotation on `bar` or a nested call.

**Option B: Colon sugar with `desugar` pass** — `(defn foo:int (bar:ptr:fn:Sym) ...)`

Pros:
- Superset of current syntax — existing code continues to work.
- Familiar to anyone who's written Nucleus. The `:` convention is well-established in the codebase.
- Compact. Type information stays visually attached to the name it annotates.
- An idempotent `desugar` pass means macros that want to work with types can call `desugar` on their input and get the canonical form. Macros that don't care about types can ignore them.

Cons:
- "Special handling" is doing a lot of work. The desugar pass must know which positions in which forms are name:type vs. other uses of `:` (if any). It's a second parser, essentially.
- Colon-chained types read left-to-right but the semantics nest: `bar:ptr:fn:Sym` means "bar is a ptr to fn taking Sym" which is `(bar (ptr fn Sym))`. The flattened syntax hides the tree structure. For simple cases (`x:i32`) this is fine; for complex types it becomes misleading.
- Where does `desugar` run? Before macro expansion? After? If before, macros see the canonical form (good for manipulation, but the user wrote the sugared form). If after, macro output can use either form (flexible, but now macros need to know about the sugar). An idempotent pass that runs both before and after expansion is safest but adds compile-time cost.
- Ambiguity: what if someone wants a symbol that literally contains `:`? Probably fine in practice (just don't), but it's a sharp edge.

**Option C: Reader macro `$`** — `(defn $foo:int ($bar:ptr:fn:Sym) ...)`

Pros:
- Simple to implement — the reader handles it, the rest of the compiler only sees the canonical form.
- Explicit opt-in. `$foo:int` is unambiguously "this is a typed name." No heuristics about which positions carry type info.
- Macros always see the canonical form. Clean separation of concerns.
- No desugar pass needed.

Cons:
- Ugly. The `$` adds noise to every typed binding. Given that most bindings in Nucleus code are typed, this means `$` everywhere.
- Unfamiliar. Neither Lisp nor C uses `$` this way. It's a new convention that has to be learned.
- Backwards-incompatible — all existing code needs `$` prefixes.
- If `$` is a reader macro, it needs to know where the colons are, so the reader is doing type-aware parsing. At that point it's essentially the desugar pass but earlier in the pipeline.

**Option D: Make `:` itself a reader macro.** `foo:int` reads as `(typed foo int)`, `bar:ptr:fn:Sym` reads as `(typed bar (ptr fn Sym))` (right-associative chaining). No `$` needed. The compiler and macros pattern-match on `typed` forms.

Pros:
- No sigil noise. Current syntax is almost unchanged — the reader does the work.
- Macros get structured data without a separate pass.

Cons:
- `:` in the middle of a token is unusual for a reader macro — normally reader macros trigger on the first character. This requires the tokenizer to split on `:`, which changes what constitutes a "symbol."
- It means `:` can never be part of a symbol name, which rules out Common Lisp-style keyword symbols if you ever want those.

**Option E: Metadata / decorator syntax.** `(defn (: int) foo ((: i32) bar) ...)` or with a reader macro: `^int foo` → `(meta int foo)`.

Pros:
- Types are clearly separated from names.

Cons:
- Very verbose without sugar. With sugar, you're back to the same reader macro questions.

**Recommendation:** Option B (colon sugar with desugar) is the pragmatic choice. It preserves the existing syntax that works well for simple cases, and the canonical form gives macros a clean target. The key design decision is: **desugar runs before macro expansion, and macro output is desugared again before compilation.** This way:

1. Macro authors always receive canonical forms — they never need to handle `:` syntax.
2. Macro output can use either sugar or canonical form (both work since desugar is idempotent).
3. User-facing code stays compact.

The desugar pass doesn't need to understand form semantics if you adopt a simple rule: any symbol containing `:` is split into `(name type1 type2 ...)` regardless of position. The compiler then decides what to do with the split form based on context. This keeps desugar context-free and easy to implement.

For function pointer types specifically, the colon chain `ptr:fn:Sym` maps naturally to `(ptr fn Sym)`, which the compiler can interpret as "pointer to function taking/returning Sym." You'll want to define the full grammar for function pointer type lists (parameter types, return type, calling convention), but that's orthogonal to the sugar question.

#### Designer:

Option B had been my first idea to solve this. We'll go with that for now.
