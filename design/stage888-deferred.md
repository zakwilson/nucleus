# Deferred

## Storage class specifiers

C has `static`, `register`, `thread_local` / `_Thread_local`. Nucleus
has none of these. Deferred from stage 8 globals work — `set!`,
`defvar` literal expansion, and producing-side `extern` cover the
common cases without needing syntax for storage classes.

When added, candidate spellings would mirror the type qualifier shape
used by `volatile` — e.g. `name:type:static` or `(name (type static))`
as a postfix tag on the storage site. None of this is committed.
