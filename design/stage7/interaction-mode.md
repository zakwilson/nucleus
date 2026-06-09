# Stage 7 — Emacs interaction mode

## Context

`editor/nucleus-mode.el` today is a passive major mode: font-lock, indentation,
syntax table. The REPL (`nucleusc -i`) recently grew the introspection surface
described in `design/stage7/repl-features.md` (`defined?`, `kind-of`, `type-of`,
`dir`, `apropos`, `complete`, `locate`, `expansion-of`, `imports`, `casts`,
`last-error`, `time`, `trace`/`untrace`, `forget`/`reset!`), plus a structured
`--repl-format=json` error channel. This is the moment to give the editor mode
real interactivity — eval-from-buffer, completion, jump-to-definition, doc
lookup, macro expansion — driven by a local inferior REPL.

Scope is deliberately smaller than SLIME/Cider:

- Local inferior process only; no swank/nrepl-style network protocol.
- One REPL session per Emacs at a time (sufficient for now).
- Build on the existing introspection functions; no new wire protocol.
- Other editors (VS Code, neovim) are deferred until this mode stabilises.

## Approach

Add a new file `editor/nucleus-repl.el` providing a `comint`-derived
`nucleus-repl-mode` and a `nucleus-interaction-mode` minor mode that layers
keybindings onto `nucleus-mode` source buffers. Touch `nucleus-mode.el` only
to `(require 'nucleus-repl)` lazily and bind `C-c C-z` etc.

### Process model

- `M-x run-nucleus` (alias `nucleus-repl`) spawns
  `nucleusc -i --repl-format=json` via `make-comint-in-buffer` in
  `*nucleus-repl*`, with `process-connection-type` left at default (pty).
- The REPL writes prompts (`nuc> `, `...> `) and all results to **stderr**
  (`src/repl.nuc:515`). Under a pty stderr and stdout merge, so comint sees
  everything; we don't need explicit redirection.
- `comint-prompt-regexp` = `^\(nuc\|\.\.\.\)> `. The prompt is the
  synchronisation boundary for request/response interactions.

### Synchronous request/response helper

Most interactive features need to send a form and read its result back into
elisp (completion, doc, locate, type-of, expansion-of). Implement a single
helper:

```
(nucleus-repl--query FORM)  →  string (everything between the form and the
                                next prompt, with the echoed input stripped)
```

It works by:
1. Installing a temporary `comint-output-filter-functions` entry that
   accumulates output into a buffer-local string.
2. `comint-send-string` of `FORM` plus newline.
3. `accept-process-output` in a loop with a short timeout until the prompt
   regex appears in the accumulated output.
4. Removing the filter, returning the captured text minus the trailing
   prompt line.

`(last-error)` is consulted after each query; if it returns non-empty JSON
that postdates the query, signal a user-error showing the message. This is
the cheapest reliable error path given that JSON errors and normal results
both arrive on stderr.

### Source-buffer commands (in `nucleus-interaction-mode`)

| Key | Command | Implementation |
|---|---|---|
| `C-x C-e` | `nucleus-eval-last-sexp` | `comint-send-string` of the sexp before point; result echoed via `nucleus-repl--query` |
| `C-M-x` / `C-c C-c` | `nucleus-eval-defun` | Send the enclosing top-level form |
| `C-c C-r` | `nucleus-eval-region` | Send region text |
| `C-c C-k` | `nucleus-load-buffer` | Send buffer text wrapped per top-level form |
| `C-c C-z` | `nucleus-switch-to-repl` | Pop to `*nucleus-repl*`, starting one if needed |
| `C-c C-d` | `nucleus-describe-symbol` | `(kind-of 'sym)` + `(type-of sym)` + `(locate 'sym)` rendered into a `*nucleus-doc*` buffer |
| `M-.` | `nucleus-find-definition` | `(locate 'sym)` → parse `file:line` → `find-file` + `goto-line`; push tag mark |
| `M-,` | `xref-pop-marker-stack` | standard |
| `C-c C-m` | `nucleus-macroexpand` | `(expansion-of FORM)` for sexp at point, output to `*nucleus-macroexpand*` in `nucleus-mode` |
| `C-c C-t` | `nucleus-type-of` | `(type-of FORM)` echoed |
| `C-c C-a` | `nucleus-apropos` | prompt for substring; `(apropos "...")` rendered in a buffer |

