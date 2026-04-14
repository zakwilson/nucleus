## Macros and JIT

Now that Nucleus is self-hosted (stage-1 == stage-2, all tests green), these are the features that move the language from "compiler that can compile itself" to "language worth writing programs in."

The ordering here is deliberate: list manipulation and quoting are prerequisites for macros, and macros are the prerequisite for everything else becoming ergonomic. Get these three right and most future features can be built *in* Nucleus rather than bolted onto the compiler.

### cond (implemented)

#### Designer:

`cond` is the conditional form found in most lisps. It replaces `if` as the sole conditional builtin. It takes an arbitrary number of test-result pairs:

    (cond (= foo 1) "one"
          (= foo 2) "two"
          (= foo 3) "three"
          true "big")
        
This eliminates the deep nesting of a series of `if`s

    (if (= foo 1)
      "one"
      (if (= foo 2)
        "two"
        (if = foo 3
          "three"
          "big")))
          
From a linguistic or mathematical perspective, `cond` is the general form and `if` is a special case so `cond` should be the builtin and `if` should be a macro on top of it. That's my preferred design.

From an implementation perspective, it's possible that the binary branch of `if` maps better to the underlying primitives. Simplicity of implementation is more important than purity of design. It is acceptable for `if` to be the builtin if `cond` has a much more complex implementation.

#### Robot:

In practice, `cond` is straightforward to implement as a chain of conditional branches in LLVM IR — each test-result pair becomes a compare-and-branch to either the result block or the next test. This is the same structure you'd get from nested `if`s, just generated from a flat list of pairs. The implementation complexity is comparable to `if`, so `cond` as the builtin with `if` as a macro (once macros exist) is viable. In the interim, `cond` can be a special form alongside `if` — the compiler already handles `if` with two branches, and `cond` is a loop over pairs emitting the same pattern. This is a good candidate for the *first* feature to add: it requires no new infrastructure and immediately improves the compiler's own source (the `emit_node` dispatch is full of nested `if`s).

**Status:** Implemented. `if` has been removed; `cond` is the sole conditional builtin. `if` will return as a macro once the macro system exists. The nested if-else chain in the top-level dispatch (formerly 7 nested `if`s) is now a single flat `cond`, demonstrating the readability improvement.

### list manipulation

#### Designer:

Macros will need list manipulation primitives:

* cons
* list
* first
* rest
* append

And quoting:

