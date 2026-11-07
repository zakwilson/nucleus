# Variadic functions defined in Nucleus

**Status:** built 2026-11-07 on `lua-bugfixes`, with Q1–Q9 ruled as recommended
(tentatively, by the project owner). Written for the Lua port (`nuc-lua`,
`PROMPT.md` §6.4). The language docs are in `docs/types.md`, "Variadic functions".

**As built, against this document:**

- **`va_arg` is open-coded on x86-64 too.** §3's "Correct" for x86-64 was measured
  through `llc` at its default level. Nucleus defaults to `-O0`, and there LLVM's
  `va_arg` of a `load`ed list crashes: the fast register allocator reloads a spill
  it never wrote, because the custom inserter's new blocks reuse a vreg marked
  killed. Both aggregate classes now use `emit-va-next`, in `select`s rather than
  blocks so no enclosing `phi` has to know. The cursor class keeps `va_arg`, which
  passed at `-O0` and `-O2` on riscv64. §8's rejected "open-code on every target"
  is half-taken.
- **Q6's diagnostic never shipped.** AArch64 works, from the same code as x86-64.
- **Q7 went further than recommended.** `musttail` forwarding works in the JIT, on
  x86-64, so a variadic `defn` can be redefined at the REPL, including with an
  `sret` return. Only `trace` refuses one, since its shim acts after the call.
- **VA-1 to VA-5 are one commit**, because the open-coding rearranged VA-3 and VA-5.
- **Q2:** the uses were tests only. `extern-decl` stays, to word the error.
- **Q4 is approximate.** `consume-valist-arg` stands down inside any branching
  form, so a second pass in a loop or in only one arm isn't caught. It sees a bare
  symbol passed through the direct or indirect call path, not an overloaded one.
- **`cheader`:** a `va_list` struct field imports as a pointer, as it always did. It
  wasn't given the refusal §6 asks for.

## 1. Summary

Nucleus can call a C variadic but can't define one or read a `va_list`. This
proposes the smallest addition that closes the gap, for the C ABI only:

```lisp
(defn lua_pushfstring (L:ptr:lua_State fmt:CStr :varargs ap):CStr
  (return (pushvf L fmt ap)))

(defn pushvf (L:ptr:lua_State fmt:CStr ap:VaList):CStr
  ; ...
  (let (n:i32 (unsafe/va-arg ap i32))
    ...))

(declare luaL_error (L:ptr:lua_State fmt:CStr :varargs):i32)
```

- `:varargs ap` in a `defn` makes it a real C variadic. `ap` is bound for the whole
  body, and `va_start` and `va_end` are the compiler's job.
- `:varargs` in a `declare` or a function-pointer type gives the flag a spelling. It
  has none today.
- `VaList` is a new built-in type that matches C's `va_list` on every target.
- `(unsafe/va-arg ap T)` reads the next argument, for a restricted set of `T`.
- `(va-copy ap)` copies a list, in a `with`.

This isn't a new way to write Nucleus APIs. `:rest`, macros and `fstr` remain the
answer there, for the reason Stage 17 C1 recorded: `fmt-*` wrappers whose arity had to
match their format string made a cold-path mistake a segfault, and replacing 636 call
sites with `fstr` made arity a macro-expansion fact (`src/format.nuc`). `va-arg` is that
same hazard, and it is here only because a foreign ABI demands it.

## 2. What exists today

All measured on 2026-11-07 with `lua-bugfixes` built against LLVM 19.1.7, on x86-64 Linux.

### 2.1 The flag is already there

`variadic` on a `TY-FN` type is real and well served. `cheader` sets it from a header,
and these already honour it: `call-arity-ok`, `abi-args-varargs` (RISC-V's register
rule), `vararg-promote`, `fn-link-sig`, `fn-type-spelling`, `generic-register-method`,
method resolution, the `defcast` guard, and the REPL's declaration printer.

What's missing is everything on the **defining** side, and any **spelling**:

