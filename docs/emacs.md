# Emacs interaction mode

Files in `editor/`:

- `nucleus-mode.el` — major mode (font-lock, indentation, syntax table).
- `nucleus-repl.el` — inferior REPL plus `nucleus-interaction-mode`, a
  minor mode that layers REPL-driven commands on top of a `nucleus-mode`
  source buffer.

Add `editor/` to `load-path` and `(require 'nucleus-mode)`. Visiting any
`.nuc` file activates `nucleus-mode`; with the default
`nucleus-mode-enable-interaction` (`t`), `nucleus-interaction-mode`
turns on automatically and `editor/nucleus-repl.el` is autoloaded on
first use.

## Starting the REPL

`M-x run-nucleus` (alias `M-x nucleus-repl`) launches
`nucleusc -i --repl-format=json` under `comint` in `*nucleus-repl*`.
The buffer uses `nucleus-repl-mode`. Customize the program path and
arguments via `nucleus-repl-program` and `nucleus-repl-program-args`.

JSON error frames written to stderr are recognized by
`compilation-shell-minor-mode` (regex matches `"file":"…","line":N`),
so error lines are clickable and `M-g M-n` / `M-g M-p` walks them.

## Source-buffer keys (`nucleus-interaction-mode`)

| Key                    | Command                       | What it does                                                                 |
|------------------------|-------------------------------|------------------------------------------------------------------------------|
| `C-x C-e`              | `nucleus-eval-last-sexp`      | Send the sexp before point to the REPL.                                      |
| `C-M-x` / `C-c C-c`    | `nucleus-eval-defun`          | Send the enclosing top-level form.                                           |
| `C-c C-r`              | `nucleus-eval-region`         | Send the active region.                                                      |
| `C-c C-k`              | `nucleus-load-buffer`         | Send the entire buffer.                                                      |
| `C-c C-z`              | `nucleus-switch-to-repl`      | Pop to `*nucleus-repl*` (starting it if needed).                             |
| `C-c C-d`              | `nucleus-describe-symbol`     | Render `kind-of` + `type-of` + `locate` into `*nucleus-doc*`.                |
| `M-.`                  | `nucleus-find-definition`     | `(locate 'sym)`, parse `file:line`, `find-file` + `goto-line`.               |
| `M-,`                  | `xref-pop-marker-stack`       | Standard xref behavior.                                                      |
| `C-c C-m`              | `nucleus-macroexpand`         | `(expansion-of FORM)` for the sexp at point into `*nucleus-macroexpand*`.    |
| `C-c C-t`              | `nucleus-type-of`             | `(type-of FORM)`, echoed in the minibuffer.                                  |
| `C-c C-a`              | `nucleus-apropos`             | Prompt for a substring; render `(apropos "...")` in `*nucleus-apropos*`.     |

`completion-at-point` is wired up in both source buffers and the REPL.
It calls `(complete "<prefix>")`, parses the indented name list, and
caches the result for one command loop so typing stays responsive.

All commands route through a single synchronous helper,
`nucleus-repl--query`, which sends a form, waits up to
`nucleus-repl-query-timeout` seconds for the next prompt, and returns
the captured output with the trailing prompt stripped.

## REPL-side support: `(doc 'sym)`

`src/repl.nuc` exposes a `doc` meta-command alongside `dir`, `apropos`,
`kind-of`, etc. It prints two indented lines:

```
nuc> (doc malloc)
  kind: fn
  (malloc:ptr (p0:ui64))
```

The argument is a bare symbol, not a quoted form — `(doc 'malloc)` is
rejected by `repl-meta-sym-arg` because the parsed argument is a cell
`(quote malloc)`, not a symbol node. The same applies to `kind-of`,
`type-of`, `locate`, `defined?`, `forget`, `trace`, `untrace`.

For non-functions the second line is the `name : kind = value` /
`name : type` form already used by `dir`. Reader macros (kind
`rmacro`) only have the `kind:` line. The output format matches
`dir`/`apropos` so the elisp parser stays uniform.
