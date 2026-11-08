# Storage-class attributes: a plan (deferred)

Asked for by the nuc-lua port's ISSUE-045, ruled 2026-11-08: write up a plan to support
storage-class attributes, defer the implementation. Stage 14's
[attributes.md](../stage14/attributes.md) built the keyword-attribute slot and
`:volatile`, reserved `:thread-local`, and only sketched `:static`, `:align`,
`:section` and `:weak` (its §6). This plan turns the `:static` sketch into a design, and
places the other three beside it. **Status: plan only. Nothing here is built.**

## 1. The case that needs it

`lvm.c` dispatches through

```c
static const void *const disptab[NUM_OPCODES] = { &&L_OP_MOVE, &&L_OP_LOADI, … };
```

which C compiles to one read-only table in `.rodata`, its entries `blockaddress`
constants. Nucleus has `label-addr` and `goto-ptr`, but the table has nowhere to live:

- a function can't hold an array binding (`(array T N)` is a storage type, valid only in
  a `defvar` or a field);
- there is no function-scope static;
- a global's initializer can't name a label, since a label belongs to a function.

The port fills a module-level `(defvar- vm-disptab:(array ptr 85))` on the first call.
That costs a test per call and races when two threads make their first Lua call at once.
An `alloca`'d table filled per call made a metamethod-heavy benchmark 1.28 times stock.

## 2. Decisions proposed

### 2.1 `:static` on a `let` binding

```lisp
(let (:static disptab:(array ptr 85) (array ptr (label-addr L_OP_MOVE) …)) …)
```

- **Storage.** One internal global per binding, named `@<fn>.<name>.static.N` so two
  statics of one name in one function stay apart. Lexical visibility only: the binding
  is in scope where a `let` binding would be, and nothing else can name it.
- **Initializer.** Constant only, under the `defvar` constant grammar (`defvar-init-ir`),
  plus one addition: `(label-addr L)` for a label of the *enclosing* function lowers to
  `blockaddress(@fn, %L)`. No once-guard is ever emitted, which is the point: the table is
  data, not code. A run-time initializer is refused with the `defvar` soft-path message
  turned into an error: "a :static binding's initializer must be constant".
- **`:const` with it** (`(:static :const disptab …)`) makes the global `internal constant`,
  C's `static const`, and refuses `set!` into it through `readonly-global`, as
  `defconst` aggregates already are. Without `:const` it is `internal global`.
- **Arrays.** `:static` is the one `let` position where `(array T N)` is legal, since the
  storage is a global. The binding reads as the decayed `&T`, as an array `defvar` does
  (`array-decay`, shared with `node-type`).
- **Escape analysis.** The address of a static is not frame storage: it carries no
  frame taint and may be returned or stored anywhere, like `&global`.
- **Drop.** Never dropped: process lifetime, as the arena-global idiom.
- **Generics.** A static inside a template function is one per *instance*: the stamp
  emits its own `@<instance>.<name>.static.N`. That is C++'s rule and the only one that
  types.
- **Closures.** A `fn` literal that names an enclosing static captures nothing: it names
  the global directly.
- **REPL.** A redefined function gets a fresh static, like a `defvar` of a new type. The
  old function, if still referenced, keeps its own.

`label-addr` in a static's initializer needs the labels' names before the body is
emitted. The emitter already collects a function's labels for `goto` (forward jumps), so
the initializer is rendered after the body, when every `%L` exists. The global's line is
written to the module stream after the function's `define`, which LLVM accepts in any
order.

### 2.2 `:align N`, `:section "name"`, `:weak` on `defvar` (and `:static`)

Valued attributes in the existing registry (`parse-decl-attrs`). Each is one token on the
global's line (`, align N`, `, section "name"`, `weak` linkage) and one in the `.nuch` and
C header exports. `:weak` is ISSUE-015's half: a weak definition the user asks for, beside
the default `weak_odr` of an imported file's `defn`, which stays as it is. The `defn` head
does not take these. `fn-attr` covers functions (AVR-5).

### 2.3 What stays out

- `:thread-local`, still blocked on a threading stage (attributes.md §5).
- `register`, which LLVM ignores.
- File-scope `static`. `defvar-`/`defn-` already mean that.

## 3. Phases

- **SC-1: `:static` locals with constant initializers.** The registry row, the `let`
  binding path (`emit-let` and `node-type-block`, lockstep), the global's emission and
  naming, `:const`, escape exemption, the array permission. Tests: a counter in a static,
  a static array read as `&T`, a refused run-time initializer, a template instance per
  stamp.
- **SC-2: `label-addr` in a static's initializer.** Deferred rendering after the body,
  `blockaddress` lowering, a refusal for a label of another function. Test: a threaded
  dispatcher in the shape of `luaV_execute`, its table in `.rodata` (`llvm-objdump`
  finds no store to it).
- **SC-3: `:align`, `:section`, `:weak`** on `defvar` and `:static`, through `.nuch` and
  `--emit-cheader`.
- **SC-4: the port.** `vm.nuc`'s `vm-disptab` becomes a `:static :const` binding in
  `vm-execute`. The first-call fill and its race are gone.

## 4. Open questions for the owner

1. Is `:static` on a `let` the spelling, or should a function-scope static be its own
   form (`(static disptab:… init)` in a body)? The slot is attributes.md's decision, so
   this plan uses it.
2. Should a `:static` without `:const` be allowed at all? C allows a mutable function
   static, and the port has no use for one.