| Want | Today |
|---|---|
| `(declare f (a:i32 ...):i32)` | `error: unknown type: ...` |
| `(defn f (a:i32 ...):i32 …)` | `error: defn: missing :type on param '...'` |
| `(declare f (a:i32 :rest):i32)` | Refused: `declare the fixed parameters only` |
| Spell a variadic function-pointer type | No way: `is-va` in `parse-type-from-node` is never set. One arriving from a C typedef does work (`(funcall p "%d %f\n" 7 1.5)` through a header's `vfn`) |
| Hold a `va_list` | `va_list` is mapped to `ptr` (`cheader.nuc`), so `(sizeof va_list)` is 8 where C says 24. Passing one through to `vprintf` emits correct IR, but no Nucleus code can create one |

`docs/compiler.md`'s arity table says an indirect call takes "exactly `num-params`",
which the working `vfn` call above contradicts for a variadic pointer.

Note that in the compiler "variadic" means two things. `Type.variadic` and
`Method.variadic` are the C flag. A macro definition's `variadic` means `:rest`.

### 2.2 Bug: the `declare` route skips the variadic call path

`docs/compiler.md` documents declaring a C variadic by its fixed parameters and letting
"the extra arguments ride the call site", and says in the same passage that arguments
past the fixed prefix take C's default promotions. They don't. The tail path in
`emit-call-with-args` is gated on `(ft0 'variadic)`, and `emit-nuch-declare-import` sets
that to 0 and sets `extern-decl` on the symbol instead. So the arity check admits the
extra arguments, and everything after it treats them as fixed.

The same C callee (`va_arg` of `double`, `int`, `double`), reached both ways, with `(zero)`
just before the call so `%al` is 0:

```lisp
(let (n:i16 -300 x:f32 2.5)
  (zero) (show 1 1.5 n x))
```

| Route | IR | `-O0` | `-O2` |
|---|---|---|---|
| Header import | `call void (i32, ...) @show(i32 1, double 1.5, i32 %t6, double %t7)` | `d=1.5 i=-300 f=2.5` | `d=1.5 i=-300 f=2.5` |
| `declare` | `call void @show(i32 2, double 1.5, i16 %t4, float %t5)` | `d=1.5 i=65236 f=5.3e-315` | `d=2.6e-318 i=65236 f=1.2e-322` |

The narrow arguments aren't promoted (the Stage 16 defect in
[varargs-promotion.md](../stage16-ergonomics/varargs-promotion.md), still live on this
path). With no `...` at the call, the x86-64 caller doesn't set `%al` either, so it holds
whatever was left there, here the 0 from `(zero)`. That tells the callee to skip saving
the XMM registers, which fits the garbage `double` at `-O2`. Nothing warns. This is what
a Lua binding written with `declare` would hit on `(luaL_error L "%f" x)`.

### 2.3 What the workaround costs

Lua's public API has three variadics (`lua_pushfstring`, `luaL_error`, `lua_gc`) and one
`va_list` consumer (`lua_pushvfstring`). `va_list` also runs through internals:
`luaO_pushvfstring` and the `pushvfstring` macro. With no language support the port needs
a C file whose entry points walk the format with `va_arg`, decode each argument into an
array, and call Nucleus. That duplicates the format parser, adds a C object (`run-repl`
refuses one, and `run` falls back to building a binary), and leaves `lua_pushvfstring`,
which real C callers reach with a real `va_list`, unable to be Nucleus at all. The same applies to any C
library that takes a logging callback with a `va_list`.

## 3. What LLVM provides

LLVM has `llvm.va_start`, `llvm.va_copy`, `llvm.va_end` and the `va_arg` instruction. The
intrinsics work everywhere, but `va_arg` is not a complete implementation: clang open-codes
it per ABI. These are from LLVM 19.1.7. The compiler is routinely built on newer LLVMs, so
**re-measure before relying on this**.

| Target | `va_list` size / align | `va_arg` of scalars | Evidence |
|---|---|---|---|
| x86-64 Linux | 24 / 8 (array of one struct) | **Correct** | Ran: 12 `int`/`double` pairs, past both register files, called from C |
| aarch64 Linux | 32 / 8 (struct) | **Wrong answer, no error** | Ran under `qemu-aarch64`: exit 1, where the same test in C passes |
| riscv64 Linux | 8 / 8 (cursor) | **Correct** | Ran under `qemu-riscv64` |
| x86-64 Windows (gnu, msvc) | 8 / 8 (cursor) | Compiles | Not run |
| aarch64 Darwin | 8 / 8 (cursor) | Compiles | Not run |
| AVR | 2 / 1 (cursor) | Compiles | Not run |

On x86-64, past scalars:

| `T` in `va_arg ptr %ap, T` | Result |
|---|---|
| `{ i64, i64 }`, `{ double, i64 }` | **`llc` segfaults** |
| `x86_fp80` | Compiles, **wrong value** (42.0L read as `-9223372036854775808`) |
| `fp128` | Compiles. Not run |
| `float`, `i8` | Compiles. Meaningless in C: these never arrive as such after promotion |

