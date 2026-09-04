# Stage 19 — process control

**Status: built 2026-09-04** (P1–P6). §8 records the five deltas from this plan.

**Goal.** `lib/process.nuc`: start a program, control its streams, wait for it,
and read a typed exit status. A self-hosted systems language that cannot run
another program is incomplete on its own terms, and today Nucleus cannot —
outside two raw `popen`/`pclose` declares the compiler keeps for itself.

**Why this is its own stage, ahead of Stage 18 part two.** The test framework
needs process control, but process control does not need the test framework.
Every option in [stage18-tooling/overview.md](../stage18-tooling/overview.md)
§T5 except E is downstream of this module, and the §T5 decision is still open —
so scheduling this behind that decision would block a capability the language
owes its users on a question about how its own tests are spelled. The dependency
runs one way. This stage is the part that does not depend on the answer.

---

## 1. Ground truth (verified 2026-09-04 against the tree)

### 1.1 What exists

| Piece | Where | What it is |
| --- | --- | --- |
| `popen` / `pclose` | `src/cheader.nuc:15-16` | Raw `declare`s, compiler-private |
| `read-pipe-output` | `src/cheader.nuc:1481` | `popen` + a `malloc`/`realloc`/`fread` loop; returns a raw `ptr` with length and status as out-parameters |
| `system` | `src/cheader.nuc:1418`, `src/nucleusc.nuc:18641` | Two call sites, both building a shell command string |

There is no `fork`, `execv`, `posix_spawn` or `waitpid` anywhere in `src/` or
`lib/`, and nothing in `lib/` exposes any of the above. `read-pipe-output` is the
whole of the language's process story, it is not reachable from `lib/`, and its
signature predates `!T`, `String` and `Drop`.

### 1.2 What already works — this is library work, not compiler work

Verified by compiling and running probes today, against `bin/nucleusc` as it
stands, with no compiler changes:

- **`fork`, `_exit`, `waitpid` and `WNOHANG`** resolve from `(import-use
  "unistd.h")` and `(import-use "sys/wait.h")`. A child calling `_exit(7)`
  yields raw status **1792**.
- **`pipe`, `dup2`, `close`, `read`, `execvp`** all work, including passing a
  NUL-terminated `ptr:ptr` as `char *const argv[]`. An end-to-end
  fork → pipe → dup2 → execvp → read → waitpid probe printed the child's output
  and its exit code correctly on the first working build.
- **`struct pollfd` is fully transparent** — `(sizeof pollfd)` is 8, its fields
  assign, and `POLLIN` is 1. The header reader does not make it opaque, so the
  deadlock-free capture of §2.3 is available.
- **`posix_spawn_file_actions_t` is 80 bytes**, also not opaque. Both spawn
  routes are open; §2.1 picks between them on other grounds.

**The whole POSIX surface this module needs is already reachable.** That is the
finding that sizes the stage: it is a library to write, not a compiler feature to
add, and nothing here is blocked on anything.

### 1.3 The one real gap: function-like macros

`cheader-macro-line` (`src/cheader.nuc:2787`) admits object-like `#define`s only
— "a `(` immediately after NAME makes it function-like, which stays out"
([platform-constants.md](../stage17-native-strings/platform-constants.md) §3.2).
So `WNOHANG` imports and **`WIFEXITED`, `WEXITSTATUS`, `WIFSIGNALED` and
`WTERMSIG` do not.**

This **corrects [stage18-tooling/overview.md](../stage18-tooling/overview.md)
§T3**, which claimed Stage 17's constant import left `lib/process.nuc` needing no
hardcoded platform knowledge. It needs exactly one piece: the layout of a wait
status. The probe's 1792 is `7 << 8`, and the decoding — low 7 bits the
terminating signal, `0x7f` meaning stopped, bits 8–15 the exit code — is written
in Nucleus, in one place, once (§2.4). It is the same layout on Linux and the
BSDs, and it is not guaranteed by POSIX, which is precisely why it belongs behind
a typed accessor rather than at 30 call sites.

---

## 2. Decisions

