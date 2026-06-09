# volatile — next-session plan

First feature from `types.md` to land. Designer answers already captured in `types.md` (Designer section, item 6):

- Postfix list form `(T volatile)` and sugared `T:volatile`.
- "That shouldn't require any changes to sugaring."

## Surface syntax

- `x:i32:volatile` — sugars to `(x (i32 volatile))` via existing multi-colon desugaring. Confirm by inspecting `split-colon-segments` / `desugar-symbol` in `src/nucleusc.nuc` (~lines 3905, 3928).
- `(x (i32 volatile))` — canonical list form for a typed binding.
- Bare type position: `(volatile T)` is NOT the form. It's postfix: `(T volatile)`.

## Implementation steps

### 1. Refactor load/store to a shared helper (prerequisite)

`src/nucleusc.nuc` currently has ~30+ inline `fprintf g-body-stream "  store %s %s, ptr %s, align %d\n"` and `"  %s = load %s, ptr %s, align %d\n"` sites (see grep results in conversation history — lines 1199, 1396, 1432, 1491, 1521, 1677, 1694, 1746, 1759, 1765, 1957, 2022, 2066, 2457, 2465, 2542, 2544, 2649, 2651, 2706, 2740, 2745, 3260, plus the i1 variants at 1746/1759/1765, plus literal-init stores at 1101/1106/1112/1121).

Add two helpers near the top of codegen (find a place after `make-type` / before `emit-defstruct`):

```
(defn emit-load:void  (dst-tmp:ptr ir-type:ptr ptr-name:ptr align:i32 ty:ptr) ...)
(defn emit-store:void (ir-type:ptr val:ptr ptr-name:ptr align:i32 ty:ptr) ...)
```

The `ty:ptr` parameter is the Nucleus `Type*` for the value; when its `is-volatile` flag is set, emit `load volatile` / `store volatile` instead. Pass `null` for `ty` at call sites where volatility cannot apply (literal stores into freshly alloca'd slots) — helper treats null as non-volatile.

Mechanical refactor; verify by diffing emitted IR for a simple program before/after — should be byte-identical.

**Out-of-scope for this pass:** `inc!`/`dec!`/`set!` paths that emit their own load+modify+store sequences. Those need to inherit volatility from the lvalue's type — handle in step 3.

### 2. Type struct: add `is-volatile`

In `(defstruct Type ...)` (line 53), add:

```
is-volatile:i32
```

`make-type` zeroes it (arena-alloc is zero-init? — verify; if not, set explicitly in `make-type`).

Add a helper:

```
(defn type-with-volatile:ptr (t:ptr)
  ; Returns a new Type identical to t but with is-volatile=1.
  ; Don't mutate t — primitive types are shared (ty-i32 etc.).
  ...)
```

### 3. Parser: recognize `(T volatile)` postfix

In `parse-type-from-node` (line 701), add a clause: if the list's last element is the symbol `volatile`, parse the head as a type and return `(type-with-volatile parsed)`.

Place this check before the `(ptr ...)` and `(fn ...)` clauses, since `(ptr i32 volatile)` should mean "volatile (ptr i32)" not "(ptr i32) with garbage trailing token".

Symbol form `i32:volatile` desugars to `(i32 volatile)` via `split-colon-segments`. Verify the desugared output reaches `parse-type-from-node` correctly (the existing `(strchr (. n s) 58)` branch at line 705 handles this).

### 4. Wire volatility into inc!/dec!/set!

`set!`, `.set!`, `aset!`, `ptr-set!`, `inc!`, `dec!` all currently emit their own load+store. Each emits via the helpers from step 1, passing the lvalue's `Type*`. The helpers honor `is-volatile`.

Locate via `grep -n "emit-set\|emit-inc\|emit-dec\|emit-aset\|emit-ptr-set\|emit-dot-set"`.

### 5. Type equality / coercion

In `type-eq` (line ~638-647 region — used pointer identity for primitives, sdef pointer for structs):

- Volatility is part of the type for storage purposes (affects ABI of loads/stores)
- But assignment-compatible: `volatile T` ↔ `T` should be implicitly convertible
- C rule: you can read from `volatile T` into `T` and write `T` into `volatile T`; only the access through the volatile lvalue is volatile-qualified

Simplest safe rule: `type-eq` ignores `is-volatile`. The volatility lives at the storage site (the variable / struct field / pointer target), not at the value level. Verify this against actual call sites of `type-eq` to make sure nothing breaks.

### 6. type-to-ir

Volatility doesn't appear in LLVM IR type syntax — it's an instruction-level annotation. `type-to-ir` is unchanged.

### 7. Tests

Add `tests/expected/volatile.out` and `examples/volatile.nuc` (or similar — check existing test layout) exercising:

- `(let (x:i32:volatile 0) (set! x 1) x)` — store/load should be volatile in IR
- Struct field declared volatile — `.` access volatile
- Pointer to volatile — `(ptr i32:volatile)`, deref through it is volatile
- Pass volatile through a function param — typing should accept

Use `diff <(build/nucleusc examples/volatile.nuc 2>/dev/null) examples/volatile.expected.ll` or similar to assert volatile keyword presence. (Check how existing tests gate compile-time IR vs. runtime output — `tests/run-tests.sh` diffs runtime per `context/build.md`. May need a separate check.)

### 8. Bootstrap

`make test` and `make bootstrap` must both pass. Do NOT run `make update-bootstrap` — leave the committed boot binary alone until designer decides.

## Files likely touched

- `src/nucleusc.nuc` (most of the work)
- `examples/volatile.nuc` (new test)
- `tests/expected/volatile.out` (new)
- `docs/builtins.md` — add volatile to type qualifiers section
- `design/stage8/types.md` — strike `volatile` from the Implement list when done

## After volatile

Mark TaskList #5 complete. Next up: #1 (anonymous struct + nested) — needs synthetic naming for anonymous StructDef and bumping `MAX-STRUCTS` (currently 64) to a generous cap or growable backing.