Also measured:

- `llvm.va_end` emits no instructions on x86-64 Linux, aarch64 Linux, riscv64 and x86-64
  Windows.
- On x86-64, `va_start`, then `va_copy`, then `vsnprintf` over each list, called from C
  with `"%s=%d/%.2f"`, gives `x=7/2.50` and total length 16, so forwarding to a C `v*`
  function works.

## 4. Proposal

### 4.1 Surface

```lisp
(defn f (a:i32 fmt:CStr :varargs ap):i32 …)    ; define; binds ap:VaList
(declare f (a:i32 fmt:CStr :varargs):i32)      ; declare; no name
((fn i32) (CStr :varargs))                     ; function-pointer type
```

`:varargs` follows the marker convention of `:rest`, `:optional` and `:where`, and comes
last. It may be the only parameter, as C23 allows. It can't be combined with `:rest` or
`:optional`.

**`VaList`** is a built-in type, distinct from `ptr`. It may be a parameter type or a
binding made by `:varargs` or `va-copy`, and nothing else: not a field, a global, an array
element, a return type, a closure capture or a `sizeof` operand. Those are what would let
a list outlive the frame that owns it, which is undefined in C.

**`(unsafe/va-arg ap T)`** reads the next argument as `T`. Nothing checks the type or the
count, and reading past the end is undefined. That is the reason for the `unsafe/` prefix.

`T` must be a type the promotions leave alone:

| Admitted | Refused |
|---|---|
| `i32`, `ui32`, `Char`, `i64`, `ui64`, `usize`, `ssize`, `f64`, `ptr`, `ptr:T`, `?&T`, `CStr`, and on AVR `i16`/`ui16` | Narrower integers, `bool`, `f32`: they arrive promoted, so reading them is undefined in C. The message names the promoted type |
| | `&T`: nothing proves it non-null. Read `?&T` and narrow |
| | Structs, unions, arrays, `StrView`: see §3. A `StrView` passed in a variadic position already arrives as only its data pointer, so read `CStr` |
| | `f80`, `f128`: see §3 |

```
t.nuc:4: error: unsafe/va-arg: 'i16' arrives promoted to 'i32' -- read i32 and narrow it
t.nuc:5: error: unsafe/va-arg: a struct can't be read from a variadic list yet
```

**`(va-copy ap)`** yields a new list at the same position, bound in a `with`, which ends
it at scope exit. This also covers traversing a list twice, which C does with a second
`va_start`.

```lisp
(with (aq (va-copy ap))
  (vsnprintf null 0 fmt aq))
(vsnprintf buf n fmt ap)
```

**Calling.** A variadic `defn` is called exactly like an imported variadic: the fixed
prefix is checked and the tail takes the promotions. That path exists.

### 4.2 Lua, for scale

```lisp
(defn luaL_error (L:ptr:lua_State fmt:CStr :varargs ap):i32
  (luaL_where L 1)
  (lua_pushvfstring L fmt ap)
  (lua_concat L 2)
  (return (lua_error L)))

(defn lua_gc (L:ptr:lua_State what:i32 :varargs ap):i32
  ; ...
  (case what
    LUA_GCSTEP  (let (n:usize (unsafe/va-arg ap usize)) …)
    LUA_GCPARAM (let (param:i32 (unsafe/va-arg ap i32)
                      value:i32 (unsafe/va-arg ap i32)) …)))
```

`luaO_pushvfstring`'s eight conversions read `CStr`, `i32`, `i32`, `i64`, `f64`, `ptr`,
`ui64` and nothing, all of them admitted. Lua needs no aggregate, `long double` or AArch64
support, so VA-0 to VA-3 is enough for the port.

## 5. Lowering

**Definition.** `emit-defn` adds `...` to the `define`. The fixed parameters are lowered
as now. The entry block gets:

```llvm
%ap.list = alloca [24 x i8], align 16      ; target's size, at least its alignment
call void @llvm.va_start.p0(ptr %ap.list)
```

Each exit calls `llvm.va_end`, by treating `ap` as a compiler-owned `with` binding so
that `return`, `goto` and `defer` need no new code.

**`VaList` at the ABI.** Inside Nucleus a `VaList` value is always the address of the
list's storage, which is what the intrinsics and `va_arg` take. What crosses a call
depends on the target:

