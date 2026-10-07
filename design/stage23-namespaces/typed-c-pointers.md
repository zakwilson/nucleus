# Typed C pointers: checking pointer arguments at the C boundary

Investigated, ruled and built 2026-10-05. §2–§3 are the prototype's
measurements; §6 is what was built.

## 1. The problem

The program in `charge.nuc` passed a quoted symbol (a `Node *`) where GTK expected
a `GtkWidget *`. It compiled and crashed at run time. A Nucleus function with a
`?&W` parameter refuses that argument. A C function with a `W *` parameter
accepts it, and accepts a pointer to an unrelated struct too.

**Root cause: the importer, not the checker.** `c-parse-type`
(`src/cheader.nuc`) returns bare `ptr` for every C declarator with a `*`. This
happens in three places: the enum, struct and typedef/builtin paths. Bare `ptr`
is `void *`, and it matches any pointer in either direction
(`docs/types.md`, "Pointer ↔ pointer, when the pointees agree"). So the
pointee-agreement check already exists. It never sees a C pointee.

## 2. Prototype and measurements

The prototype makes a single-level `T *` import as `(ptr T)` (the unchecked
kind, so nullability is unchanged) when `T` is one of:
- a known struct (opaque included);
- a typedef;
- a builtin.

These stay bare `ptr`: `void *`, an unresolved pointee, and `T **`.

The prototype had one bug, fixed. `FILE` is registered as an opaque struct, but
its typedef entry holds the bare-`ptr` stand-in that the importer uses for a
layout it can't read. When a typedef resolves to that stand-in and a struct of
the same name exists, the struct wins.

**Results:**

| Gate | Result |
|---|---|
| `make test` | 1322 passed + the 5 known datalayout failures. **No new failures.** |
| Self-compile | Clean. No call in the compiler disagrees with a C header. |
| The `charge.nuc` crash | Refused: `gtk_box_append: argument 2 has type &Node, …` |
| GTK import time | **+27%** (1.78 s → 2.27 s). See §4, TP-0. |

**How many pointers keep a type.** Each pointer declarator the importer read
was counted once per parse (proportions are what matter).

| Import | Declarators | Typed | `void *` | `T **` | Unresolved |
|---|---|---|---|---|---|
| libc (`stdio`, `stdlib`, `string`, `unistd`, `sys/stat`) | 696 | 78.4% | 16.7% | 4.2% | 0.7% |
| `gtk/gtk.h` | 33,415 | 90.8% | 3.6% | 4.8% | 0.7% |

`void *` is a wildcard in C too. Of the pointers that have a pointee, **94%**
are checked in both imports.

## 3. What a strict check turns up

Each conversion was probed against the prototype.

| Argument → C parameter | Prototype | C (clang) | Verdict |
|---|---|---|---|
| `&Node`, `&V` → `W *` | refused | error | **the fix** |
| `&i8`/literal/`CStr` → `char *` | ok | ok | keep |
| `&ui8` → `char *`; `unsigned char *` result → `strlen` | refused | warning (`-Wpointer-sign`) | **false positive, see TP-3** |
| `&usize` → `size_t *` | refused | ok | **importer bug, see TP-2** |
| `&ui32` → `int *` | refused | warning | keep refused |
| `&i64` → `long *`, `&bool` → `bool *`, `&i32` → `int *` | ok | ok | keep |
| `GtkApplication *` → `GApplication *` (upcast) | refused | error without `G_APPLICATION()` | **see TP-4** |
| `GtkWidget *` → `GtkWindow *` (downcast) | refused | error without `GTK_WINDOW()` | explicit cast, as in C |

**The GTK program.** It needs 10 casts:
- 9 are downcasts from `GtkWidget *`. GTK's constructors return `GtkWidget *`,
  and its setters take the class. They are exactly the sites where C writes
  `GTK_WINDOW(w)` and friends.
- 1 is the upcast in `g_application_run`.