Completion-at-point: register `nucleus-completion-at-point` on
`completion-at-point-functions` in both `nucleus-mode` and
`nucleus-repl-mode`. It calls `(complete "<prefix>")` and parses the
whitespace-indented name list. Results are cached briefly (per command
loop) to keep typing responsive.

### Error navigation

In the REPL buffer, install `compilation-shell-minor-mode` with a regex
that matches the JSON error frame
(`{"file":"\([^"]+\)","line":\([0-9]+\)`). This makes errors clickable
without parsing JSON ourselves; the bracketed JSON is otherwise treated as
plain text.

### Nucleus-side additions

The introspection set already covers the editor's needs except for one gap:
a single `(doc 'sym)` that returns docstring + signature + kind in one
call. The design doc lists `doc` as desired ("Designer" section) but it's
not yet implemented. Add it in `src/repl.nuc` alongside the other handlers
in `repl-handle-builtin`, composing existing helpers (`repl-classify`,
`repl-type-to-nuc`, `repl-print-fn-sig`). Output format: same indented-name
style as `dir`/`apropos` so the elisp parser stays uniform. No other
prelude or REPL changes are required — the elisp side composes existing
queries.

### Files to add / modify

- **add** `editor/nucleus-repl.el` — comint mode, query helper, commands,
  capf, `nucleus-interaction-mode` minor mode.
- **modify** `editor/nucleus-mode.el` — autoload `nucleus-repl`, bind
  `C-c C-z` / `M-x run-nucleus`, enable `nucleus-interaction-mode` in the
  mode hook (opt-in via `nucleus-mode-enable-interaction` defcustom,
  defaulting to `t`).
- **modify** `src/repl.nuc` — add `(doc sym)` handler, mirroring the
  surrounding handlers around `repl.nuc:228` (`dir`).
- **modify** `docs/` — add `docs/emacs.md` describing `M-x run-nucleus`,
  the keymap, and the `(doc ...)` helper. Link from `docs/` index if one
  exists.

Existing utilities to reuse:
- `repl-classify`, `repl-walk-names`, `repl-type-to-nuc`,
  `repl-print-fn-sig` in `src/repl.nuc` (lines ~120–280) for the `doc`
  handler.
- Standard `comint`, `compilation-shell-minor-mode`, `xref` from Emacs.

## Verification

1. Self-host: `make` rebuilds `nucleusc`; `make test` is green. The new
   `(doc ...)` handler follows the existing pattern so nothing else
   regresses.
2. Manual REPL smoke: `./build/nucleusc -i --repl-format=json`, exercise
   `(doc malloc)`, `(complete "ap")`, `(locate parse-form)`, `(type-of
   (+ 1 2))`. All return well-formed indented output and `(last-error)`
   stays empty on success, JSON-shaped on failure. Note the meta forms
   take a bare symbol — `'sym` is parsed as `(quote sym)`, which the
   handlers reject.
3. Emacs smoke (in a clean Emacs `-Q`, with `editor/` on `load-path`):
   - Open a `.nuc` file, `M-x run-nucleus`, see `nuc> `.
   - `C-x C-e` after `(+ 1 2)` echoes `3` (or the printed form).
   - `C-c C-c` on a `defn` round-trips; redefining and `C-x C-e`-ing a
     caller picks up the new body (uses existing thunk redefinition).
   - `M-.` on a known symbol jumps to its source; `M-,` returns.
   - `C-c C-d` opens a `*nucleus-doc*` buffer with kind/type/location.
   - `C-c C-m` expands a `when` form into its `if` desugaring.
   - `completion-at-point` after typing `def` offers `defn`, `defmacro`,
     etc.
   - Triggering a deliberate error in the REPL produces a JSON line that
     `compilation-shell-minor-mode` makes clickable, jumping to the
     offending source line.
4. Update `design/stage999-future.md` to reflect that local Emacs
   interaction is now in stage 7 and other editors remain deferred.