### 2.1 `fork` + `execvp`, not `posix_spawn`, and never `system`

All three are available (§1.2). The choice is not availability:

- **`system` and `popen` route through `/bin/sh`**, which means the caller
  assembles a command *string* and owns the quoting. Every argument containing a
  space, a quote or a `$` becomes a correctness problem that a typed API exists
  to make impossible. An `argv` vector has no quoting.
- **`posix_spawn` is a second vocabulary** — `posix_spawn_file_actions_init`,
  `_adddup2`, `_addclose`, `_destroy` — to wrap for the same result, and its
  advantage (no address-space copy) is one `vfork` implementation detail on the
  platforms that matter. `fork`/`execvp` needs no opaque handle and expresses the
  child's fd plan as ordinary code.

`system` and `popen` stay only as long as §5 takes to retire them.

### 2.2 Everything the child needs is built before the `fork`

Between `fork` and `execvp` the child may call async-signal-safe functions only.
Allocating there — building an `argv` array, formatting a path, growing a
`Vector` — is a deadlock or a corrupted heap waiting for the day the allocator
holds a lock at fork time.

So the API takes a **`Command` value that is fully built before spawning**:
program, `argv` already materialised as a NUL-terminated pointer array, `envp` if
overridden, and the fd plan as a small fixed table. The child window is then
`dup2`, `close`, `execvp`, `_exit(127)` — four calls, no allocation, no
formatting. This is why the surface is a `Command` record rather than a spawn
that takes a callback: a callback is an invitation to allocate in the child.

### 2.3 Capturing both streams uses `poll`, because sequential draining deadlocks

A pipe holds a bounded amount — 64 KiB on Linux. Read the child's stdout to EOF
while the child writes more than that to stderr and the child blocks on the full
stderr pipe, never closes stdout, and the parent waits forever. This is not a
slow path to optimise later; it is a hang, and it is reachable by any test whose
subject prints a large diagnostic.

`poll` over both read ends, draining whichever is ready, is the fix, and §1.2
verified `struct pollfd` is usable. The alternative — redirect one or both
streams to temporary files — trades the hang for a dependency on a filesystem
module this stage deliberately does not have (§6).

### 2.4 The exit status is a typed value, and the raw `int` never escapes

`waitpid`'s status is a packed `int` whose accessors are macros the header reader
cannot import (§1.3). The module decodes it once, into a value that names what
happened:

```
exited(code)      — the child called exit / returned from main
signaled(sig)     — the child died on a signal
```

Callers ask `status-code` or match on the variant. Nothing outside the module
sees 1792, and the bit layout that is not guaranteed by POSIX lives at exactly
one site, so a port to a platform that spells it differently is a one-function
change.

### 2.5 `Process` owns the child, and `Drop` reaps it

`lib/file.nuc`'s `File` closes its descriptor in `Drop`; a `Process` that does
not reap leaves a zombie, and a runner that spawns 955 children leaks 955 slots
in the process table. So `Drop` waits.

**The hazard is named rather than designed away:** dropping a `Process` whose
child is still running blocks until it exits. The intended path is an explicit
wait; `Drop` is the safety net for the error path, not the normal one. A separate
`process-detach` covers the deliberate fire-and-forget case, and `process-kill`
covers the case where the caller has given up.

### 2.6 Two tiers, because a one-shot API cannot express a job pool

`run` — build a command, spawn it, capture both streams, wait, return output and
status — is what almost every caller wants, including `read-pipe-output`'s
replacement.

It is not sufficient. A job pool spawns *N* children and needs to service
whichever finishes first, which is `waitpid(-1, …)` — a fact about the *set* of
children, not about any one of them. `run` cannot express it at any API width. So
the module exposes the pieces (`spawn`, `wait`, `try-wait`, `wait-any`) as well
as the convenience, and `run` is written in terms of them.

---

## 3. The surface

Sketch, not final spelling — the exact syntax settles at implementation against
the idioms in `lib/file.nuc`:

