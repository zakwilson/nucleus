; Stage 18 TF-6 category (a): the compiler's rejection and acceptance table.
;
; Each row is one test. `tests/nuctests.nuc` reads this file, registers a test
; per row, and runs `nucleusc --diagnostics=sexp` on the fixture -- so `(line …)`
; and `(message …)` are matched against ONE diagnostic record rather than
; grepped independently out of one stderr blob. See design/stage18-tooling/
; overview.md T4.2 and T6.6.
;
;   (reject NAME (file F) [(line N)] (message M)... [(note M)...])
;     compiling F must fail; every (message …) must appear in the message of a
;     diagnostic at F:N, and every (note …) in a note of a diagnostic there.
;     With no (line …), the message need only appear in some error, and the
;     old ":0: is a regression" guard becomes "no diagnostic has line 0".
;
;   (accept NAME (file F))
;     compiling F must produce no diagnostic at all.
;
; A `;` block above a row is that row's rationale, carried over verbatim from
; the `run_reject`/`run_reject_at`/`run_accepts` shell units this table retired.

(reject "avr6-const-on-let-rejected" (file "tests/fixtures/avr6-const-let.nuc")
        (message "':const' applies only to a defvar global"))
(reject "avr6-const-on-field-rejected" (file "tests/fixtures/avr6-const-field.nuc")
        (message "':const' applies only to a defvar global"))
(reject "avr6-const-mutate-rejected" (file "tests/fixtures/avr6-const-mutate-rejected.nuc")
        (message "set!: cannot assign to 'answer' -- declared :const"))

; Stage 13 L1: cfn escape analysis. A cfn captures each used local by reference,
; so the closure value inherits the captured referent's frame region. Returning
; it out of that scope would dangle, so compiling the fixture must FAIL with the
; frame-region escape error. (The `examples/closures.nuc` run covers the positive
; cfn case; this proves the escape rejection.)
(reject "closure-escape-rejected" (file "tests/fixtures/closure-escape.nuc")
        (message "address of frame-local storage escapes via return"))