**The hierarchy is only partly visible in the headers:**
- A first-field chain works where structs have bodies:
  `GtkApplicationWindow → GtkWindow → GtkWidget → GObject`, and
  `GtkApplication → GApplication → GObject`.
- GTK 4 makes many widgets opaque, among them `GtkLabel` and `GtkComboBoxText`.
- 202 classes declared with `G_DECLARE_*` leave a checked cast function
  (`GTK_STRING_LIST (gpointer)`) in the preprocessed header.
- Only 69 of those name their parent, through a
  `typedef struct { ParentClass parent_class; } XClass;`.
- The older classes' casts are preprocessor macros, so they vanish.

**Downcasts therefore stay explicit.**

**A neighbouring hole, not part of this work.** A `CStr` parameter accepts any
pointer, `&i32` included. So typing `char *` as `CStr` would throw away most of
the check.

## 4. Phases

- **TP-0 — index the importer's lookups.**
  - `lookup-struct` (`src/union-registry.nuc`) walks every registered struct.
  - `c-typedef-find` (`src/type-utils.nuc`) walks a linked list.
  - Today `c-parse-type` is already 39% of a GTK import's samples. The prototype
    adds lookups, and that rises to 54%.
  - A HashMap keyed by name, for each table, removes the regression, and probably
    speeds up today's import too.
- **TP-1 — import `T *` as `(ptr T)`.**
  - This is the prototype, including the opaque-typedef rule.
  - It applies to parameters, returns, struct fields and typedefs.
  - Hand-written `declare`s and `.nuch` signatures are unchanged.
- **TP-2 — `size_t` → `usize`, `ssize_t` → `ssize`.**
  - Today `size_t` is a `ui16`/`ui32`/`ui64`, chosen by pointer width, which is
    what `usize` already is.
  - Prototyped: the suite and self-compile are unchanged.
- **TP-3 — `char` signedness.** Let `i8` and `ui8` pointees match at a C
  boundary, which is what C itself does with a warning. **Decision needed
  (Q1).**
- **TP-4 — first-member upcast.**
  - A pointer to a C-imported struct converts implicitly to a pointer to its
    first field's struct type, transitively.
  - It stops at an opaque struct.
  - C guarantees the layout (C11 6.7.2.1¶15). GObject, and much other C code,
    builds inheritance on it.
  - This is more lenient than C, which demands `G_APPLICATION()`, but it is
    sound. **Decision needed (Q2).**
- **TP-5 — fill in the unresolved 0.7%.**
  - Register an opaque struct on the first `struct Tag *`, as C does for an
    incomplete type. This covers the self-referential
    `struct __pthread_internal_list *`.
  - Follow typedef-of-typedef chains to an opaque struct: `GtkSnapshot` →
    `GdkSnapshot`.
- **TP-6 — `T **` as `(ptr (ptr T))`.**
  - This is 4–5% of pointers, and includes GLib's ubiquitous `GError **`.
  - First, probe whether `&?&GError` matches `(ptr (ptr GError))`. That depends
    on whether the inner pointer's kind is ignored the way the outer one is.
- **Not compiler work: a GObject cast helper.**
  - A `g-cast` macro, `(g-cast GtkLabel w)`, would expand to
    `g_type_check_instance_cast` with `gtk_label_get_type`.
  - It gives Nucleus GTK code the run-time-checked downcast C has, in place of
    `unsafe/cast`.
  - It belongs in a GTK binding library: see `design/gtk-wrapper/options.md`.

**Gates for each phase:** `make test`, self-compile, the boot fixed point, and
examples. Plus:
- TP-1: the `charge.nuc` reproducer as a test; a pointee-mismatch test against a
  fixture header.
- TP-2/TP-3: the §3 probe rows as tests.
- TP-0: GTK import time no worse than today.

## 5. Questions (ruled 2026-10-05: Q1 (a), Q2 implicit; TP-0 deferred)