* quote (')
* quasiquote (`) allowing splicing
* eval-splice (~)
* flattening-eval-splice (~@)

#### Robot:

This is where the design gets interesting and deserves careful thought. The current compiler represents the AST as C-style structs allocated from an arena. For macros to manipulate code, we need actual list values at compile time. There are two paths:

1. **Compile-time interpreter.** The compiler interprets macro bodies at compile time using a list representation that exists only during compilation. The compiled output never contains list operations unless the program explicitly uses them at runtime. This is the traditional Lisp approach and aligns with "zero mandatory runtime overhead."

2. **Lists as a runtime type.** Add cons cells as a first-class heap type, available at both compile time and runtime. Simpler to implement but adds a runtime type that C doesn't have, moving away from "drop-in substitute for C."

Path 1 is more aligned with the design principles (zero overhead, small core), but it means the compiler needs an embedded interpreter before macros work — a significant implementation effort. Path 2 gets macros working sooner but at an architectural cost.

The quoting syntax also interacts with reader macros (mentioned in overview.md). If `'` is a reader macro for `quote`, then the reader macro system needs to exist before quoting works, which pushes the dependency chain further back. Alternatively, `'` can initially be hardcoded in the reader (as `;` comments already are) and later generalized to the reader macro system.

Suggested ordering: hardcode `quote` and `'` in the reader → implement the compile-time list representation → add `cons`/`first`/`rest`/`append` as compile-time builtins → implement quasiquote/splicing → then macros become possible. `list` is just a convenience wrapper over `cons`.

#### Designer:

A separate compiler and interpreter could increase complexity exponentially over time and should only be considered as a last resort. Lists as a runtime type *library* could keep the core small. The compiler would always require it, but that's not a runtime cost.

I'd like to have reader macros for [' quote], [` quasiquote], [~ unquote], and [~@ unquote-splice] eventually, but it would be convenient to have the shortcuts before reader macros are implemented. Adding both the special forms and hardcoded syntactic sugar for them could work as a temporary solution until we have real reader macros.

####Robot:

The library-based lists approach is a clever middle ground. The implementation shape: cons cells are a `defstruct` with `car` and `kind` tag fields (or a tagged union), and `cons`/`first`/`rest`/`append` are ordinary Nucleus functions. The compiler `include`s this library and uses it internally — since the compiler is itself a Nucleus program, whatever the compiler uses *must* be expressible in the language. Programs that don't touch lists don't pay for them. This preserves "drop-in substitute for C" at the language level while giving the compiler what it needs.

One wrinkle: if the compile-time interpreter executes Nucleus code that manipulates cons cells, those cons cells need to exist in the compiler's address space at compile time. Either the interpreter shares its heap with the running compiler (easy, but means compile-time allocations leak into the compiler's memory), or there's a separate compile-time arena that gets discarded after expansion (cleaner, but more plumbing). The arena approach matches the existing stage-0 "leak on exit" model the compiler already uses.

Hardcoding `'` / `` ` `` / `~` / `~@` in the reader as a transitional step is low-risk: they become a handful of cases in the tokenizer, similar to how `;` comments are handled today. When reader macros land, those cases get replaced by entries in the reader macro table. The user-visible syntax doesn't change, so no code needs updating.

#### Designer:

Leaking memory during compilation is OK for now. I noted it in long-term-issues.md

### macros

#### Designer:

Macros are what makes Nucleus special. By making the full power of the language available to manipulate code during compilation, abstractions without runtime overhead are possible in Nucleus that are impossible in other languages.

#### Robot:

The macro system design needs to address several concrete questions:

**Expansion model.** Do macros expand in a single pass (top-down, each macro sees unexpanded code) or iteratively (expand until no more macros remain)? Single-pass is simpler but means macros can't compose as freely. Iterative is more powerful but needs a termination check. Most Lisps use iterative expansion. Given the "worse is better" principle, starting with single-pass and upgrading later is reasonable.

**Hygiene.** Traditional Lisp macros are unhygienic — they can capture or shadow bindings in the expansion site. Scheme-style hygienic macros avoid this but add significant complexity. For a systems language where the programmer is expected to manage memory manually, unhygienic macros (with a `gensym` facility for when you need fresh names) are the pragmatic choice. This matches Common Lisp's approach.

**Compile-time environment.** Macros need to call functions at compile time. This means the compiler must be able to *execute* Nucleus code, not just emit IR for it. The compile-time interpreter from the list manipulation section is the foundation here. The scope of what's available at compile time matters: can macros call `malloc`? Open files? The minimal answer is list manipulation plus arithmetic plus string operations — enough to construct and transform AST fragments. Something like Common Lisp's `eval-when` (already mentioned in overview.md) would let the programmer control what's available at compile time vs. runtime.

**What macros unlock.** Once macros work, many things currently in the compiler or missing entirely become expressible in library code:
- `let` bindings
- Pattern matching / destructuring
- `for` loops / iteration forms
- `defmethod` / method dispatch on struct types (relates to the compile-time dispatch musings)
- `set!` as a macro that dispatches on its target (as explored in musings.md)
- Type-checked struct accessors that look like function calls

This is the payoff: each macro replaces what would otherwise be a new special form in the compiler. The compiler stays small and the language grows through libraries.

#### Designer

Macros must expand iteratively by the time phase 2 is complete. Single-pass as an intermediate step is fine. Unhygenic macros with gensym are the correct choice for Nucleus.

Nucleus needs something like eval-when, though probably with less verbose syntax. A single special form like (compile-time &body) might be sufficient, especially early on. Macros shouldn't be restricted from using any parts of the language arbitrarily even if using a certain feature seems unwise. Excluding features long-term due to implementation complexity *may* be acceptable on a case-by-case basis.

Excluding features to simplify implementation is acceptable during phase 2.

#### Robot:

Iterative expansion needs a termination rule. The two common approaches: (1) expand a form, if it's still a macro call, expand again, and bound total expansions per form at some large constant (e.g. 1024) to catch runaway recursion; (2) mark each form with its expansion history and refuse to re-expand a macro that's already in its ancestry. Option 1 is simpler and matches "worse is better" — a programmer who hits the bound has almost certainly written infinite recursion, and the error message can point them at it.

`(compile-time &body)` is much nicer than Common Lisp's `eval-when` triple of `:compile-toplevel`, `:load-toplevel`, `:execute`. That distinction exists for a file-loading model Nucleus doesn't have. For Nucleus, the only meaningful axis is "does this code run at compile time or runtime?" — a single form captures that. If a use case later emerges that needs finer control, it can be added without breaking existing code.

"Macros shouldn't be restricted from using any parts of the language arbitrarily" is the right call but has a concrete consequence: the compile-time environment has to be the *full* language, which means the compile-time interpreter has to handle everything the code generator handles. This argues for making the interpreter a natural fall-out of the compiler architecture — e.g., have `emit_node` optionally produce a value directly instead of IR — rather than writing a separate interpreter. Otherwise the interpreter and the code generator can drift apart and macros that work at compile time might behave differently at runtime.

The "excluding features in phase 2 is OK" line is important context: it signals that the phase 2 implementation doesn't need to be the final design. A simpler subset can ship, and restrictions can be lifted as the implementation matures.

#### Designer:

A hardcoded expansion limit is fine for phase 2, and may be fine long-term.

Long-term, a compiler-only approach is strongly preferred, i.e. a just-in-time compilation step that shares most of its code path with the ahead-of-time compilation. During phase 2, the compiler-only approach is weakly preferred, but adding a throwaway interpreter is acceptable.

### Open questions before implementation

#### Robot:

The followups above resolve the major design questions (lists-as-library, no restrictions on macros, leak-OK, iterative-by-end-of-phase-2, compiler-only preferred). Three concrete implementation questions remain before step 2 (quote) can begin — they all revolve around the *representation* macros operate on, which ripples through everything after:

**1. AST nodes vs. cons cells — same type or two types?**

The compiler currently uses a `Node` tagged union (`NODE_INT`, `NODE_SYM`, `NODE_STR`, `NODE_LIST` with a `Node**` items array). For macros, two options:

- **(a) Unify**: replace the `Node**` array with cons cells. The AST *is* a list. Every `first`/`rest` call on AST works directly. But it's a non-trivial refactor of the existing compiler — the entire reader, `emit_*` functions, and `Node.items[i]` access all change.
- **(b) Keep both**: `Node` stays for the compiler's internal use; cons cells are a separate library type; macros receive and return cons-cell lists, with conversion at the macro boundary.

(a) is more Lisp-idiomatic and avoids the impedance mismatch. (b) is less invasive but means `(first some-ast-form)` either doesn't work or requires an implicit conversion. I lean (a) — the current `Node.items[]` array is already a thin wrapper around "linked list of children."

**2. `(compile-time …)` execution mechanism for phase 2.**

Given "compiler-only weakly preferred, throwaway interpreter acceptable" — attempt the JIT path first (LLVM ORC, reusing `emit_node`), or start with a tree-walking interpreter over the AST and defer JIT? The interpreter is probably a week of work; the JIT is probably a month, but matches the long-term target and avoids a throwaway implementation.

**3. Macro return protocol.**

When a macro function returns, how is the result spliced back? The simplest contract: macro is `(defmacro name (args…) body)`, body returns a value of whatever type cons-cell lists are, and the compiler substitutes that value for the call site before re-dispatching. But this requires the macro return type to be known to the compiler at the call site. Is `defmacro` a distinct special form from `defn` (with fixed return type, compile-time-only), or just `defn` flagged as macro?

Answering (1) unblocks (3); answering (2) is independent. Once these three are settled, steps 2–5 in the implementation order become mechanical.

#### Designer:

1. Unify AST nodes with cons cells. Manipulating the AST at compile time is the core lispiness value that Nucleus is trying to create. Early implementation details must not constrain the later design; refactoring the compiler is always OK during these early phases.

2. Attempt the JIT approach now.

3. Macros return our unified cons/node unless that proves unworkable.

#### Robot:

Each answer settles direction but opens a concrete sub-question before implementation can start:

**On (1) unify:** The unified type needs a layout. Classical cons is `(car, cdr)` — two pointers. Atoms (int/sym/str) are distinct from cells: `(a b c)` is `cons(a, cons(b, cons(c, nil)))` where `a b c` are atom values in car slots. So "unified" really means "one graph built from cons cells pointing to atoms or other cells." Two sub-questions:

- **1a.** Is the atom type folded into the cell (every cell has a kind tag + either atom-data or car/cdr), or are atoms a distinct allocation that cells point to? Folding is more compact, one allocation per thing. Separate is cleaner but doubles allocation count.
- **1b.** Where does source line info live? Every `Node` currently carries a line number for error messages. On cons cells, do we tag every cell with a line, only the list-head cell, or only atoms? Classical Lisp discards line info; we probably can't since our errors are `file:line:` style.

**On (2) JIT now:** "JIT" has two plausible shapes in our world:

- **2a.** Real in-process LLVM via the C API (`LLVMOrcXXX`). Links `libLLVM`, significant new dependency, matches the long-term vision.
- **2b.** Shell out to `clang` to produce a shared object into a temp file, `dlopen` it, call the symbol. Uses our existing `clang file.ll` pipeline, far simpler, works today, but it's "JIT" only in a loose sense.

`design/stage1-self-host.md` line 21 explicitly says "No LLVM C API" — does the move to real JIT relax that, or do you want the `dlopen` shape for phase 2?

**On (3) macros return unified:** Return type is settled. The *argument* side is still open:

- **3a.** Classical Lisp: macro args are passed unevaluated as cons structure. But Nucleus is typed — do macro parameters get implicit type "cons/node" by virtue of being declared in `defmacro`, or do they need explicit `:node` annotations?
- **3b.** Is `defmacro` a new special form, or is it `defn` with a flag? New form is clearer; flagged `defn` is less machinery.
- **3c.** How does the compiler know to expand rather than call? It needs a macro registry consulted at every list-head dispatch. Confirm: a single global table indexed by symbol name, populated by `defmacro` processing at top-level?

Once these six (1a, 1b, 2, 3a, 3b, 3c) are settled, implementation is mechanical.

#### Designer:

1a. Separate is fine. Let's not prematurely optimize the compiler.

1b. Tag every cell, at least for now.

2. It's fine to make the compiler depend on libLLVM.

3b. `defmacro` is a new special form.

3c. A single global table is fine at this phase.

#### Robot:

The framing of 3a had a false premise. I said "macro args are passed unevaluated as cons structure," but atoms like `5` aren't cons cells — they're leaves. Under our unified design, though, `5` is still a *node*: one with `kind=INT` and an `i64` field. Same as how `x` is a node with `kind=SYM` and a string field, and `(+ 1 2)` is a cons cell. The macro body inspects the tag to figure out what it got.

So every macro parameter has the *same* type regardless of what was written at the call site: always `node` (our unified cons/atom type). That uniformity is exactly what makes typing trivial — there's only one possibility, so the param type is either implicit (no annotation needed, `defmacro` knows) or a redundant `:node` for consistency with `defn`. No type inference or call-site-dependent typing required.

The macro author extracts the atom's value explicitly when they need it: `(. arg i)` for an INT node, `(. arg s)` for a SYM/STR node, etc. That's the price of reified syntax, and it's paid uniformly.

3a collapses to a purely stylistic choice: annotate or not. Leaning implicit (less noise), matching how Common Lisp / Scheme avoid annotations in `defmacro` headers.

### Suggested implementation order

Given the dependencies resolved above, the real ordering is:

1. ~~**`cond`** — no prerequisites, immediate quality-of-life improvement, good warmup~~ done
2. ~~**AST unification** — internal refactor: replace `Node.items[]` arrays with cons cells (`car`/`cdr`/`line`). Atoms remain a separate allocation per 1a. `null` is the empty list. No user-visible language change; every test must still pass. Prerequisite for everything below.~~ done (stage1.ll == stage2.ll fixed-point holds; all 13 tests pass)
3. ~~**`quote` and `'`** — hardcode `'x` → `(quote x)` in the reader; add `quote` as a special form that evaluates to its argument as a node at compile time.~~ done (`'x` expands in the reader; `quote` emits private Node-struct globals — `{i32 kind, i32 line, i64 i, ptr s, ptr car, ptr cdr}` — and yields a pointer to the root. Runtime-visible only for now; will be reused by the JIT in step 6.)
4. ~~**List manipulation primitives** — `cons`, `first`, `rest`, `append` as Nucleus functions over the unified cons/node type. `list` is a convenience wrapper over `cons`.~~ done (definitions live in `lib/list.nuc`; `examples/list.nuc` exercises them; a `load`/import mechanism is deferred, so consumers currently inline the definitions). `list` deferred until quasiquote lands — `(list a b c)` is just `` `(~a ~b ~c) ``, so waiting for step 5 avoids duplicate work.
5. ~~**Quasiquote and splicing** — `` `x ``, `~x`, `~@x` as hardcoded reader shortcuts for `quasiquote` / `unquote` / `unquote-splice`, with special-form support for each.~~ done. Atoms and static sublists expand to private Node globals (same as `quote`). Unquoted expressions splice runtime values. Unquote-splice calls the builtin `@__append`. When any of these are used the compiler emits `@__cons`/`@__append` LLVM IR helpers into the output module — no link-time dependency required.
6. ~~**libLLVM JIT + `compile-time` special form**~~ done. `(compile-time body…)` executes forms at compile time via LLVM ORC LLJIT. Top-level forms (`defn`, `defstruct`, `include`, etc.) are processed as declarations; expression forms are wrapped in a unique `@__compile_time_main_N` function that runs in-process. The JIT is lazily initialized (one shared LLJIT instance per compiler invocation). CT output goes to stderr so it doesn't corrupt the IR emitted to stdout. `(include llvm)` exposes the LLVM C API; `(include unistd)` exposes `dup`/`dup2`/`close`. The `funcall-void` special form was added to call function pointers with void signatures (needed by the CT executor). Fixed-point holds; all 16 tests pass.
7. ~~**`defmacro`**~~ done - new special form. Body runs via the JIT; result is a node that replaces the call site. Iterative expansion with a hardcoded recursion bound (~1024). Unhygienic, with `gensym`. Single global macro registry.
8. **Use macros to simplify the compiler** — Now that `defmacro` works, a standard library of macros can be written in Nucleus and used to clean up the compiler's own source. The macros below are listed in implementation order — each group depends on the group above it. **Group 1–5 macros implemented; compiler source updated.** `cond` now appears only inside macro bodies and the multi-way top-level dispatch; all single-branch guards use `when`, binary conditions use `if`.

   **Group 1 — Binary and one-armed conditionals** (no dependencies; immediate payoff)

   - `if` — `(if test then else)` expands to `(cond test then true else)`. The compiler currently has `cond` as the sole conditional builtin; `if` was removed early to keep the core small. Restoring it as a macro reclaims the familiar two-branch form for the many places in the compiler where exactly one alternative exists. Without this, every binary choice requires the noise of the `true` fallthrough arm.

   - `when` — `(when condition body...)` expands to `(cond condition (do body...))`. One-armed conditional: "do this if true, nothing otherwise." Already written in `examples/defmacro.nuc`; needs to move into a standard library file consumed by the compiler itself. The compiler has dozens of guard-and-continue patterns (`cond (< nargs 2) (die-at ...)`) that read more clearly as `(when (< nargs 2) (die-at ...))`.

   - `unless` — `(unless condition body...)` expands to `(cond (not condition) (do body...))`. Negated `when`. Common in the compiler for "proceed unless something is wrong" guards. Implemented alongside `when`; both are trivial once `if` exists.

   **Group 2 — N-ary boolean operators** (depends only on Group 1)

   - `and` (n-ary) — `(and a b c ...)` expands recursively to `(and a (and b c ...))`. The built-in `and` is a strict 2-arg short-circuit operator because `emit-short-circuit` enforces `(node-len cc) == 3`. A macro wrapper allows n-ary calls by nesting. This unblocks compound conditions like `(and (>= i 0) (< i len) (not= p null))` that currently require nesting by hand. The base case `(and a b)` falls through to the built-in.

   - `or` (n-ary) — same approach as n-ary `and`. Base case `(or a b)` falls through to the built-in.

   **Group 3 — Iteration** (depends on Group 1; `dolist` also depends on list primitives from step 4)

   - `for` — `(for (var:type init) test step body...)` expands to a `let`+`while` combination:
     ```
     (let (var:type init)
       (while test
         body...
         step))
     ```
     The compiler is full of the pattern `(let (i:i32 0) (while (< i n) ... (inc! i)))`. The `for` macro collapses this to `(for (i:i32 0) (< i n) (inc! i) ...)`, making the loop variable, bound, and increment visible at a glance. The step expression is placed at the end of the body so `return`/`continue` semantics are natural.

   - `dotimes` — `(dotimes (i:i32 n) body...)` expands to `(for (i:i32 0) (< i n) (inc! i) body...)`. Specialises `for` for the overwhelmingly common counted loop from 0 to n−1. The compiler has roughly 20 such loops — `dotimes` would replace all of them.

   - `dolist` — `(dolist (x:ptr list) body...)` expands to a `while` loop that walks a cons-cell list via `(first ...)` and `(rest ...)`. Requires the list primitives from step 4. Useful for any macro or compiler pass that iterates over a node list.

   **Group 4 — Mutation helpers** (depends on `gensym`, already available)

   - `swap!` — `(swap! a b)` introduces a gensym'd temporary and emits:
     ```
     (let (tmp:T (gensym))
       (set! tmp a)
       (set! a b)
       (set! b tmp))
     ```
     Because gensym'd names cannot be used as typed `let` binding names (the `sym:type` token is read as a single atom — see `context/local.md`), this macro requires the typed temp to be spelled out explicitly or the type to be inferred — which means `swap!` may be deferred until type inference exists, or implemented with an explicit type parameter: `(swap! a b :i32)`.

   - `push!` — `(push! val head)` expands to `(set! head (cons val head))`. Builds a cons list by prepending. Depends on `cons` from step 4.

   **Group 5 — Predicates** (no dependencies; can be added any time)

   - `zero?` — `(zero? x)` → `(= x 0)`. Reads more clearly than the comparison form in boolean contexts.
   - `null?` — `(null? x)` → `(= x null)`. Replaces the pervasive `(= foo null)` null-checks throughout the compiler.
   - `pos?` / `neg?` — `(pos? x)` → `(> x 0)`, `(neg? x)` → `(< x 0)`. Lower priority; add if the compiler has enough uses to justify them.

   **Group 6 — Threading** (depends on quasiquote/splicing for the recursive expansion)

   - `->` (thread-first) — `(-> x (f a b) (g c))` expands to `(g (f x a b) c)`. Each form threads the previous result in as the *first* argument. Useful for chains of transformations where the data flows left-to-right: `(-> node (cast *Node) (. kind) (= NODE-SYM))` instead of `(= (. (cast *Node node) kind) NODE-SYM)`.

   - `->>` (thread-last) — `(->> x (f a) (g b c))` expands to `(g b c (f a x))`. Threads as the *last* argument. Common when the interesting value is a list being processed by higher-order operations.

   The threading macros require recursive quasiquote expansion to build up the nested call. They are non-trivial to implement but have a large readability payoff for the deeply-nested cast chains that appear throughout the compiler's emit functions.

   **Ordering summary**

   All Group 1–3 macros should be written first and the compiler source updated to use them before moving on. Group 4–6 are incrementally useful but the compiler can ship without them. The suggested commit order:

   1. `if`, `when`, `unless` (one commit; update all call sites in `nucleusc.nuc`)
   2. n-ary `and` / `or` (one commit; update compound conditions)
   3. `dotimes` and `for` (one commit; replace all indexed while loops)
   4. `dolist` (depends on step-4 list primitives being available in the compiler)
   5. Predicates (`zero?`, `null?`) — low cost, add alongside any of the above
   6. Threading macros (`->`, `->>`) — done
   7. `push!`, `swap!` — deferred until a clear need arises in the compiler or stdlib

   After each group, run `make test` and `make bootstrap` to verify the fixed-point holds.

#### Designer:

Threading macros are particularly useful. Racket has a version where the threaded value is in position 1 by default, but can be placed elsewhere arbitrarily with the placeholder `_`. Clojure has `as->`, which binds a symbol to the threaded value.