```
(defstruct Command …)         ; program, argv, envp, fd plan
(defn command ((prog (ref StrView))):Command)
(defn command-arg ((self (ref Command)) (a (ref StrView))):void)
(defn command-env ((self (ref Command)) (k (ref StrView)) (v (ref StrView))):void)
(defn command-cwd ((self (ref Command)) (dir (ref StrView))):void)

(defstruct Process pid:i32 …)  ; owning; Drop reaps (§2.5)
(defn spawn ((self (ref Command))):!Process)
(defn process-wait ((self (ref Process))):!ExitStatus)
(defn process-try-wait ((self (ref Process))):!(Maybe ExitStatus))   ; WNOHANG
(defn process-kill ((self (ref Process)) sig:i32):!void)
(defn process-detach ((self (ref Process))):void)
(defn wait-any ():!ChildExit)                                        ; waitpid(-1)

(defstruct Output status:ExitStatus out:String err:String)
(defn run ((self (ref Command))):!Output)
```

Errors follow the established shape: `!T` returns with `deferror` codes defined
in the module, the way `lib/parse.nuc` defines its own rather than reaching into
`lib/string-errors.nuc`.

---

## 4. Phases

Each phase is gated by `make test`, `./scripts/stage17/ir-snapshot.sh verify`
and `make bootstrap`. The snapshot must stay byte-identical throughout: this
stage changes what the compiler *is written with*, never what it emits.

**P1 — spawn and wait.** `Command`, `Process`, `spawn`, `process-wait`,
`ExitStatus` and its decoding (§2.4). No stream capture: the child inherits the
parent's descriptors. This is the smallest thing that runs a program, and it is
enough to replace the two `system` call sites of §5.
*Gate:* exit codes and signal deaths both round-trip through `ExitStatus`.

**P2 — streams.** Pipes, the pre-fork fd plan (§2.2), `poll`-based capture
(§2.3), `Output`, `run`.
*Gate:* a child writing more than a pipe buffer to *both* streams completes.
This test is the phase — without it §2.3 is an assertion, not a property.

**P3 — the job-pool primitives.** `process-try-wait`, `wait-any`,
`process-kill`, `process-detach`.
*Gate:* spawn *N* children with staggered lifetimes and reap them in completion
order, not spawn order.

**P4 — retire the compiler's private process code.** §5. The module is not done
until the compiler uses it.

**P5 — documentation.** `docs/process.md`, and the module listed wherever
`docs/stdlib.md` lists modules. Per the house rule this is not optional; a
capability the language has and does not document is one its users do not have.

**P6 — an `examples/` program.** One example that shells out and reads a result,
so the facility is demonstrably usable from outside the compiler.

---

## 5. What this retires

- **`read-pipe-output`** (`src/cheader.nuc:1481`) — a `malloc`/`realloc`/`fread`
  loop returning a raw `ptr` with two out-parameters, written before `!T` and
  `String` existed. Its caller wants `run`.
- **The `popen`/`pclose` declares** (`src/cheader.nuc:15-16`) — private to the
  compiler because there was nowhere else to put them.
- **Both `system` call sites** (`src/cheader.nuc:1418`,
  `src/nucleusc.nuc:18641`), each of which builds a shell command string and
  inherits the quoting problem of §2.1.

This is the stage's own dogfooding, and it is the reason P4 is a phase rather
than a follow-up: a library the compiler does not use is a library nothing has
tested against a real caller. It is the same rule that made Stage 17 produce a
string library instead of a string module.

---

## 6. Out of scope

- **Filesystem operations.** `mkdir`, `mkdtemp`, `unlink`, `rmdir`, `readdir`
  are a sibling module with its own reasons to exist, and §2.3 was decided the
  way it was partly so this stage does not acquire a dependency on one.
- **Threads.** Not needed and not wanted; the parallelism here is process-level.
- **Windows hosts.** The compiler can *target* a Windows triple
  (`target-long-size` checks for it), but this module is host-side POSIX. A
  Windows host needs `CreateProcess` behind the same surface — a later phase
  with a real user, not speculative portability now.
- **Signal handling in the parent.** `SIGCHLD` handlers, `sigaction`,
  process groups. `waitpid` covers what a job pool needs.

