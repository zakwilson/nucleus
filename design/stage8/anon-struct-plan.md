# Anonymous + nested structs — implementation plan

Designer answers from `design/stage8/types.md`:

1. Structural equivalence: **memoized** — identical field-name+type list ⇒ shared `StructDef`.
2. Synthetic naming: **content-hashed**.
3. `(struct ...)` accepted everywhere `parse-type-from-node` is called.
4. **Eliminate `MAX-STRUCTS`** — growable backing.
5. Anonymous struct is always list form; sugared symbols for members (`x:i32`) work normally.
6. No C-style member-namespace injection. A future `..` macro will offer flat access; out of scope here.
7. Immediately after Nucleus-side support lands, do the C-header import side (cheader.nuc) without waiting for a commit.

## Step 1 — Growable struct registry

Change `g-structs` from a single arena slab of `StructDef` records to a growable malloc'd array of **pointers** to `StructDef`. Each `StructDef` is still arena-allocated individually so its address is stable (Type.sdef pointers must not be invalidated by growth).

- Replace `(defconst MAX-STRUCTS 64)` with `g-structs-cap:i32 0`.
- `g-structs:ptr` now points to `ptr:StructDef[]`.
- In `register-struct`: arena-alloc a fresh `StructDef`, grow the index table if `len == cap` (double, start at 8 — mirror `intern-string`), store pointer at `[len]`, increment `len`.
- Update `lookup-struct` and any other readers to index through the pointer table.
- Drop `MAX-STRUCTS` and the bootstrap `arena-alloc` site at line 4610.

## Step 2 — Content hash + memoization

Add `hash-struct-shape:ptr (field-names:ptr field-types:ptr nfields:i32)`:

- Walk fields, accumulating an FNV-1a hash over each field-name string and its type-shape descriptor.
- Type-shape descriptor for primitives = kind byte; for struct types = the **target struct's name pointer** (named structs are already unique by name; anonymous ones already have a content-derived name from a prior memoize, so the recursion terminates); for `(ptr T)` = a tag byte plus inner shape; for `(fn ...)` = tag + ret-shape + each param-shape.
- Synthetic name format: `"__anon_struct_h%016lx"` (16 hex of a 64-bit hash). Collisions are vanishingly unlikely; rejected as bugs if they ever occur.

Add `lookup-or-make-anon-struct:ptr (field-names:ptr field-types:ptr nfields:i32 line:i32)`:

- Compute the hash → synthetic name.
- `lookup-struct(name)` — if present, return its `Type` wrapper.
- Otherwise: `register-struct(name)` with the hashed name, fill fields, emit `%__anon_struct_hX = type { ... }` to `g-type-stream`, return wrapper.

## Step 3 — Parse `(struct ...)` as a type expression

Add a clause in `parse-type-from-node` (after symbol handling, near the `(ptr ...)`/`(fn ...)` branches): when the head symbol is `"struct"`, treat the remaining elements as field bindings:

- For each member node, call `extract-name-and-type` (which already handles `name:type` and `(name type)` forms and recurses for inline `(struct ...)` types via this same function).
- Build the field-name + field-type arrays exactly as `emit-defstruct` does.
- Delegate to `lookup-or-make-anon-struct`.

The recursion is correct because `extract-name-and-type` reaches into `parse-type-from-node`, which is the function we are extending.

## Step 4 — defstruct nested anonymous

No special-case needed once Step 3 is in. `emit-defstruct` already uses `extract-name-and-type` per field; an inline `(struct ...)` type just falls through to the new clause. Verify by test.

## Step 5 — type-eq

No change. After memoization, structurally-equal anonymous structs share one `StructDef*`, so the existing identity comparison already does the right thing.

## Step 6 — Tests

`examples/anon-struct.nuc`:

- `(let (p:(struct x:i32 y:i32) ...) (set! (. p x) 1) (. p x))`
- `(defstruct Outer point:(struct x:i32 y:i32) tag:i32)` and `(. (. o point) y)` access.
- `(defn take:i32 (p:(struct x:i32)))` called from two sites with literal anonymous-struct typed values; both call sites must resolve to the same `StructDef`.
- Returning `(struct x:i32 y:i32)` from a function.
- `(ptr (struct x:i32))` round-trip.
- Two different shapes (`(struct x:i32)` vs `(struct y:i32)`) must produce distinct StructDefs.

Expected output via `tests/expected/anon-struct.out` (runtime-diff style, matching existing test harness).

## Step 7 — Documentation

Update `docs/builtins.md` (or wherever struct types are described) with the `(struct ...)` form and its memoization semantics. Strike "Anonymous structs" and "Nested structs" from `design/stage8/types.md` Implement list.

## Step 8 — C header import (immediately after, no commit gate)

`src/cheader.nuc` currently skips anonymous inner structs (per stage8-list.md). After Step 7:

- In the `clang -E` struct-body parser, recurse into nested braces to capture inner anonymous structs.
- For each inner anonymous struct, emit a `(struct ...)` type expression in the imported defstruct's field — relying on Step 3's parser support.
- Verify against a real header that exercises this (e.g. parts of `<sys/socket.h>`).

## Bootstrap

`make test` and `make bootstrap` must pass. Do NOT run `make update-bootstrap`.

## Files likely touched

- `src/nucleusc.nuc` (registry refactor, hash, parser clause)
- `src/cheader.nuc` (Step 8)
- `examples/anon-struct.nuc` (new)
- `tests/expected/anon-struct.out` (new)
- `docs/builtins.md`
- `design/stage8/types.md` (strike done items)
