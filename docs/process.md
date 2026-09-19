# Processes

`lib/process.nuc` — start another program, control its streams, wait for it, and
read a typed exit status.

```lisp
(import-use process)

(let (c:Command (command "git"))
  (command-arg &c "rev-parse")
  (command-arg &c "HEAD")
  (match (run &c)
    ((ok o)  (print "sha: " (string-as-view (ref o 'out))) (drop &o))
    ((err e) (eprint "could not run git\n")))
  (drop &c))
```

A `Command` is an **argv, not a command line**. Nothing goes through a shell, so
an argument containing spaces, quotes or `$` is one argument and nobody escapes
anything. There is no `system`-style entry point, deliberately.

See `examples/subprocess.nuc` for a worked example.

## Command

| Form | Meaning |
| --- | --- |
| `(command prog)` | A command that will run `prog`, with `prog` as `argv[0]`. |
| `(command-arg c a)` | Append one argument. |
| `(command-cwd c dir)` | Run the child in `dir` (default: inherit). |
| `(command-env c k v)` | Set one variable. The child otherwise inherits the parent's environment; an override **replaces** the inherited entry rather than shadowing it, since `getenv` returns the first match. |
| `(command-search c on)` | `true` (default) looks `prog` up on `PATH` (`execvp`); `false` treats it as an exact path (`execv`). |
| `(command-capture c on)` | Pipe the child's stdout and stderr back instead of inheriting the parent's. `run` sets this; set it by hand when driving `spawn` yourself. |
| `(command-stdout-path c path)` | Send the child's stdout to a file, created and truncated. |
| `(command-stdin-path c path)` | The child reads `path` as its stdin — shell `< path`. |
| `(command-stderr-to-stdout c on)` | The child's stderr follows its stdout — shell `2>&1`. |

A `Command` owns its argument buffer: `drop` it when you are done, and do not
add arguments to one that has already been spawned.

### Pipes or a file?

`command-capture` gives you the output as a `String`; `command-stdout-path`
gives the child a file and hands you nothing. Which one you want depends on how
many children there are.

**One child: capture.** `run` does exactly this.

**A pool of children: files.** A pipe holds a bounded amount — 64 KiB on Linux —
and a child that fills its pipe blocks until somebody drains it. With *N*
children in flight and one parent, draining child A means not draining child B,
and a parent blocked in `wait-any` is draining nobody at all. A file has no such
limit, so the parent can start every child and then wait, which is the whole
shape of a job pool. `tests/fixtures/s19-process-pool.nuc` is the worked
example.

The parent opens the file before forking — for `command-stdin-path` too — so a
bad path is a `process-redirect-failed` error rather than a child that silently
exits 127.

### `2>&1` and capture together

`command-stderr-to-stdout` applies to a captured child as well as a redirected
one, and it means the same thing in both: **one** stream. Under capture the
child's stderr is duplicated onto the *stdout pipe*, so `Output.out` holds the
interleaving the child actually produced and `Output.err` is empty. Two
separately drained pipes cannot reproduce an interleaving at all, which matters
whenever the thing being compared is a transcript.

## Running one thing: `run`

```lisp
(defn run ((self (ref Command))):!Output
```

Spawns, captures both streams, waits, and hands back everything at once.

| `Output` field | Type |
| --- | --- |
| `status` | `ExitStatus` |
| `out` | `String` — the child's stdout |
| `err` | `String` — the child's stderr |

`Output` owns two `String`s; `drop` it.

Both streams are drained together with `poll`. This is not an optimisation: a
pipe holds a bounded amount (64 KiB on Linux), so reading stdout to EOF while
the child writes more than that to stderr would block forever.

## The pieces: `spawn` and friends

`run` cannot express a job pool — servicing whichever of *N* children finishes
first is a question about the set, not about any one child — so the primitives
are public too.

| Form | Meaning |
| --- | --- |
| `(spawn c)` | `!Process` — start the child and return immediately. |
| `(process-wait p)` | `!ExitStatus` — block until this child ends, and reap it. |
| `(process-try-wait p)` | `!bool` — `true` if it has already ended (and `process-status` now holds the result); `false` if it is still running. |
| `(process-status p)` | `ExitStatus` — valid once a wait has succeeded. |
| `(process-capture p out err)` | `!void` — drain both pipes into two `String`s. Requires `command-capture`. |
| `(process-kill p sig)` | `!void` — send a signal. |
| `(process-detach p)` | Give up ownership without waiting. |
| `(process-pid p)` | The child's pid, or `-1` once reaped or detached. |
| `(wait-any)` | `!ChildExit` — reap whichever child finishes first. |

`ChildExit` has `pid:i32` and `status:ExitStatus`.

`wait-any` does not report "no children left": a pool knows how many it started,
so it calls this exactly that many times and a failure really is one.

### Ownership

`Process` owns a live child, and **`drop` reaps it** — a program that spawns
hundreds of children would otherwise leak a process-table slot for each.
Dropping a `Process` whose child is still running therefore *blocks*. The
intended path is an explicit `process-wait`; `drop` is the error path's safety
net. Use `process-detach` when you mean to leave a child running.

## ExitStatus

```lisp
(defunion ExitStatus
  (exited code:i32)
  (signaled sig:i32))
```

| Form | Meaning |
| --- | --- |
| `(success? st)` | `true` only for `exited` with code 0. |
| `(exit-code st)` | The code, or `128 + signal` for a signalled child — the shell's spelling. |

Match on it when the difference matters:

```lisp
(match st
  ((exited code)  (print "exit " code "\n"))
  ((signaled sig) (print "killed by " sig "\n")))
```

A child that could not `exec` — no such program, or not executable — exits `127`,
the shell's convention. It is an `exited` status, not a `spawn` error: by the
time `exec` fails the child already exists.

## Errors

`deferror` codes: `process-spawn-failed`, `process-wait-failed`,
`process-pipe-failed`, `process-read-failed`, `process-signal-failed`,
`process-redirect-failed`.

## Platform

POSIX hosts. The module uses `fork`/`execvp`/`waitpid`/`pipe`/`poll` directly.
Note that `command-env` replacing `PATH` also changes where `execvp` looks, since
the search reads the child's environment.
There is no Windows host support yet, and no parent-side signal handling —
`waitpid` covers what a job pool needs, and this module installs no handlers, so
a failing wait means the child was lost rather than that the call was
interrupted.