- **Q1. How far does the `char` rule reach?**
  - (a) Only where the parameter came from a C declaration. This needs the call
    check to know the callee's origin.
  - (b) Everywhere `i8`/`ui8` pointees meet, Nucleus code included.
  - (c) None: users write `as`/`unsafe/cast`, as C users silence
    `-Wpointer-sign`.
  - Recommended: (a).
- **Q2. Implicit upcast, or `as`?**
  - Implicit is the more lenient rule.
  - Allowing it only through `as` keeps C's explicitness, while still sparing
    `unsafe/cast`.
  - Recommended: implicit, since it is sound and saves the GTK upcasts.

## 6. As built

TP-1 through TP-6 are built. TP-0 is deferred, at the user's ruling: see
`design/deferred/overview.md`, "The C importer's lookups are linear scans".

**Importer** (`src/cheader.nuc`):
- `c-ptr-to` wraps a pointee in one `(ptr …)` per `*`. `void` and an unresolved
  pointee leave bare `ptr`.
- `char` and `unsigned char` pointees become the marker singletons `ty-c-char`
  and `ty-c-uchar`. These are `i8`/`ui8` to every other question, because
  `type-eq` compares primitives by kind.
- The enum, struct and typedef/builtin paths of `c-parse-type` use it, and so
  does the `typedef struct {…} *P` declarator.
- A typedef holding the bare-`ptr` stand-in yields to a struct of the same name.
  This is the `FILE` case.

**Checker** (`src/abi.nuc`):
- `slot-type-compat` gains the byte rule (`c-byte-pointees`) and `CStr` ≍ C
  `char *`.
- It also gains one C type under several names (`c-same-struct`): either the
  same alias root, or one shared field table. The second matters because
  `cheader-adopt-shape` shares the table, so the tag and the typedef name of
  `typedef struct _W {…} W;` both carry the anonymous body's table, with no
  alias link between them.
- `slot-value-compat` adds the first-member upcast. It is used only where a
  value converts:
  - `safe-coerce-val` (arguments);
  - `coerce-int-val` (`let`, `set!`, `return`);
  - the `defvar` constant renderer.

  So neither a nested pointer nor a function-pointer signature can upcast.
- `c-downcast-hint` appends the `unsafe/cast` spelling to an argument mismatch
  between two C struct pointers.

**Registration fixes the typed check exposed:**
- **A `typedef struct Tag {…} Name;` body now registers `Tag`** if nothing named
  it earlier, linked to the body. Before, a later `struct Tag *` found nothing.
  With typed pointers it would have declared a second, permanently opaque
  `Tag`.
- **A prescan-registered typedef name gets its `alias-of` link** when the body
  arrives.
- **`struct Tag *` registers an opaque `Tag` on first sight**, as C declares an
  incomplete type.
- **TP-5's typedef-of-opaque alias registers only in the real import.** The
  prescan sees every struct opaque. Registering there made glibc's `sigset_t`
  permanently opaque, which the `l2-libc-layouts` test caught.

**Gates:**
- `make test`: 1329 passed, plus the 5 known datalayout failures. Seven new
  units in `tests/suite-cimport.nuc` (`tp1-*` … `tp6-*`) run against
  `tests/fixtures/tp-pointers.h`.
- Self-compile: clean. Boot refreshed: boot == stage1 == stage2.
- Examples: 162/162. `abi-test`: passes.
- `charge.nuc`: 9 casts, all GTK downcasts. The `g_application_run` upcast no
  longer needs one.
- GTK import: +32% (1.77 s → 2.33 s), which is TP-0's cost.

**Not built:** the GObject `g-cast` helper (§4), which is library work
(`design/gtk-wrapper/options.md`).

**Follow-on, 2026-10-06: a prescan bug that typing the bindings exposed.**
Declaring `charge.nuc`'s widgets as their GTK class takes the casts from 9 to 5:
- three at creation;
- two downcasts to opaque classes.

That rewrite needed `?&GtkComboBox` in a global, which the signature prescan did
not know. `cheader-skip-to-semi` skipped a `static inline` body to the next
`;`, eating the declaration after it. A `{` opened right after a `)` now ends
the declaration at its `}`.