| Class | Targets | C passes | At a call | At entry |
|---|---|---|---|---|
| Aggregate | x86-64 SysV, aarch64 AAPCS | A pointer (array decay, or a large struct by reference) | Pass the handle | Use the incoming pointer as the handle |
| Cursor | riscv64, Windows, Darwin arm64, AVR | The cursor value itself | `load` the cursor, pass it | Spill to a slot; the slot is the handle |

Every class is one `ptr` in a register, so `abi-classify` is unaffected. Only the argument
and parameter paths need the rule.

This means passing a list down behaves differently by target. In the aggregate class the
callee advances the caller's list, and in the cursor class it doesn't. C calls the list
indeterminate after such a call, and §4.1's rule is the same: **passing a `VaList` consumes
it** (Q4).

**`unsafe/va-arg`** emits `va_arg ptr %handle, T` where §3 shows that's right. AArch64
needs an open-coded sequence like clang's `EmitAAPCSVAArg`: test `__gr_offs` or
`__vr_offs`, take the register save area or `__stack`, and bump. Until then, emit a
diagnostic on AArch64 Linux instead of the silently wrong instruction. That shape hasn't
been prototyped; the evidence that it's reachable is that clang's output passes the same
`qemu` test.

## 6. Compiler touch points

| Area | Change |
|---|---|
| Parameter parsing (`defn-params-to-types-at`, `defn-params-count`, the `emit-defn` walk, `reject-declare-marker`) | Recognize `:varargs`, count it out, set `variadic` |
| `parse-type-from-node` | Set `is-va`, the variable that already exists for this |
| `emit-defn` | `...`, the entry sequence, the hidden binding |
| Type system | `VaList`, `type-to-ir` = `ptr`, per-target size and class table beside `abi.nuc`, refusals |
| New forms | `unsafe/va-arg`, `va-copy` |
| `emit-call-with-args`, indirect path | `VaList` cursor rule. Tail handling unchanged |
| `emit-nuch-declare` | Write `:varargs` without the binder name, so a `.nuch` round-trips |
| `cheader` | Import `va_list` and `__gnuc_va_list` as `VaList` in parameters; refuse them elsewhere rather than the wrong size. `--emit-cheader` writes `...`, `va_list` and `<stdarg.h>` |
| `emit-fn-thunk`, REPL trace | Q7 |
| `resolve.nuc`, refactoring | The binder is a binding |
| `docs/` | `toplevel.md`, `types.md`, `compiler.md` (arity table, §2.2's passage), `builtins.md`, `special-forms.md`. Remove the entry from `design/deferred/overview.md` when done |

## 7. Interactions

- **`longjmp`.** A jump over a live list skips `va_end`, which is harmless where §3
  measured it, and C has the same exposure: `lua_pushvfstring` can raise a memory error
  while `luaL_error`'s list is live.
- **`with`, `defer`, `Drop`.** Unchanged. Copied lists use the ordinary `with` exit path.
- **Closures.** `fn`, `vfn` and `mfn` can't be variadic, since nothing needs it, and can't
  capture a `VaList`.
- **Generics.** A variadic `defn` can't be a template, have `:where`, or be a protocol
  method. See Q9 for overloads.
- **`:noreturn`, `:returns-twice`, `defn-`.** Compose as usual.
- **Inlining.** LLVM won't inline a function that calls `va_start`, so a variadic `defn`
  is always a real call.
- **Macros and `compile-time`.** The macro JIT's declaration path already handles variadic
  prototypes. A variadic `defn` called from JIT code should need no more than any other,
  but this hasn't been tested.
- **`defcast`.** The existing guard refuses a variadic conversion function.

## 8. Alternatives

- **Status quo, a C shim per project.** §2.3. It's what the port does until this is
  ruled on, and works, at the cost of a second format parser and of `lua_pushvfstring`.
- **Compiler-generated C shim.** It hides a C object in every such program's build, with
  the same `run-repl` limit, and doesn't reach the `va_list` consumer.
- **Hand-walk `__va_list_tag` in Nucleus.** It handles `va_list` on one target only, and
  `va_start` still needs the prologue to save the registers, which only a variadic
  `define` gets.
- **Use `:rest`.** It builds a `Node` list at each Nucleus call site, so it isn't C-callable.
  [stage6-rest-optional.md](../stage6-rest-optional.md) already reached this conclusion, and
  kept `...` for `extern` declarations. This proposal extends that to definitions, for the
  same C-only reason.
- **`va_start`, `va_end` as user forms.** They'd add a way to get it wrong and no power.
  The one thing this drops, restarting a list, is covered by `va-copy`.
- **Open-code `va_arg` on every target.** Not needed for v1. LLVM's `va_arg` was correct on
  two of the three targets that were run, and it's one code path to replace if that changes.

## 9. Questions for ruling

| # | Question | Recommendation |
|---|---|---|
| Q1 | Spelling: `:varargs ap`, or `...`? The reader takes `...` as a symbol, so either can be done | `:varargs`. It matches `:rest` and `:optional`, and there has to be a place for the binder |
| Q2 | Keep the open-tailed `declare`? | Fix it in VA-0 regardless. After VA-1, make extra arguments on a plain `declare` an error that names `:varargs`, since a `declare` can then say what it means. Pre-release, so the break is acceptable, but count the uses first |
| Q3 | Name of the read form | `unsafe/va-arg`. It's as unchecked as `unsafe/cast` |
| Q4 | Enforce "passing a `VaList` consumes it"? `Sym.moved` exists | Yes, for the same reason as `move`: a use after passing is target-dependent, the kind of bug that passes on the machine it's written on. `va-copy` is the way out |
| Q5 | Aggregates, `f80`, `f128` in `unsafe/va-arg` for v1? | Refuse. `llc` crashes or the value is wrong (§3), nothing needs them yet, and supporting them means open-coding each ABI |
| Q6 | Ship before AArch64 works? | Yes, with a diagnostic there, not the wrong instruction. Open-code it in VA-5 |
| Q7 | REPL redefinition: a thunk can't forward `...` | Refuse redefining a variadic `defn`, with a message, for now. `musttail` forwarding is possible but not target-independent, and hasn't been tried |
| Q8 | Restrict `:varargs` to C-facing functions? | No check, since `defn-` callbacks are legitimate. The docs steer Nucleus APIs to macros |
| Q9 | Can a variadic `defn` join an overload set? | No. Overloading mangles the symbol, which defeats the only reason to define one, and dispatch can't see the tail. An imported C variadic adopted into a generic stays as it is |

## 10. Plan

Each step is one commit, with `make test bootstrap`.

| Step | What | Needs ruling |
|---|---|---|
| VA-0 | Fix §2.2: past the prefix of an `extern-decl`, take the variadic path: promotions, `abi-args-varargs`, the `(…, ...)` call signature. Correct the docs | None |
| VA-1 | `:varargs` in `declare` and function-pointer types; `.nuch` round trip | Q1, Q2 |
| VA-2 | `VaList`, the size and class table, `cheader` import | Q4 |
| VA-3 | `:varargs` in `defn`, `unsafe/va-arg`, on the targets §3 shows correct; a diagnostic on the others | Q3, Q5, Q6, Q8, Q9 |
| VA-4 | `va-copy` | |
| VA-5 | AArch64 open-coded `va_arg` | Q6 |
| VA-6 | `--emit-cheader`, REPL handling, docs, drop the deferred entry | Q7 |

**Tests.** C is the oracle in each direction.

- C calling a Nucleus variadic past both register files, including `f32` and `i8`
  arguments that C promotes. Compare with the identical C callee.
- Nucleus calling that Nucleus variadic.
- Nucleus forwarding `ap` to `vsnprintf`; a C variadic forwarding its `va_list` to a
  Nucleus `VaList` parameter.
- `va-copy` traversing twice.
- A `sret` return plus a tail, and a struct-by-value fixed parameter plus a tail.
- Every refusal in §4.1, as a diagnostic golden.
- A `.nuch` round trip, an `--emit-cheader` round trip compiled by clang.
- riscv64 under the existing `qemu` setup, and AArch64 under `qemu-aarch64` from VA-5.
- Windows and Darwin stay compile-only until someone can run them. Say so in the docs.

**Lua.** After VA-3, `nuc-lua` deletes its `src/c/` and removes the known-limitation's
workaround tags, and the port has no C left at all.

## 11. Not measured

- Anything on LLVM above 19.1.7.
- Variadics under the x32 or aarch64-be ABIs. `emit-va-next` assumes little-endian
  and 64-bit pointers.
- Running Windows, Darwin or AVR.
- `musttail` forwarding (Q7).
- A struct by value in a variadic *call* tail from Nucleus to C. It goes through the existing
  `abi-arg-frag`, and this write-up didn't test it.
- Any of §4 end to end. The lowering was checked in hand-written IR called from C, not
  through a modified compiler.