---

## 7. Open decisions

1. **Does `run` merge stderr into stdout, offer both separately, or both?** The
   compiler's existing caller wants merged; Stage 18's `run_reject_at` shape
   wants them separate (it discards stdout and reads stderr). Both is two fields
   and one flag, and probably right, but it is a decision.
2. **Does `spawn` search `PATH`?** `execvp` does, `execv` does not. Searching is
   what callers expect; not searching is what a test harness wants when it means
   *this* binary. Likely both, spelled distinctly.
3. **What happens to a `Command` after `spawn`?** Reusable for a second spawn, or
   consumed? Reuse is convenient and makes the fd plan's ownership subtle.
4. **Where do the environment defaults come from?** Inherit the parent's `environ`
   unless overridden, or start empty and require what the child needs? Inheriting
   is expected; starting empty is what makes a test suite reproducible.

---

## 8. As built (2026-09-04)

All six phases landed. 959 tests (955 + three phase gates + the example), IR
snapshot byte-identical across 2,624 artifacts, bootstrap converged,
`check-headers` and `check-cstr` clean.

`lib/process.nuc` is 415 lines. Five deltas from the plan above:

**8.1 `process-try-wait` returns `!bool`, not `!(Maybe ExitStatus)`.** The
planned signature does not compile: `(Result (Maybe T) Err)` for a struct `T`
stamps a `(Maybe ExitStatus)` whose type the `ok` arm's field rejects
(*"type mismatch for a field of arm 'ok'"*), and the plain `:!(Maybe …)` sugar
does not parse at all. A `bool` plus a `process-status` accessor says the same
thing — the status is stored on the `Process` either way — and the accessor is
useful on its own. **This is a real language limitation the port found**, of
exactly the kind §1 said the exercise is for: nested template construction in a
return position has no want channel to resolve `some` against. Fixing it is a
compiler change with its own gates, not a phase of this stage.

**8.2 `command-env` merges rather than appends, which settled §7 decision 4.**
The child inherits the parent's environment and an override *replaces* the
inherited entry. Appending would have been three lines, and wrong: `getenv`
returns the first match, so a duplicate entry is never seen. `environ` needed an
`(extern environ:ptr:ptr)` declaration — the C header reader takes function
declarations and object-like macros, not `extern` variables. The child sets it
with a pointer store, which is safe in the post-fork window where `setenv` (which
allocates) would not be.

**8.3 The `Command` holds one buffer, not a `(Vector String)`.** `Vector`'s
`drop` frees its array **without dropping its elements**, so N owning strings
would have leaked N heap buffers. Arguments accumulate NUL-terminated into a
single `String` with a vector of offsets, which also makes the argv pointers
stable and the whole thing one allocation.

**8.4 P4 kept the cheader cache's `ptr`+length interface.** The cache stores a
bare pointer in a `Node` and nothing ever frees it, so converting it to `String`
would have meant changing the cache representation as well. Instead
`cheader-capture` parks the captured `String` in a process-lifetime
`g-cheader-bufs` vector and hands out `string-as-cstr`'s pointer — no copy, and
the owner outlives every reader. Converting the cache itself is follow-on work.

**8.5 The example is `examples/subprocess.nuc`, not `process.nuc`.** A file named
`process.nuc` cannot `(import-use process)`: the compilation unit's root file is
on no import list, so the import silently resolves to the file itself and every
name from the module goes missing. The diagnostic — *"'Command' is defined in
lib/process.nuc, which no import in this unit reaches"* — is accurate and reads
like a bug in the import. Recorded in `context/conventions.md`.

### What P4 retired

`read-pipe-output`, the `popen`/`pclose` declares, and both `system` call sites
are gone. Three consequences beyond the line count:

- The link step passes an **argv**. A path with a space in it was the caller's
  quoting problem and is now nobody's.
- `clang -E` no longer needs `2>/dev/null` in a command string; stderr is a
  separate captured stream that gets dropped.
- The `--sysroot=<dir>` flag was interpolated into a shell command line. A
  sysroot path containing a space was a latent bug; it is now one argument.
