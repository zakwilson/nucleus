## Post-toy features

Now that Nucleus is self-hosted (stage-1 == stage-2, all tests green), these are the features that move the language from "compiler that can compile itself" to "language worth writing programs in."

The ordering here is deliberate: list manipulation and quoting are prerequisites for macros, and macros are the prerequisite for everything else becoming ergonomic. Get these three right and most future features can be built *in* Nucleus rather than bolted onto the compiler.

### cond (implemented)

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

**Commentary:** In practice, `cond` is straightforward to implement as a chain of conditional branches in LLVM IR — each test-result pair becomes a compare-and-branch to either the result block or the next test. This is the same structure you'd get from nested `if`s, just generated from a flat list of pairs. The implementation complexity is comparable to `if`, so `cond` as the builtin with `if` as a macro (once macros exist) is viable. In the interim, `cond` can be a special form alongside `if` — the compiler already handles `if` with two branches, and `cond` is a loop over pairs emitting the same pattern. This is a good candidate for the *first* feature to add: it requires no new infrastructure and immediately improves the compiler's own source (the `emit_node` dispatch is full of nested `if`s).

**Status:** Implemented. `if` has been removed; `cond` is the sole conditional builtin. `if` will return as a macro once the macro system exists. The nested if-else chain in the top-level dispatch (formerly 7 nested `if`s) is now a single flat `cond`, demonstrating the readability improvement.

### list manipulation

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

**Commentary:** This is where the design gets interesting and deserves careful thought. The current compiler represents the AST as C-style structs allocated from an arena. For macros to manipulate code, we need actual list values at compile time. There are two paths:

1. **Compile-time interpreter.** The compiler interprets macro bodies at compile time using a list representation that exists only during compilation. The compiled output never contains list operations unless the program explicitly uses them at runtime. This is the traditional Lisp approach and aligns with "zero mandatory runtime overhead."

2. **Lists as a runtime type.** Add cons cells as a first-class heap type, available at both compile time and runtime. Simpler to implement but adds a runtime type that C doesn't have, moving away from "drop-in substitute for C."

Path 1 is more aligned with the design principles (zero overhead, small core), but it means the compiler needs an embedded interpreter before macros work — a significant implementation effort. Path 2 gets macros working sooner but at an architectural cost.

The quoting syntax also interacts with reader macros (mentioned in overview.md). If `'` is a reader macro for `quote`, then the reader macro system needs to exist before quoting works, which pushes the dependency chain further back. Alternatively, `'` can initially be hardcoded in the reader (as `;` comments already are) and later generalized to the reader macro system.

Suggested ordering: hardcode `quote` and `'` in the reader → implement the compile-time list representation → add `cons`/`first`/`rest`/`append` as compile-time builtins → implement quasiquote/splicing → then macros become possible. `list` is just a convenience wrapper over `cons`.

### macros

Macros are what makes Nucleus special. By making the full power of the language available to manipulate code during compilation, abstractions without runtime overhead are possible in Nucleus that are impossible in other languages.

**Commentary:** The macro system design needs to address several concrete questions:

**Expansion model.** Do macros expand in a single pass (top-down, each macro sees unexpanded code) or iteratively (expand until no more macros remain)? Single-pass is simpler but means macros can't compose as freely. Iterative is more powerful but needs a termination check. Most Lisps use iterative expansion. Given the "worse is better" principle, starting with single-pass and upgrading later is reasonable.

**Hygiene.** Traditional Lisp macros are unhygienic — they can capture or shadow bindings in the expansion site. Scheme-style hygienic macros avoid this but add significant complexity. For a systems language where the programmer is expected to manage memory manually, unhygienic macros (with a `gensym` facility for when you need fresh names) are the pragmatic choice. This matches Common Lisp's approach.

**Compile-time environment.** Macros need to call functions at compile time. This means the compiler must be able to *execute* Nucleus code, not just emit IR for it. The compile-time interpreter from the list manipulation section is the foundation here. The scope of what's available at compile time matters: can macros call `malloc`? Open files? The minimal answer is list manipulation plus arithmetic plus string operations — enough to construct and transform AST fragments. Something like Common Lisp's `eval-when` (already mentioned in overview.md) would let the programmer control what's available at compile time vs. runtime.

**What macros unlock.** Once macros work, many things currently in the compiler or missing entirely become expressible in library code:
- `cond` (if we didn't already add it as a special form)
- `let` bindings
- Pattern matching / destructuring
- `for` loops / iteration forms
- `defmethod` / method dispatch on struct types (relates to the compile-time dispatch musings)
- `set!` as a macro that dispatches on its target (as explored in musings.md)
- Type-checked struct accessors that look like function calls

This is the payoff: each macro replaces what would otherwise be a new special form in the compiler. The compiler stays small and the language grows through libraries.

### Suggested implementation order

Given the dependencies:

1. **`cond`** — no prerequisites, immediate quality-of-life improvement, good warmup
2. **`quote` and `'`** — hardcoded in the reader, introduces quoted values to the language
3. **Compile-time list representation** — cons cells, `first`, `rest`, `cons`, `append` as compile-time builtins
4. **Quasiquote and splicing** — enables readable macro bodies
5. **`defmacro`** — single-pass expansion, unhygienic, with `gensym`
6. **Use macros to simplify the compiler** — `cond` becomes a macro on `if`, add `let`, etc.
7. **Reader macros** — generalize the hardcoded `'` to user-defined reader transformations
8. **`eval-when` / compile-time control** — fine-grained control over what's available when

Each step is independently useful and testable. Steps 1-2 are small. Steps 3-5 are the heavy lift. Steps 6-8 are the payoff and polish.
