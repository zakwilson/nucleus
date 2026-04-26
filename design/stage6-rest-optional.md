# `&rest` and `&optional` for `defn`

`defmacro` accepts `&rest` parameters (see `docs/builtins.md`); `defn`
does not. This is item "&rest / &optional for defn" deferred from
[stage6-plan.md](stage6-plan.md). Discussed in
[stage6-cleanup.md](stage6-cleanup.md) under "Variadic functions."

The space has three reasonable implementations with different cost
models, so the deferral is a real design call rather than just an
implementation oversight.

## Designer:

(Not yet written.)

## Robot:

### Three flavors

1. **Macro-style `&rest`** — the rest args are collected into a `Node`
   cons list at the call site, by a synthesized macro expansion.
   Zero runtime cost when the call is fully expanded at compile time.
   Cost: the function isn't directly C-callable; passing it as a
   function pointer doesn't carry the "I have rest args" expectation,
   so it can only be called through Nucleus call sites that the
   compiler has rewritten.

2. **C varargs (`...`)** — the function uses the platform vararg ABI
   (`va_list` etc.). Calls from C work, types are erased, the callee
   has to know how many args it got. Per-call cost: the va_arg
   prologue. Worth keeping reserved for actual C-interop functions
   (e.g. wrappers around `printf`) and not used as the default
   Nucleus rest-arg mechanism.

3. **Named `&optional`** — fixed-arity at the ABI level; the *call
   site* fills in defaults for omitted trailing args. Implemented as
   a rewrite at the caller, not a flag in the callee. No runtime
   cost when defaults are constants.

These are not mutually exclusive. Common Lisp has all three.

### Recommendation

Ship `&rest` first, as macro-style. Defer `&optional` to a follow-up.
Keep C-style `...` for `extern` declarations only — already works.

`&rest` is the higher-impact feature (collection-of-args is a much
more common pattern than "this one trailing arg is optional"), and
the macro-style implementation is the cheapest one available in
Nucleus today: `defmacro` already does it, and the codegen path for
"build a Node list at the call site" already exists.

### `&rest` design

Source surface, mirroring `defmacro`:

```
(defn print-each:void (prefix:ptr &rest args:ptr)
  (while (not (nil? args))
    (printf "%s%s\n" prefix (cast ptr (car args)))
    (set! args (cdr args))))
```

`args` inside the body is a `*Node` (cons-list head). The type
annotation `:ptr` documents what each *element* is — but it's not
enforced, just like macro `&rest` parameters.

**Call-site rewrite.** A call `(print-each "> " "a" "b" "c")` is
rewritten to `(print-each "> " (list "a" "b" "c"))` before codegen.
The rewrite happens after macro expansion, before type checking, in
a new pass that fires on calls to functions with `&rest` in their
declared signature.

**ABI.** The compiled function takes a fixed arity: positional
parameters as-is, plus one trailing `*Node` for the rest list. So
`print-each` compiles to a two-arg function; the rewrite ensures
every call site supplies exactly two args.

**C interop.** Functions with `&rest` cannot be called from C
directly without manually constructing a `Node` list. Document this
in `docs/builtins.md`. If a function needs both — be callable from
C and accept variadic input — write two: a C-callable `...` shim
and a Nucleus `&rest` function it forwards to.

**Function pointers.** Taking a pointer to a `&rest` function gives
a pointer to the fixed-arity compiled form. Calling through the
pointer requires manually constructing the rest list. Document.

### `&optional` (deferred follow-up)

Sketch only — not blocking the `&rest` work.

```
(defn greet:void (name:ptr &optional (greeting:ptr "hello"))
  (printf "%s, %s\n" greeting name))
```

Call-site rewrite: `(greet "world")` → `(greet "world" "hello")`. The
default expression is evaluated *at the call site* (the Common Lisp
default), so `(defn next:i64 (&optional (n:i64 (now-counter))) ...)`
gets a fresh counter per call. Implement after `&rest`; the rewrite
infrastructure is shared.

Edge case: `&optional` parameters with no default. Decision: require a
default. Without one, the parameter is morally `&rest`-of-zero-or-one
and that's a different feature.

`&rest` and `&optional` can coexist in one signature, with
`&optional` first: `(defn f (a &optional b &rest c) ...)`. The
rewrite fills in `&optional` defaults, then collects everything left
into the `&rest` list.

### Test plan

- `(defn sum:i64 (&rest args)
     (let (total:i64 0)
       (while (not (nil? args))
         (set! total (+ total (cast i64 (car args))))
         (set! args (cdr args)))
       total))`
  — `(sum 1 2 3)` → 6. `(sum)` → 0.
- `&rest` after positional: `(defn fmt:ptr (template:ptr &rest fields)
   ...)` — works with zero or more fields.
- Function pointer: `(let (fp:ptr sum) ...)` documents that calling
  `fp` requires manual list construction.
- Self-host pass.

### Completion criteria

- `defn` accepts `&rest` with the same surface as `defmacro`.
- Variadic-arithmetic macros (already shipping in `lib/varmath.nuc`)
  could in principle be rewritten as functions, demonstrating
  feature parity. Not required, but a useful smoke test.
- The compiler self-hosts and the test suite passes.
- `docs/builtins.md` documents `&rest` for `defn`, including the
  C-callability caveat.