; Stage 13 CE-3: moving a struct-VALUE Drop binding into an `mfn` consumes the
; source, so a later use must be rejected as use-after-move — including through
; `&x` (the only way to read a struct value's field). Compiling the fixture
; must FAIL with the use-after-move error. (The `examples/ce3-owning-closure.nuc`
; run covers the positive move/drop-once path; this proves the consume.)
(reject "ce3-use-after-move-rejected" (file "tests/fixtures/ce3-use-after-move.nuc")
        (message "use after move: 'r'"))

; Stage 14 LW-1/LW-2: an overload set with no i32 candidate (x:i64 / x:ui8)
; called with a bare literal reaches the tier-2 widen/untyped-int-literal
; adaptation pool on both candidates, so the call is genuinely ambiguous.
; Compiling the fixture must FAIL with the widening-ambiguity error. (The
; positive `examples/int-widening.nuc` run covers the unique-widen case; this
; proves the ambiguity accounting still dies.)
(reject "lw-ambiguous-widening-rejected" (file "tests/fixtures/lw-ambiguous-widening.nuc")
        (message "ambiguous overload for 'f' under argument widening"))

; Stage 14 LW-4: an out-of-range literal (300 does not fit ui8) must be a
; compile-time error instead of the old silent trunc-and-wrap. Compiling the
; fixture must FAIL with the representability error.
(reject "lw-literal-range-rejected" (file "tests/fixtures/lw-literal-range.nuc")
        (message "integer literal 300 does not fit ui8"))

; Stage 14 SM-5: a name containing a character that is legal in a Nucleus
; symbol but illegal in an unquoted LLVM identifier (ir-name-token only maps
; `?`/`!`; the solitary defn path applies no other sanitizing) must be a
; source-level compiler error, not a raw LLVM parse error at link/verify time.
(reject "sm5-illegal-char-rejected" (file "tests/fixtures/sm5-illegal-char.nuc")
        (message "illegal character '%' in generated symbol for 'weird%name'"))

; Stage 14 TC-1: a zero-arg return-only-tyvar generic called with no expected
; type (no declared binding → no want) must FAIL with the dedicated diagnostic,
; not the misleading "no matching method".
(reject "tc-cannot-infer-tyvar" (file "tests/fixtures/tc-cannot-infer-tyvar.nuc")
        (message "cannot infer type variable 'T' for 'box-empty'"))

; 2. A bare-name new-style defn missing its mandatory return operand dies cleanly
;    with the targeted diagnostic (the same message a stale legacy spelling gets
;    in Phase S4), not a crash or a remote type error.
(reject "s1-missing-ret-diagnostic" (file "tests/fixtures/s1-missing-ret.nuc")
        (message "expected return type after the parameter list"))

; Stage 14 defn-signature.md S4 — the legacy `name:ret` return-in-the-name signature
; is retired. A colon-bearing (or list-head) defn / declare / protocol-method /
; generic-template signature must now die with the targeted "legacy 'name:ret'
; syntax is no longer supported" diagnostic, quoting the offending name, at each
; chokepoint (defn-parse-sig, emit-nuch-declare-import, protocol-register-form,
; register-generic-defn).
(reject "s4-legacy-defn-rejected" (file "tests/fixtures/s4-legacy-defn.nuc")
        (message "defn 'foo': legacy 'name:ret' syntax is no longer supported"))
(reject "s4-legacy-declare-rejected" (file "tests/fixtures/s4-legacy-declare.nuc")
        (message "declare 'bar': legacy 'name:ret' syntax is no longer supported"))
(reject "s4-legacy-proto-rejected" (file "tests/fixtures/s4-legacy-proto.nuc")
        (message "protocol method 'area': legacy 'name:ret' syntax is no longer supported"))
(reject "s4-legacy-template-rejected" (file "tests/fixtures/s4-legacy-template.nuc")
        (message "defn 'gmax': legacy 'name:ret' syntax is no longer supported"))
(reject "s17-dup-struct-field-rejected" (file "tests/fixtures/s17-dup-struct-field.nuc")
        (message "defstruct: duplicate field 'x'"))
(reject "s17-rvalue-addr-of-rejected" (file "tests/fixtures/s17-rvalue-addr-of.nuc")
        (message "show: argument 1 has type StrView, which does not match parameter type &StrView"))

; Stage 14 unsafe-namespace.md UN-1 — the `(as TYPE expr)` statically-safe
; conversion form. Its three rejection categories each route to the right tool:
;   lossy/narrowing  -> "use unsafe/cast"
;   raw->ref launder -> mentions "as-ref" (honors pkind-flow-check, which `cast`
;                       bypasses)
;   reinterpretation -> "use unsafe/cast"
(reject "as-lossy-rejected" (file "tests/fixtures/as-lossy.nuc")
        (message "as: lossy conversion from i32 to i8 -- use unsafe/cast"))
(reject "as-raw-to-ref-rejected" (file "tests/fixtures/as-raw-to-ref.nuc")
        (message "unchecked pointer (ptr Rec) where non-null &Rec is required -- use as-ref (checked) or unsafe/cast"))
(reject "as-reinterpret-rejected" (file "tests/fixtures/as-reinterpret.nuc")
        (message "as: reinterpretation from &Sym to &Rec -- use unsafe/cast"))

; Stage 16 as-sugar.md — a value-position `:type` annotation is that same `as`
; cast (`baz:CStr` == `(as CStr baz)`), so the first three pin that it inherits
; `as`'s refusals rather than getting a laxer path of its own; the accept side
; runs as examples/as-sugar.nuc. The first is also the WART being closed: the
; annotation used to be discarded unread, so `x:NoSuchType` compiled silently.
; The fourth holds the excluded spelling: a parenthesised type is claimed by the
; reader's colon-paren fuse in every list context, so it reads as a call and
; must SAY so instead of reporting `unknown: ref`.
(reject "as-sugar-unknown-type" (file "tests/fixtures/as-sugar-unknown-type.nuc")
        (message "unknown type 'NoSuchType' in the annotation 'x:NoSuchType'"))
(reject "as-sugar-lossy" (file "tests/fixtures/as-sugar-lossy.nuc")
        (message "as: lossy conversion from i64 to i32 -- use unsafe/cast"))
(reject "as-sugar-raw-to-ref" (file "tests/fixtures/as-sugar-raw-to-ref.nuc")
        (message "use as-ref (checked) or unsafe/cast (unchecked assertion)"))
(reject "as-sugar-paren" (file "tests/fixtures/as-sugar-paren.nuc")
        (message "'q:(ref ...)' reads as a call here"))
; Stage 15 W9 items 8 and 30 refine the narrowing rule for LITERALS only: an
; operand that provably fits its destination is not lossy, so `as` stops being
; stricter than the implicit coercion at the same slot. `as-lossy.nuc` above
; narrows a parameter -- an unknown runtime value -- and is unaffected, which is
; the distinction these five hold. The accept side is the `w9-as-literal-*` and
; `w9-as-float-literal-*` units of tests/suite-conversions.nuc.
;
; The integer pair holds the boundary at magnitude and at sign. The float trio
; holds two different edges: `-inexact` is the VALUE edge (3.14 is a literal that
; does not round-trip, and admitting it would make `as` round silently),
; `-runtime` is the KNOWLEDGE edge (a parameter is unknown, so the widths alone
; decide and the original rule stands), and `-global-inexact` pins that
; `defvar-init-ir`'s fold reaches the same verdict with the same wording -- a
; second asker that re-derives the rule.
(reject "w9-as-literal-too-big" (file "tests/fixtures/w9-as-literal-too-big.nuc")
        (message "as: lossy conversion from i32 to i8 -- use unsafe/cast"))
(reject "w9-as-literal-signed-into-unsigned" (file "tests/fixtures/w9-as-literal-signed-into-unsigned.nuc")
        (message "as: lossy conversion from i32 to ui8 -- use unsafe/cast"))
(reject "w9-as-float-inexact" (file "tests/fixtures/w9-as-float-inexact.nuc")
        (message "as: lossy conversion from f64 to f32 -- use unsafe/cast"))
(reject "w9-as-float-runtime" (file "tests/fixtures/w9-as-float-runtime.nuc")
        (message "as: lossy conversion from f64 to f32 -- use unsafe/cast"))
(reject "w9-as-float-global-inexact" (file "tests/fixtures/w9-as-float-global-inexact.nuc")
        (message "as: lossy conversion from f64 to f32 -- use unsafe/cast"))

; W9 item 13: an unrecognized list head in type position used to fall out of
; `parse-type-from-node` as null, which every caller reads as "no annotation was
; written". Four positions, one shared fall-through — if a future change patches
; a single caller instead of the predicate, the other three fixtures fail. The
; `-unimported` case is the everyday one (a forgotten `import-use`) and pins
; that the fix reuses `unknown-type-message`'s tiers rather than a local string;
; the `-return` case pins the `:0:` half, which `run_reject` checks on its own.
(reject "w9-unknown-type-ctor-field" (file "tests/fixtures/w9-unknown-type-ctor-field.nuc")
        (message "unknown type: nosuch — not defined anywhere in this compilation unit"))
(reject "w9-unknown-type-ctor-param" (file "tests/fixtures/w9-unknown-type-ctor-param.nuc")
        (message "unknown type: nosuch — not defined anywhere in this compilation unit"))
(reject "w9-unknown-type-ctor-return" (file "tests/fixtures/w9-unknown-type-ctor-return.nuc")
        (message "unknown type: nosuch — not defined anywhere in this compilation unit"))
(reject "w9-unknown-type-ctor-unimported" (file "tests/fixtures/w9-unknown-type-ctor-unimported.nuc") (line 12)
        (message "unknown type: Vector")
        (note "'Vector' is defined in lib/vector.nuc, which no import in this unit reaches"))

; The other mistake class at the same fall-through: a head that IS a type. One
; message for both would lie about this one.
(reject "w9-type-ctor-doubled-annotation" (file "tests/fixtures/w9-type-ctor-doubled-annotation.nuc")
        (message "'i32' is a type, not a type constructor"))

; Stage 14 unsafe-namespace.md UN-2 — `unsafe` is a reserved pseudo-namespace
; (D1): no user code may declare `(ns unsafe)`, which would make `unsafe/foo`
; ambiguous between a reserved op and a real namespace member. (The positive
; `examples/unsafe-spellings.nuc` run — dispatched via the examples/*.nuc loop
; above — covers `as` and the unsafe/cast, unsafe/ptr+, unsafe/funcall-ptr-i32,
; and unsafe/import-private routes.)
(reject "unsafe-ns-reserved-rejected" (file "tests/fixtures/unsafe-ns-reserved.nuc")
        (message "'unsafe' is a reserved namespace name"))

; Stage 14 unsafe-namespace.md UN-5 — the bare legacy spellings (`cast`,
; `funcall-ptr-*`, `ptr+`, `unsafe-import-private`) are retired: each dispatch
; site now dies with a targeted error naming its replacement instead of
; silently working as an alias (D6).
(reject "un5-bare-cast-rejected" (file "tests/fixtures/un5-bare-cast.nuc")
        (message "'cast' was split in Stage 14: use 'as' (safe) or 'unsafe/cast' (unchecked)"))
(reject "un5-bare-ptr-plus-rejected" (file "tests/fixtures/un5-bare-ptr-plus.nuc")
        (message "'ptr+' was split in Stage 14: use 'unsafe/ptr+'"))
(reject "un5-bare-funcall-ptr-rejected" (file "tests/fixtures/un5-bare-funcall-ptr.nuc")
        (message "'funcall-ptr-i32' was split in Stage 14: use 'unsafe/funcall-ptr-i32'"))
(reject "un5-bare-import-private-rejected" (file "tests/fixtures/un5-bare-import-private.nuc")
        (message "'unsafe-import-private' was split in Stage 14: use 'unsafe/import-private'"))

; Stage 14 attributes.md AT-3 — the old postfix volatile spellings are retired:
; both the list form `(T volatile)` and the colon-sugared `T:volatile` (which
; reduces to the same trailing-symbol shape via split-colon-segments) now die
; with a targeted error naming the `:volatile` attribute-slot replacement,
; instead of silently stripping the trailing symbol and calling
; type-with-volatile as before AT-3.
(reject "at3-postfix-volatile-rejected" (file "tests/fixtures/at3-postfix-volatile.nuc")
        (message "postfix 'volatile' is retired: use the ':volatile' attribute"))
(reject "at3-colon-volatile-rejected" (file "tests/fixtures/at3-colon-volatile.nuc")
        (message "postfix 'volatile' is retired: use the ':volatile' attribute"))

; --- Stage 15 W5a: `\x` string escapes --------------------------------------
; design/stage15-stress-test/ergonomics.md §W5a. A `\x` escape with no
; following hex digit is a reader error. The pattern includes the `:6:` line
; prefix on purpose: the diagnostic must be attributed to the literal's own
; line, never line 0 (cf. run_no_line_zero).
(reject "w5a-hex-escape-no-digit-rejected" (file "tests/fixtures/w5a-hex-escape-no-digit.nuc") (line 6)
        (message "\\x escape needs at least one hex digit"))
(reject "w2a-mixed-sign" (file "tests/fixtures/w2a-mixed-sign.nuc") (line 10)
        (message "mixed signed/unsigned operands — use explicit cast"))
(reject "w2a-mixed-sign-cmp" (file "tests/fixtures/w2a-mixed-sign-cmp.nuc") (line 11)
        (message ">: mixed signed/unsigned operands — use explicit cast"))

; --- Stage 15 W2b: a named integer constant behaves like the literal ---------
; design/stage15-stress-test/literal-typing.md section W2b. The positive matrix
; (a defconst against {i32, i64, ui32, ui64} in both operand orders, each line
; paired with the identical inline-literal spelling; the enum-member case; the
; BIG-value case; the vararg path) is examples/defconst-literal-typing.nuc, run
; by the examples/*.nuc loop above. The committed boot compiler FAILS to compile
; that file, which is the teeth.
;
; Here: the negative half. Two properties must survive the fix -- the provenance
; is read through the SCOPE (so a shadowing local is not a literal), and it
; carries the VALUE (so an out-of-range narrowing is rejected rather than
; wrapped, at both the coerce-int-val chokepoint and the global-initializer
; path, and for a named constant exactly as for the literal it names).
(reject "w2b-shadow-local" (file "tests/fixtures/w2b-shadow-local.nuc") (line 12)
        (message "<: mixed signed/unsigned operands — use explicit cast"))
(reject "w2b-const-narrow" (file "tests/fixtures/w2b-const-narrow.nuc") (line 10)
        (message "integer literal 5000000000 does not fit i32"))
(reject "w2b-defvar-const-narrow" (file "tests/fixtures/w2b-defvar-const-narrow.nuc") (line 7)
        (message "defvar: constant 'BIG' (5000000000) does not fit i32"))
(reject "w2b-defvar-lit-narrow" (file "tests/fixtures/w2b-defvar-lit-narrow.nuc") (line 5)
        (message "defvar: integer literal 5000000000 does not fit i32"))
(reject "w2d-float-into-int" (file "tests/fixtures/w2d-float-into-int.nuc") (line 9)
        (message "let: init type mismatch for 'a'"))
(reject "w2d-mixed-float-int-binop" (file "tests/fixtures/w2d-mixed-float-int-binop.nuc") (line 9)
        (message "mixed float and non-float operands — use explicit cast"))
(reject "w2d-dispatch-no-narrow" (file "tests/fixtures/w2d-dispatch-no-narrow.nuc") (line 15)
        (message "no matching method for overloaded 'tk' with argument types (f64)"))

; --- Stage 15 W4a: located diagnostics --------------------------------------
; design/stage15-stress-test/diagnostics.md §W4a. Every entry below reported
; `:0:` before W4a. The location is part of the assertion, not decoration.
(reject "w4a-undefined-value" (file "tests/fixtures/w4a-undefined-value.nuc") (line 8)
        (message "undefined: missing-thing"))
(reject "w4a-suggest-spelling" (file "tests/fixtures/w4a-suggest-spelling.nuc") (line 6)
        (message "unknown: printfx (did you mean 'printf'?)"))
(reject "w4a-let-null-ref" (file "tests/fixtures/w4a-let-null-ref.nuc") (line 7)
        (message "unchecked pointer where non-null (ref ...) is required"))
(reject "w4a-bare-cast-head" (file "tests/fixtures/w4a-bare-cast-head.nuc") (line 7)
        (message "'cast' was split in Stage 14"))

; --- Stage 15 W4b: defconst annotation rejected + sibling-definer sweep ----
; design/stage15-stress-test/diagnostics.md §W4b. `defconst` never takes a
; type annotation (its value is always ty-i32 from an integer literal), so
; `(defconst K:i32 2)` is rejected at its own line rather than silently
; registering nothing under the literal key "K:i32". The same silent-
; registration bug recurred, unannounced, in every sibling top-level definer
; whose own name is never annotated — each is pinned here too.
(reject "w4a-defconst-annotated" (file "tests/fixtures/w4a-defconst-annotated.nuc") (line 7)
        (message "defconst: takes no type annotation; write (defconst K 2)"))
(reject "w4b-defconst-paren" (file "tests/fixtures/w4b-defconst-paren.nuc") (line 7)
        (message "defconst: takes no type annotation; write (defconst K 2)"))
(reject "w4b-defenum-annotated" (file "tests/fixtures/w4b-defenum-annotated.nuc") (line 9)
        (message "defenum: takes no type annotation; write (defenum E ...)"))
(reject "w4b-defstruct-annotated" (file "tests/fixtures/w4b-defstruct-annotated.nuc") (line 9)
        (message "defstruct: takes no type annotation; write (defstruct S ...)"))
(reject "w4b-defprotocol-annotated" (file "tests/fixtures/w4b-defprotocol-annotated.nuc") (line 9)
        (message "defprotocol: takes no type annotation; write (defprotocol P ...)"))
(reject "w4b-defmacro-annotated" (file "tests/fixtures/w4b-defmacro-annotated.nuc") (line 7)
        (message "defmacro: takes no type annotation; write (defmacro m ...)"))
(reject "w4b-defunion-annotated" (file "tests/fixtures/w4b-defunion-annotated.nuc") (line 6)
        (message "defunion: takes no type annotation; write (defunion U ...)"))
(reject "w4b-deferror-annotated" (file "tests/fixtures/w4b-deferror-annotated.nuc") (line 7)
        (message "deferror: takes no type annotation; write (deferror MyErr \"message\")"))

; Found (not silent, but wrong location) while sweeping defvar the same way:
; `(defvar x 3)` -- no annotation at all -- already died with the right
; message but at line 0 (name-node is a bare interned NODE-SYM).
(reject "w4b-defvar-missing-type" (file "tests/fixtures/w4b-defvar-missing-type.nuc") (line 9)
        (message "defvar: missing :type on 'x'"))

; --- Stage 15 W5f: an empty list `()` never segfaults ------------------------
; design/stage15-stress-test/ergonomics.md §W5f. `()` reads as a NULL node (an
; empty cons list), and a raw `(n kind)` / `(n line)` on it faults. Each fixture
; below was a confirmed SIGSEGV-with-no-output before W5f; run_reject_at fails on
; a crash too (no message to grep), so these double as segfault regressions.
(reject "w5f-empty-union-member" (file "tests/fixtures/w5f-empty-union-member.nuc") (line 11)
        (message "expected a name:type declaration, found the empty list '()'"))
(reject "w5f-empty-param" (file "tests/fixtures/w5f-empty-param.nuc") (line 7)
        (message "expected a name:type declaration, found the empty list '()'"))
(reject "w5f-empty-expr" (file "tests/fixtures/w5f-empty-expr.nuc") (line 6)
        (message "'()' is not an expression -- the empty list has no value"))
(reject "w5f-empty-defunion-arm" (file "tests/fixtures/w5f-empty-defunion-arm.nuc") (line 4)
        (message "defunion: arm cannot be the empty list '()'"))

; --- Stage 15 W4c: unterminated forms point at the imbalance -----------------
; design/stage15-stress-test/diagnostics.md §W4c. The reader already reported the
; innermost unclosed form's OPENING line; what it lacked was the second number --
; the first line that opens a new form in column 0 while a form is still open,
; which is where an earlier missing `)` first became observable. Each entry below
; pins BOTH: the `loc` argument carries the primary `path:line: error: message`
; and the `pattern` argument carries the note with the second number, so a
; regression in either half fails the test. (run_reject_at's loc is a literal
; grep -F, so it can pin the message text as well as the location.)
(reject "w4c-unterminated-deep" (file "tests/fixtures/w4c-unterminated-deep.nuc") (line 12)
        (message "unterminated list")
        (note "line 23 starts a new form in column 0 while 1 form(s) are still open"))
(reject "w4c-unterminated-deep-many" (file "tests/fixtures/w4c-unterminated-deep-many.nuc") (line 12)
        (message "unterminated list")
        (note "line 18 starts a new form in column 0 while 6 form(s) are still open"))

; No column-0 candidate exists (the imbalance is in the file's last form): the
; alternative note must appear, and since the two notes are the arms of one
; if/else, pinning this one also asserts no bogus second number is invented.
(reject "w4c-unterminated-last-form" (file "tests/fixtures/w4c-unterminated-last-form.nuc") (line 9)
        (message "unterminated list")
        (note "end of file reached with 3 form(s) still open"))

; A bracket kind other than `(`: depth tracking spans ( [ { #{ , and the note
; names the closer the form is actually waiting for.
(reject "w4c-unterminated-bracket" (file "tests/fixtures/w4c-unterminated-bracket.nuc") (line 7)
        (message "unterminated vector literal")
        (note "line 9 starts a new form in column 0 while 4 form(s) are still open -- a ']' is probably missing"))

; The extra-`)`-in-a-let-binding-list shape, both ways it can land: still
; balanced (caught at emit, in emit-let) and no longer balanced (caught by the
; reader at the excess `)`, with the note bounding the search to one form).
(reject "w4c-let-extra-paren" (file "tests/fixtures/w4c-let-extra-paren.nuc") (line 11)
        (message "let: 'b:i32' is a body form, not a binding -- an extra ')' probably ended the binding list early"))
(reject "w4c-stray-close-paren" (file "tests/fixtures/w4c-stray-close-paren.nuc") (line 13)
        (message "unexpected )")
        (note "the form opened at line 10 is already closed -- look for an extra ')' between lines 10 and 13"))

; --- Stage 15 W4d: errors that name the macro instead of the mistake ---------
; design/stage15-stress-test/diagnostics.md §W4d. `case`'s documented-but-wrong
; nested-clause shape used to die with the opaque "value is not callable: no
; `invoke` method is defined for this type" -- naming the mechanism (an int
; literal in call position), not the mistake. Fixed at the one chokepoint every
; non-callable head funnels through (emit-invoke-with-callee), not inside the
; `case` macro body: a macro body is ordinary user-scope Nucleus code and
; `die-at`/`report-at` are only in scope for the compiler's own source, not a
; user program's macro expansions (confirmed empirically -- a `defmacro` body
; calling `die-at` fails `unknown: die-at`).
(reject "w4d-case-clause-form" (file "tests/fixtures/w4d-case-clause-form.nuc") (line 16)
        (message "case takes flat value/result pairs, not clauses: (case x 1 \"one\" 2 \"two\" \"other\")"))

; examples/case.nuc (the real flat syntax) is covered as a regression by the
; ordinary examples/*.nuc + tests/expected/case.out loop above -- no separate
; fixture needed here.
;
; One-armed `if` used to die with the generic, unlocated-by-name
; `macro: wrong number of args`. `if` is a fixed 3-arg macro
; (test/then/else); there is no one-armed `if`, only `when`/`unless`.
(reject "w4d-if-one-armed" (file "tests/fixtures/w4d-if-one-armed.nuc") (line 11)
        (message "if requires an else branch; use (when test then…) for a guard"))

; The generic arg-count messages themselves, now naming the macro and both
; counts instead of the bare "macro: wrong number of args" / "macro: not
; enough args".
(reject "w4d-macro-too-many-args" (file "tests/fixtures/w4d-macro-too-many-args.nuc") (line 11)
        (message "macro 'for': expects 4 args, got 5"))
(reject "w4d-macro-too-few-args" (file "tests/fixtures/w4d-macro-too-few-args.nuc") (line 12)
        (message "macro 'case': expects at least 1 args, got 0"))

; --- Stage 15 W3a: opaque forward-declared C types ---------------------------
; design/stage15-stress-test/cheader.md §1.6. `struct Foo;` used to be skipped
; outright, so the type never registered and any later `ptr:Foo` died
; `unknown type: Foo` — C's standard opaque-handle idiom (FILE, SDL_Window,
; Mix_Music) was simply unusable. It now registers layout-less, is legal behind
; a pointer, and every by-value use is refused at its own line naming the header
; declaration. The runnable half is examples/cheader-opaque.nuc (a real
; fopen/fprintf/fgets round trip through `ptr:FILE`, plus forward-declaration-
; then-definition upgrades); the rejections are pinned here.
(reject "w3a-opaque-sizeof" (file "tests/fixtures/w3a-opaque-sizeof.nuc") (line 9)
        (message "sizeof: 'CHOpaque' is an opaque type declared at "))
(reject "w3a-opaque-alloca" (file "tests/fixtures/w3a-opaque-alloca.nuc") (line 6)
        (message "alloca: 'CHOpaque' is an opaque type declared at "))
(reject "w3a-opaque-field" (file "tests/fixtures/w3a-opaque-field.nuc") (line 7)
        (message "field access: 'CHOpaque' is an opaque type declared at "))
(reject "w3a-opaque-param" (file "tests/fixtures/w3a-opaque-param.nuc") (line 6)
        (message "defn parameter: 'CHOpaque' is an opaque type declared at "))
(reject "w3a-opaque-return" (file "tests/fixtures/w3a-opaque-return.nuc") (line 5)
        (message "defn return type: 'CHOpaque' is an opaque type declared at "))

; W3a also gave `unknown type:` a location: resolving a defn signature used to
; blame the defn's NAME node, an interned NODE-SYM whose line is always 0. Both
; halves (parameter, return) are pinned, and both fixtures also feed the
; run_no_line_zero sweep above.
(reject "w3a-unknown-type-param" (file "tests/fixtures/w3a-unknown-type-param.nuc") (line 6)
        (message "unknown type: NoSuchTypeHere"))
(reject "w3a-unknown-type-return" (file "tests/fixtures/w3a-unknown-type-return.nuc") (line 3)
        (message "unknown type: AlsoNoSuchType"))

; A parameter spelling that names no type is a located error, not a default —
; and `:rest`/`:optional` are defn-only (the marker used to be counted as an
; extra i32 parameter, so the declared arity silently disagreed).
(reject "w3c-declare-unknown-type" (file "tests/fixtures/w3c-declare-unknown-type.nuc") (line 4)
        (message "unknown type: NoSuchDeclParamType"))
(reject "w3c-declare-rest" (file "tests/fixtures/w3c-declare-rest.nuc") (line 6)
        (message "declare: ':rest' is not supported in a declaration"))

; --- Stage 15 W5c: a `defvar` global may be typed CStr ----------------------
; design/stage15-stress-test/ergonomics.md §W5c (findings §3.7). The positive
; matrix -- both literal spellings (plain "…" and c"…"), explicit `null`, no
; init, `:const`, the private `defvar-`, `set!`, and every global handed to a
; libc function declared `const char *` -- is examples/cstr-defvar.nuc, run by
; the examples/*.nuc loop above against tests/expected/cstr-defvar.out. It is
; checked BY VALUE (strlen/strcmp results, %s output) rather than by exit code,
; because "it compiles" was never the question: the pre-W5c workaround compiled
; too. That example also pins the segfault W5c fixed -- `(= cstr null)` lowered
; to `strcmp(ptr, null)`, undefined behaviour in C and a crash under glibc.
;
; Here: the boundary the widened gate must NOT cross. `defvar-init-ir` now gates
; a string literal and `null` on `is-ptr-like` instead of a bare `TY-PTR` kind,
; which admits `CStr` -- and must still admit nothing else. (The `null` gate also
; admits TY-FN by name since the fn-pointer-global fix below, which is why its
; message names three admissible spellings; a string literal still does not.)
(reject "w5c-string-into-int" (file "tests/fixtures/w5c-string-into-int.nuc") (line 5)
        (message "defvar: string literal requires ptr or CStr type, not i32"))
(reject "w5c-null-into-int" (file "tests/fixtures/w5c-null-into-int.nuc") (line 4)
        (message "defvar: null requires ptr, CStr or a function-pointer type, not i32"))

;
; The carve-out, pinned in the other direction. `CStr` is flow-exempt (a null
; `char*` is ordinary C), and `defvar-init-ir` states that exemption as its own
; early return rather than letting it ride on `is-ptr-like`. W6 (below) has since
; added a `pkind-flow-check` to the `TY-PTR` path beside it; this test is what
; fails if `CStr` ever gets swept up with `ptr`.
(accept "w5c-cstr-null-exempt" (file "tests/fixtures/w5c-cstr-null-exempt.nuc"))

; --- Stage 15 W6: null into a non-null global -------------------------------
; `defvar-init-ir` is a CONSTANT RENDERER: it never routes through
; `coerce-int-val` (src/abi.nuc), the chokepoint every value-position assignment
; passes for its Phase-F `pkind-flow-check`. So `(defvar g:ptr:Thing null)`
; compiled clean and segfaulted on first use, while the identical local
; `(let (p:ptr:Thing null) …)` was correctly rejected -- one rule living in one
; path and not the other. The fix calls the SAME predicate from the global path
; (source type = `ty-raw`, exactly what `emit-symbol-ref` gives the `null`
; symbol), so the two cannot drift; these tests pin both directions.
;
; Rejections: a TYPED non-null pointer, in both spellings. The location is pinned
; (not just the message) because the init node is the interned symbol `null`,
; whose own line is always 0 -- the diagnostic has to borrow the enclosing
; `defvar` form's line via `node-line`, and a regression there reports `:0:`.
(reject "w6-defvar-null-ptr-elem" (file "tests/fixtures/w6-defvar-null-ptr-elem.nuc") (line 11)
        (message "defvar: unchecked pointer where non-null (ref ...) is required"))
(reject "w6-defvar-null-ref" (file "tests/fixtures/w6-defvar-null-ref.nuc") (line 8)
        (message "defvar: unchecked pointer where non-null (ref ...) is required"))

;
; Stage 15 W9 item 7: the same rule, for the source kind it never reached. A
; `CStr` is `TY-CSTR`, so `pkind-flow-check`'s `TY-PTR`-only guard let it launder
; a null into a typed non-null slot — global and local alike, since the defvar
; renderer calls the same predicate — and `as-ptr-convert` carried a second copy
; of the premise. Measured before the fix: all three of these compiled clean and
; segfaulted; the corpus contained exactly ONE conversion that this rejects
; (lib/hash.nuc's CStr Hash conformance), now null-guarded.
(reject "w9-cstr-into-ref-defvar" (file "tests/fixtures/w9-cstr-into-ref-defvar.nuc") (line 17)
        (message "defvar: unchecked pointer where non-null (ref ...) is required"))
(reject "w9-cstr-into-ref-let" (file "tests/fixtures/w9-cstr-into-ref-let.nuc") (line 8)
        (message "assignment: unchecked pointer where non-null (ref ...) is required"))
(reject "w9-cstr-as-typed-ptr" (file "tests/fixtures/w9-cstr-as-typed-ptr.nuc") (line 16)
        (message "as: unchecked pointer CStr where non-null &W9C7A is required"))

; ...but it is NOT admitted to the strcmp lowering. This is the tripwire against
; "fixing" item 18 by widening `is-ptr-like` to contain TY-FN, which would turn
; the line below into strcmp(hook, msg) — a function's code read as text.
(reject "w9-fnptr-cstr-compare" (file "tests/fixtures/w9-fnptr-cstr-compare.nuc") (line 15)
        (message "=: a CStr compares only with a CStr or pointer"))

; ...but ONLY the literal. Gating item 20 on `is-ptr-repr` instead of on
; Val.is-nlit would compile the line below and make any data pointer callable.
(reject "w9-fnptr-null-launder" (file "tests/fixtures/w9-fnptr-null-launder.nuc") (line 17)
        (message "let: init type mismatch for 'f'"))

;
; Acceptances: every NULLABLE or contract-free pointer destination stays legal --
; elem-less bare `ptr` (with and without an init), `(raw T)` / `raw:T`, `?ptr:T`,
; and `CStr`. The bare-`ptr` cases are the load-bearing ones: `ptr` is PTR-REF
; since the Phase-F flip, so only `pkind-flow-check`'s untyped-destination
; refinement keeps them compiling, and this compiler's own source has ~1550 such
; bindings -- narrowing that refinement would take the bootstrap with it.
(accept "w6-defvar-null-accepts" (file "tests/fixtures/w6-defvar-null-accepts.nuc"))

; --- Stage 15 W8: a function-pointer-typed global ---------------------------
; `(defvar h:(fn ret)(params) …)` could not be declared at all. Two stacked
; defects: `name-existing-kind` called any TY-FN-typed global Sym "a function",
; so once G-0's prescan defined that Sym the `defvar` collided with itself; and
; behind it `defvar-init-ir`'s `null` gate tested `is-ptr-like`, which excludes
; TY-FN by design. The positive matrix -- explicit `null`, no init, a runtime
; initializer, `set!`, both call spellings, and reassignment -- is
; examples/fnptr-global.nuc, run by the examples/*.nuc loop above against
; tests/expected/fnptr-global.out and checked BY VALUE: a hook wired to the
; wrong symbol, or an @__nucleus_init that never ran, links and exits 0.
;
; The two boundaries that must hold. First, the null admission is TY-FN-only:
; `ptr:(fn …)` is a pointer TO a function pointer, an ordinary PTR-REF, and W6's
; gate still refuses `null` there. The location is pinned for the same reason
; W6's are -- the init node is the interned symbol `null`, whose own line is 0.
(reject "w8-fnptr-null-still-gated" (file "tests/fixtures/w8-fnptr-null-still-gated.nuc") (line 12)
        (message "defvar: unchecked pointer where non-null (ref ...) is required"))

; Second, the `is-local` conjunct must not silence a real cross-kind collision.
; g0-value-fn-collision-order1/2 pin the plain (i32-typed) shape; this is the
; fn-typed one, i.e. exactly the shape the new conjunct changes the answer for.
;
; Stage 15 B5 re-pointed the LOCATION and the noun, not the verdict. The guard
; now asks the shared binding table for the first binding whose kind is NOT the
; one being defined (name-resolution.md §13.3), so the collision is reported at
; whichever definer is EMITTED first — here the `defn`, naming the
; `defvar` — instead of only at the second one. Before B5 the first definer's
; own guard was silently masked by its own prescan registration, which is the
; same class of hole this chunk exists to close; the pair is still refused, and
; `run_reject_at` still proves no binary is produced.
(reject "w8-fnptr-global-name-collision" (file "tests/fixtures/w8-fnptr-global-name-collision.nuc") (line 19)
        (message "'f' already names a value — a symbol may name only one kind of thing"))

; --- Stage 15 W5d: array literal ergonomics ---------------------------------
; design/stage15-stress-test/ergonomics.md §3.9 + §3.10. The positive matrix is
; examples/array-literal-ergonomics.nuc, run by the examples/*.nuc loop above:
; bare struct compound literals as array elements (positional, designated and
; mixed with the old `(deref …)` spelling), the zero-fill of an unspecified
; struct/CStr slot, the same relaxation at the sibling typed slots (local, field,
; aset!, by-value return), and the §3.10 `:ptr` bindings. The committed boot
; compiler FAILS on that file (`array: type mismatch in positional initializer`),
; which is the teeth.
;
; Here: the three boundaries the relaxations must NOT cross.
; 1. §3.9 stays type-directed — a compound literal of a DIFFERENT struct is
;    still a mismatch (the load is gated on the pointee's StructDef).
; 2. The implicit load is a `deref`, so it inherits `deref`'s Stage 10
;    obligation: a `?T` source must be narrowed first, or the sugar would be a
;    nullability hole the explicit spelling does not have.
; 3. §3.10 is SYNTACTIC (an `(array T …)` init and nothing else). A bare `:ptr`
;    is the void*-style erasure hatch; inferring the element type generally
;    would re-route multimethod dispatch across every such binding, so a `:ptr`
;    bound from an `alloca` must stay elem-less.
(reject "w5d-array-wrong-struct" (file "tests/fixtures/w5d-array-wrong-struct.nuc") (line 9)
        (message "array: type mismatch in positional initializer"))
(reject "w5d-struct-slot-maybe-null" (file "tests/fixtures/w5d-struct-slot-maybe-null.nuc") (line 13)
        (message "assignment: value may be null"))
(reject "w5d-elemless-not-inferred" (file "tests/fixtures/w5d-elemless-not-inferred.nuc") (line 13)
        (message "aref: operand must be typed pointer"))
(reject "g1-fold-range" (file "tests/fixtures/g1-fold-range.nuc") (line 5)
        (message "defvar: constant expression value 6000000000 does not fit i32"))
(reject "g1-fold-overflow" (file "tests/fixtures/g1-fold-overflow.nuc") (line 3)
        (message "defvar: constant initializer overflows 64-bit signed integer arithmetic"))
(reject "g1-div-zero" (file "tests/fixtures/g1-div-zero.nuc") (line 4)
        (message "defvar: division by zero in constant initializer"))
(reject "g1-rem-zero" (file "tests/fixtures/g1-rem-zero.nuc") (line 2)
        (message "defvar: remainder by zero in constant initializer"))
(reject "g1-shift-range" (file "tests/fixtures/g1-shift-range.nuc") (line 3)
        (message "defvar: shift amount 64 out of range in constant initializer"))
(reject "g1-as-lossy" (file "tests/fixtures/g1-as-lossy.nuc") (line 5)
        (message "as: lossy conversion from i64 to i32 -- use unsafe/cast"))
(reject "g1-as-null-launder" (file "tests/fixtures/g1-as-null-launder.nuc") (line 7)
        (message "defvar: unchecked pointer where non-null (ref ...) is required"))
(reject "g1-addr-of-const" (file "tests/fixtures/g1-addr-of-const.nuc") (line 4)
        (message "defvar: ref: 'G1K' is a compile-time constant and has no address"))
(reject "g1-not-constant" (file "tests/fixtures/g1-not-constant.nuc") (line 5)
        (message "defvar: init must be a compile-time constant"))
(accept "g2-anon-struct-field" (file "tests/fixtures/g2-anon-struct-field.nuc"))
(reject "g2-array-param" (file "tests/fixtures/g2-array-param.nuc") (line 4)
        (message "(array T N) is a storage type"))
(reject "g2-array-return" (file "tests/fixtures/g2-array-return.nuc") (line 3)
        (message "(array T N) is a storage type"))
(reject "g2-array-let" (file "tests/fixtures/g2-array-let.nuc") (line 4)
        (message "(array T N) is a storage type"))
(reject "g2-array-ptr-elem" (file "tests/fixtures/g2-array-ptr-elem.nuc") (line 4)
        (message "(array T N) is a storage type"))
(reject "g2-array-nested" (file "tests/fixtures/g2-array-nested.nuc") (line 3)
        (message "(array T N) is a storage type"))
(reject "g2-array-generic-arg" (file "tests/fixtures/g2-array-generic-arg.nuc") (line 5)
        (message "(array T N) is a storage type"))
(reject "g2-len-nonconst" (file "tests/fixtures/g2-len-nonconst.nuc") (line 4)
        (message "(array T N): length must be a compile-time integer constant"))
(reject "g2-len-zero" (file "tests/fixtures/g2-len-zero.nuc") (line 4)
        (message "(array T N): length must be positive, got 0"))
(reject "g2-index-range" (file "tests/fixtures/g2-index-range.nuc") (line 3)
        (message "index 5 is out of range for a 3-element array"))
(reject "g2-index-twice" (file "tests/fixtures/g2-index-twice.nuc") (line 3)
        (message "index 1 specified twice"))
(reject "g2-too-many" (file "tests/fixtures/g2-too-many.nuc") (line 3)
        (message "too many initializers for a 2-element array"))
(reject "g2-elem-mismatch" (file "tests/fixtures/g2-elem-mismatch.nuc") (line 3)
        (message "array initializer element type i64 does not match the declared element type i32"))
(reject "g2-elem-range" (file "tests/fixtures/g2-elem-range.nuc") (line 4)
        (message "defvar: constant expression value 6000000000 does not fit i32"))
(reject "g2-scalar-init" (file "tests/fixtures/g2-scalar-init.nuc") (line 2)
        (message "slot must be initialized with an (array T ...) literal"))
(reject "g2-struct-scalar-init" (file "tests/fixtures/g2-struct-scalar-init.nuc") (line 5)
        (message "a P slot must be initialized with a (P ...) compound literal"))
(reject "g2-struct-field-twice" (file "tests/fixtures/g2-struct-field-twice.nuc") (line 3)
        (message "defvar: field 'x' specified twice"))
(reject "g2-struct-no-field" (file "tests/fixtures/g2-struct-no-field.nuc") (line 3)
        (message "defvar: no field 'z' on struct 'P'"))
(reject "g2-field-assign" (file "tests/fixtures/g2-field-assign.nuc") (line 5)
        (message "set!: field 'xs': an (array T N) is storage, not a value"))
(reject "g2-set-global" (file "tests/fixtures/g2-set-global.nuc") (line 4)
        (message "set!: 'g': an (array T N) is storage, not a value"))

; The queue predicate is `defvar-init-ir`'s own answer, so a runtime initializer
; inherits every check the constant renderer already applied at the same slot —
; §2.8's `pkind-flow-check` most of all, which is the whole acceptance argument
; for combining declaration with initialization. Pinned at the `defvar`, not at
; some synthesized set! the user never wrote.
(reject "g3-init-raw-into-ref" (file "tests/fixtures/g3-init-raw-into-ref.nuc") (line 9)
        (message "unchecked pointer where non-null (ref ...) is required"))
(reject "g3-init-type-mismatch" (file "tests/fixtures/g3-init-type-mismatch.nuc") (line 6)
        (message "set!: type mismatch for 'g3-bad'"))

; Positions where a runtime initializer has nowhere to run. Each must be a
; located refusal rather than a slot that silently stays zero.
(reject "g3-init-in-compile-time" (file "tests/fixtures/g3-init-in-compile-time.nuc") (line 6)
        (message "a compile-time or macro body cannot have"))
(reject "g3-init-const-storage" (file "tests/fixtures/g3-init-const-storage.nuc") (line 6)
        (message "is :const, so its initializer must be a compile-time constant"))
(reject "g4-forward-ref" (file "tests/fixtures/g4-forward-ref.nuc") (line 12)
        (message "defvar: the initializer for 'g4-fwd-a' names global 'g4-fwd-b', whose own defvar has not been reached yet")
        (note "'g4-fwd-b' is declared at tests/fixtures/g4-forward-ref.nuc:13"))
(reject "g4-init-cycle" (file "tests/fixtures/g4-init-cycle.nuc") (line 10)
        (message "defvar: the initializer for 'g4-cyc-a' names global 'g4-cyc-b'")
        (note "'g4-cyc-b' is declared at tests/fixtures/g4-init-cycle.nuc:11"))
(reject "g4-self-ref" (file "tests/fixtures/g4-self-ref.nuc") (line 6)
        (message "defvar: the initializer for 'g4-self' names 'g4-self' itself")
        (note "a global's initializer runs at the point its own defvar is reached, so it cannot read the global it is initializing"))

; The two carve-outs, pinned as ACCEPTING here as well as by value above: a
; later, stricter walk that swallowed either would break programs that compile
; today (examples/g1-const-init.nuc's forward `&g-later-target` is the
; in-tree instance of the first).
(accept "g4-addr-of-forward-clean" (file "tests/fixtures/g4-addr-of-forward.nuc"))
(accept "g4-laundered-call-clean" (file "tests/fixtures/g4-laundered-call.nuc"))

; --- Stage 15 W8 G-5: eliminate compiler-init, then flip ---------------------
; design/global-init.md §5 "G-5". The migration itself is verified by the whole
; suite (the compiler that runs every test below IS the migrated compiler), plus
; `assert-compiler-arena-backed`, which main/repl-main call on every invocation.
;
; The FLIP (acceptance criterion (B)): a `defvar` whose type is a non-null typed
; pointer must be initialized. This closes nullability.md §1.5's remaining half
; and makes `ptr:T` mean non-null at a global as it does everywhere else.
(reject "g5-noinit-ref" (file "tests/fixtures/g5-noinit-ref.nuc") (line 12)
        (message "defvar: 'g5-thing' has a non-null pointer type but no initializer"))

; ...and the note that tells you the two ways out, which is the whole reason the
; rule is tolerable at all.
(reject "g5-noinit-ref-note" (file "tests/fixtures/g5-noinit-ref.nuc") (line 12)
        (message "has a non-null pointer type but no initializer")
        (note "declare it nullable (`?&T`)"))

; The carve-outs the flip must NOT swallow, all four in one fixture: `raw`, `?T`,
; an elem-less bare `ptr` (~1550 of them in this compiler's own source), and
; CStr. These are pkind-flow-check's own exemptions, inherited by calling it
; rather than re-derived — a hand-written `(= (ty pkind) PTR-REF)` here would
; have broken every bare `:ptr` global in the tree.
(accept "g5-noinit-carve-outs" (file "tests/fixtures/g5-noinit-raw-ok.nuc"))
(reject "w5e-ns-hash-reserved" (file "tests/fixtures/w5e-ns-hash-reserved.nuc")
        (message "a namespace name may not begin with '#'"))

; --- Stage 15 W7: a bare selector symbol may be a value ---------------------
; design/stage15-stress-test/selector-ambiguity.md. The positive matrix is
; examples/selector-value.nuc, run by the examples/*.nuc loop above against
; tests/expected/selector-value.out: a local key in head position, through
; `get`, and through `invoke` (which now falls back to `get`); a string-literal
; key; an absent key; plain field access with a same-named local in scope; and
; the collision case where the local names a REAL field, which still resolves to
; the field with `invoke` as the escape hatch. Checked by value, not by exit
; code — "it compiles" was never the question for the field-access half.
;
; Since step 3 the selector IS the local: `(p k)` reads `k` as a computed
; selector, and an i32 is not one. The old W7 demotion this pinned is gone --
; there is nothing left to demote when a bare symbol was never a field.
(reject "w7-local-not-a-field" (file "tests/fixtures/w7-local-not-a-field.nuc") (line 9)
        (message "computed selector must evaluate to a symbol (ptr)"))

; And the hint must not leak onto an ordinary typo — no local named `zz`, so the
; message stays the plain unadorned one.
(reject "w7-plain-typo" (file "tests/fixtures/w7-plain-typo.nuc") (line 7)
        (message "get: no field 'zz' on struct 'Point'"))

; --- Stage 15 W9 defects 11 + 12 -----------------------------------------------
; design/stage15-stress-test/progress.md, W9 rows 11 and 12 — a matched pair.
;
; Defect 11: FOUR call sites passed more substitutions than their fixed-arity
; format helper takes (context/conventions.md opens with this trap), so snprintf
; read a garbage vararg. The two `%d %d` sites printed a garbage COUNT rather
; than crashing ("got 100", "got 115"), which is why nobody noticed; the two
; `%s %s` sites dereferenced the garbage and SEGFAULTED the compiler with no
; output at all. All four were cold paths a green suite had never executed, so
; the durable half of the fix is that each now HAS a test: a corrected format
; string nothing runs is one edit away from regressing.
(reject "w9-fnptr-arity" (file "tests/fixtures/w9-fnptr-arity.nuc") (line 12)
        (message "call: expected 2 args, got 1"))
(reject "w9-boxedfn-arity" (file "tests/fixtures/w9-boxedfn-arity.nuc") (line 9)
        (message "BoxedFn call: expected 1 args, got 2"))

; The two that SEGFAULTED before the fix (both substitutions are `%s`).
; w9-dyn-not-protocol was RE-POINTED by defect 21 (see the fixture's own header):
; it used to reach this message by exploiting the protocol/conformance key
; mismatch that defect 21 fixed, and now reaches it the honest way — a `dyn`
; position naming a protocol nothing declared. The `(extend Cat dp/Describe)`
; above it now succeeds, which is the fix.
(reject "w9-dyn-not-protocol" (file "tests/fixtures/w9-dyn-not-protocol.nuc") (line 36)
        (message "(dyn dp/Missing): 'dp/Missing' is not a declared protocol"))
(reject "w9-extend-super-not-protocol" (file "tests/fixtures/w9-extend-super-not-protocol.nuc") (line 11)
        (message "extend: 'Describe' is a protocol, so its supertype 'Plain' must be a protocol too"))

; Defect 12: a wrong-arity call to a SOLITARY `defn` was not diagnosed at all —
; `(f 1 2)` against a one-parameter `f` emitted `call i32 @f(i32 1, i32 2)`,
; linked and ran. The rule now lives in ONE function (`call-arity-ok` /
; `check-call-arity`, src/nucleusc.nuc) that the direct, indirect and BoxedFn
; paths all CALL, so they cannot drift. Both directions are errors.
(reject "w9-call-too-many" (file "tests/fixtures/w9-call-too-many.nuc") (line 9)
        (message "call to 'f': expected 1 args, got 2"))
(reject "w9-call-too-few" (file "tests/fixtures/w9-call-too-few.nuc") (line 9)
        (message "call to 'f': expected 2 args, got 1"))

; The legitimately variable arities: `:optional` is a band, `:rest` is a floor.
(reject "w9-optional-too-many" (file "tests/fixtures/w9-optional-too-many.nuc") (line 7)
        (message "call to 'opt': expected at most 2 args, got 3"))
(reject "w9-rest-too-few" (file "tests/fixtures/w9-rest-too-few.nuc") (line 7)
        (message "call to 'r': expected at least 2 args, got 1"))

; A `declare`d signature is OPEN-TAILED: Nucleus has no `...` spelling, so the
; documented way to call a C variadic function is to declare its fixed
; parameters and let the extras ride the call site. This is the carve-out the
; check must not swallow — three tests above (n6/sm3/s1) already depend on it.
(accept "w9-declare-open-tail" (file "tests/fixtures/w9-declare-open-tail.nuc"))

; ...but the fixed prefix is still asserted, so too FEW is an error.
(reject "w9-declare-too-few" (file "tests/fixtures/w9-declare-too-few.nuc") (line 9)
        (message "call to 'some-c-fn': expected at least 2 args, got 1"))

; --- Stage 15 W9 defect 21: protocols are namespaced entities -------------------
; design/stage15-stress-test/progress.md W9 row 21; the ruling is recorded as a
; dated supersession of Stage 12 decision 9 in design/stage12/namespaces.md.
;
; `(dyn ns/Proto)` was unusable across a namespace: the conformance registry
; stripped the qualifier off BOTH the type and the protocol while
; `protocol-lookup` matched the raw spelling, so `(extend Cat dp/Describe)`
; recorded a fact `(dyn dp/Describe)` could never find. The fix keeps the strip
; for the TYPE half (Stage 12's actual claim — a qualified type reference must
; resolve to the same StructDef from any namespace) and replaces it for the
; PROTOCOL half with resolution through the namespaced protocol registry.
;
; The positive, link-AND-RUN half is examples/w9-dyn-ns.nuc (dispatched by the
; examples/*.nuc loop above against tests/expected/w9-dyn-ns.out): it asserts the
; dispatched RESULTS 105/207/309, not an exit-0 compile. It pins all three halves
; of the ruling at once — a qualified reference resolving cross-namespace under a
; DIFFERENT import prefix, a bare reference inside its own namespace naming the
; same identity, and two namespaces declaring a `Describe` apiece without
; colliding. The committed pre-fix compiler rejects that program outright.
;
; The negative halves: conformance is still checked (and now names the protocol
; by its namespaced identity, so a failure says *which* Describe), and a bare
; reference that names no protocol in scope is still an error rather than
; silently picking one.
(reject "w9-ns-proto-nonconform" (file "tests/fixtures/w9-ns-proto-nonconform.nuc") (line 18)
        (message "type 'Bad' does not conform to protocol 'dp/Describe'"))
(reject "w9-ns-proto-ambiguous" (file "tests/fixtures/w9-ns-proto-ambiguous.nuc") (line 17)
        (message "extend: unknown protocol 'Describe'"))
(reject "b2a-extend-ns-not-in-scope" (file "tests/fixtures/b2a-ns-not-in-scope.nuc") (line 25)
        (message "extend: unknown protocol 'dp/Describe'"))
(reject "b2a-dyn-ns-not-in-scope" (file "tests/fixtures/b2a-dyn-ns-not-in-scope.nuc") (line 27)
        (message "(dyn dp/Describe): 'dp/Describe' is not a declared protocol"))

; Defect #7's other half, and defect #4. `strip-ns-qualifier` used to discard a
; type spelling's qualifier without checking it, so a type was reachable from
; anywhere under any qualifier — including one naming no namespace at all.
(reject "b3-type-bogus-qualifier" (file "tests/fixtures/b3-type-bogus-qualifier.nuc") (line 14)
        (message "'nope' is not in scope in this file"))

; B3′ gave `unknown-type-message` the did-you-mean tier `unresolved-name-message`
; already had. The tier is a COLD error path, so it needs a test that EXECUTES it
; — the first cut called `fmt-3s` with two arguments, which conventions.md's
; fixed-arity rule says is invisible until something runs the line.
(reject "b3-type-typo" (file "tests/fixtures/b3-type-typo.nuc") (line 12)
        (message "unknown type: Widgat (did you mean 'Widget'?)"))

; `unsafe` is a namespace now, not seven strings in the special-form set. The
; positive half (unsafe/cast, unsafe/ptr+, unsafe/funcall-ptr-i32 and
; unsafe/import-private all compiling and RUNNING, the last of them reaching a
; `defn-` through the prefix) is examples/unsafe-spellings.nuc, dispatched by
; the examples loop above; the four `un5-bare-*` rejections above still pin the
; retired bare spellings, which are now refused because the namespace is bound
; PREFIXED and never flattened rather than by a hard-coded arm in the dispatch
; ladder. This is the third half: the qualified spellings stay RESERVED even
; though they left `g-special-form-set`.
(reject "b2b-unsafe-reserved" (file "tests/fixtures/b2b-unsafe-reserved.nuc")
        (message "'unsafe/cast' already names a special form"))

; The tenth defect (`protocol-dyn-annot`). An annotation naming a protocol that
; exists nowhere used to compile and fabricate a box type; admission now happens
; at the annotation site, deferred to `drain-dyn-annots`. Nothing in this fixture
; constructs a box, so only the annotation path can reach it.
(reject "b6-dyn-annot-unknown" (file "tests/fixtures/b6-dyn-annot-unknown.nuc") (line 17)
        (message "(dyn nope/Wholly-Absent): 'nope/Wholly-Absent' is not a declared protocol"))

; The erased-slot coercion's missing identity check, pinned at BOTH of its call
; sites: the argument position (its own blocks in emit-call-with-args) and the
; binding position (maybe-box-into-slot). The argument one is the one that
; mattered — the SysV ABI splits the fat pointer into two i64s at the call, so
; LLVM never saw the mismatch and the program linked and ran against the wrong
; vtable.
(reject "b6-dyn-box-mismatch-arg" (file "tests/fixtures/b6-dyn-box-mismatch-arg.nuc") (line 30)
        (message "type mismatch: a (dyn Pp) value cannot be used where (dyn Qq) is required"))
(reject "b6-dyn-box-mismatch-let" (file "tests/fixtures/b6-dyn-box-mismatch-let.nuc") (line 29)
        (message "type mismatch: a (dyn Pp) value cannot be used where (dyn Qq) is required"))

; The per-kind collision rule (§8.2's table, §14.2's `collides` column). Of the
; three rows that were 0, only `BK-ENUM` hid a real hole: a `defunion` also
; registers a backing StructDef under the same key so `BK-STRUCT` already
; answered for it, and `__fnty_N` has no source spelling — but an enum registers
; only its MEMBERS, so its own name collided with nothing.
(reject "b4-enum-vs-defn" (file "tests/fixtures/b4-enum-vs-defn.nuc") (line 13)
        (message "'Colour' already names an enumeration — a symbol may name only one kind of thing"))
(reject "b4-enum-vs-defvar" (file "tests/fixtures/b4-enum-vs-defvar.nuc") (line 6)
        (message "'Colour' already names an enumeration — a symbol may name only one kind of thing"))

; Stage 21 (design/stage21-cleanup/frame-storage-escape.md): every producer of
; a fresh stack slot — `alloca`, the struct/array/collection literals — hands
; back a frame-tainted address, so the existing return sinks refuse it, and a
; defvar initializer (run in @__nucleus_init, whose frame is gone before main)
; is the one global store that is provably an escape. The accept fixture pins
; the discharge rule: a by-value slot loads through the address, so the taint
; is dropped there rather than carried.
(reject "s21-frame-alloca-return" (file "tests/fixtures/s21-frame-alloca-return.nuc") (line 7)
        (message "address of frame-local storage escapes via return"))
(reject "s21-frame-literal-implicit-return" (file "tests/fixtures/s21-frame-literal-implicit-return.nuc") (line 4)
        (message "address of frame-local storage escapes via implicit return"))
(reject "s21-frame-vector-literal-return" (file "tests/fixtures/s21-frame-vector-literal-return.nuc") (line 6)
        (message "address of frame-local storage escapes via return"))
(reject "s21-frame-defvar-alloca" (file "tests/fixtures/s21-frame-defvar-alloca.nuc") (line 4)
        (message "defvar: the initializer of 'gb' is the address of frame-local storage"))
(reject "s21-frame-defvar-vector-literal" (file "tests/fixtures/s21-frame-defvar-vector-literal.nuc") (line 4)
        (message "defvar: the initializer of 'options' is the address of frame-local storage"))
(reject "s21-frame-cond-join" (file "tests/fixtures/s21-frame-cond-join.nuc") (line 6)
        (message "address of frame-local storage escapes via return"))
(accept "s21-frame-discharge-accepts" (file "tests/fixtures/s21-frame-discharge-accepts.nuc"))
