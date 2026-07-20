;;; nucleus-mode.el --- Major mode for Nucleus -*- lexical-binding: t; -*-

(require 'lisp-mode)

(defvar nucleus-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\; "<" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?- "_" table)
    (modify-syntax-entry ?! "_" table)
    (modify-syntax-entry ?? "_" table)
    (modify-syntax-entry ?. "_" table)
    (modify-syntax-entry ?* "_" table)
    (modify-syntax-entry ?: "_" table)
    table))

(defvar nucleus-toplevel-keywords
  '("defn" "defn-" "defvar" "defvar-" "defconst" "defconst-"
    "defenum" "defenum-" "defstruct" "defstruct-"
    "defunion" "defunion-" "defprotocol" "defprotocol-"
    "defmacro" "defmacro-" "defcast" "def-rmacro" "deferror"
    "extend" "import" "import-use" "import-prefixed" "import-only"
    "unsafe-import-private" "declare" "extern" "include" "exclude-prelude"
    "ns" "set-ir-prefix" "export"))

(defvar nucleus-special-forms
  '("do" "let" "with" "cond" "case" "match" "make"
    "while" "return" "set!" "inc!" "dec!" "label" "goto"
    "label-addr" "goto-ptr" "cast" "addr-of" "deref"
    "ptr-set!" "ptr+" "aref" "aset!" "sizeof" "alloca" "char"
    "quote" "quasiquote" "compile-time" "gensym"
    "some" "none" "as-ref" "unwrap" "unwrap-or"
    "if-some" "when-some" "move" "defer"
    "fn" "vfn" "mfn" "cfn" "funcall" "funcall-void"
    "funcall-ptr-1" "funcall-ptr-i32" "funcall-ptr-i64" "funcall-ptr-ptr"
    "if" "when" "unless" "and" "or" "not" "_and" "_or"
    "zero?" "null?" "for" "dotimes" "doseq" "doseq-iter"
    "into" "into-iter" "->" "unquote" "unquote-splice"
    "get" "invoke"))

(defvar nucleus-accessor-primitives
  ;; Forms that begin with non-word constituents (so `regexp-opt 'symbols'
  ;; won't anchor them) and must be fontified only in head position --
  ;; i.e. immediately after an open paren.
  '("." ".&" ".set!" "_get"))

(defvar nucleus-builtin-types
  '("i1" "i8" "i16" "i32" "i64" "ui8" "ui16" "ui32" "ui64"
    "f32" "f64" "int" "bool" "void" "ptr" "usize" "ssize"
    "float" "double" "ref" "raw" "CStr" "Char" "StrView" "Self"))

(defvar nucleus-constants
  '("null" "true" "false" "none"))

(defvar nucleus-font-lock-keywords
  (let ((toplevel-re (regexp-opt nucleus-toplevel-keywords 'symbols))
        (special-re (regexp-opt nucleus-special-forms 'symbols))
        (type-re (regexp-opt nucleus-builtin-types 'symbols))
        (const-re (regexp-opt nucleus-constants 'symbols))
        ;; `regexp-opt' without 'symbols yields shy groups, so wrap in a
        ;; real group to expose subexp 1.  regexp-opt shares the common
        ;; "." prefix, matching the longest alternative first.
        (accessor-re (regexp-opt nucleus-accessor-primitives)))
    `((,(concat "(" toplevel-re) 1 font-lock-keyword-face)
      (,(concat "(" special-re) 1 font-lock-keyword-face)
      (,(concat "(" "\\(" accessor-re "\\)") 1 font-lock-keyword-face)
      (,type-re . font-lock-type-face)
      (,const-re . font-lock-constant-face)
      ("\\<[A-Z][A-Z0-9_-]*\\>" . font-lock-constant-face)
      ("(defn\\s-+\\([^ :)]+\\)" 1 font-lock-function-name-face)
      ("(defmacro\\s-+\\([^ :)]+\\)" 1 font-lock-function-name-face)
      ("(defcast\\s-+\\([^ :)]+\\)" 1 font-lock-function-name-face)
      ("(defstruct\\s-+\\([^ :)]+\\)" 1 font-lock-type-face)
      ("(defenum\\s-+\\([^ :)]+\\)" 1 font-lock-type-face)
      ("(defunion\\s-+\\([^ :)]+\\)" 1 font-lock-type-face)
      ("(defprotocol\\s-+\\([^ :)]+\\)" 1 font-lock-type-face)
      ("(defvar\\s-+\\([^ :)]+\\)" 1 font-lock-variable-name-face)
      ("(defconst\\s-+\\([^ :)]+\\)" 1 font-lock-variable-name-face)
      (":\\([^ )\n]+\\)" 1 font-lock-type-face))))

(defvar nucleus-indent-specials
  '(("defn" . 2) ("defmacro" . 2) ("defstruct" . 2) ("defenum" . 2)
    ("defunion" . 2) ("while" . 2) ("do" . 2) ("compile-time" . 2)
    ;; Body-having standard macros: their body forms indent +2, matching
    ;; the source convention (e.g. `if'/`when'/`unless' branches, and the
    ;; loop body of `for'/`dotimes'/`doseq'/`doseq-iter'/`into'/`into-iter').
    ("if" . 2) ("when" . 2) ("unless" . 2)
    ("for" . 2) ("dotimes" . 2) ("doseq" . 2) ("doseq-iter" . 2)
    ("into" . 2) ("into-iter" . 2))
  "Alist of form names to a body indent offset added to the column of the
form's opening paren.  `let', `with', `match' and `cond' have dedicated
handling in `nucleus-indent-function'.")

(defun nucleus-indent-cond (indent-point state)
  "Indent a Nucleus cond form.
Nucleus cond clauses are flat (test result test result ...), not wrapped
in parens. Test clauses align with the first test; result clauses sit two
columns to the right of the test column."
  (save-excursion
    (let ((containing-col (save-excursion
                            (goto-char (elt state 1))
                            (current-column))))
      (goto-char (1+ (elt state 1)))
      (forward-sexp 1)
      (forward-comment (point-max))
      (if (>= (point) indent-point)
          (+ containing-col 2)
        (let ((test-col (current-column))
              (count 0))
          (while (and (< (point) indent-point)
                      (ignore-errors (forward-sexp 1) t))
            (setq count (1+ count))
            (forward-comment (point-max)))
          (if (zerop (mod count 2))
              test-col
            (+ test-col 2)))))))

(defun nucleus-indent-let-bindings (indent-point bl-open-col)
  "Return the indent column for a line at INDENT-POINT inside a binding list.
BL-OPEN-COL is the column of the binding list's open paren.  The list is a
flat sequence of (binding-spec init) pairs, so even-indexed elements align
at BL-OPEN-COL + 1 and odd-indexed inits align two columns right of their
binding-spec.  Returns nil when INDENT-POINT lies inside a sub-form, so the
default Lisp indenter takes over for multi-line continuation."
  (let ((n 0)
        (last-col nil)
        inside-subform)
    (while
        (and (not inside-subform)
             (progn
               (forward-comment (point-max))
               (and (< (point) indent-point)
                    (not (looking-at "\\s)")))))
      (let ((start-col (current-column))
            sexp-end)
        (setq sexp-end
              (save-excursion
                (condition-case nil
                    (progn (forward-sexp 1) (point))
                  (error nil))))
        (cond
         ((null sexp-end)
          (setq inside-subform t))
         ((<= sexp-end indent-point)
          (setq last-col start-col)
          (setq n (1+ n))
          (goto-char sexp-end))
         (t
          (setq inside-subform t)))))
    (cond
     (inside-subform nil)
     ((zerop (mod n 2))
      (+ bl-open-col 1))
     (t
      (if last-col (+ last-col 2) (+ bl-open-col 1))))))

(defun nucleus-indent-let (indent-point state containing-col)
  "Indent inside a `let' or `with' form whose open paren is the innermost
containing one.  CONTAINING-COL is the column of that open paren.
Returns an integer column or nil."
  (save-excursion
    (goto-char (1+ (elt state 1)))
    (if (not (ignore-errors (forward-sexp 1) t))    ; skip the head
        nil
      (forward-comment (point-max))
      (let ((bl-start (point))
            (bl-open-col (current-column))
            bl-end)
        (condition-case nil
            (progn (forward-sexp 1) (setq bl-end (point)))
          (error (setq bl-end nil)))
        (if (and bl-end (< bl-end indent-point))
            (+ containing-col 2)                     ; body
          (goto-char (1+ bl-start))
          (nucleus-indent-let-bindings indent-point bl-open-col))))))

(defun nucleus-indent-let-binding-list-p (state)
  "Return t if STATE's innermost form is the binding list of a let/with.
When the indent-point sits inside a let/with binding list, the innermost
containing paren is the binding list's paren (so the head extracted by
`nucleus-indent-function' is the first binding, not `let').  This detects
that situation by looking at the parent form."
  (ignore-errors
    (let ((inner-pos (elt state 1)))
      (and (> inner-pos (point-min))
           (let (parent-pos)
             (save-excursion
               (goto-char (1- inner-pos))
               (setq parent-pos (nth 1 (syntax-ppss))))
             (and parent-pos
                  (goto-char (1+ parent-pos))
                  (looking-at "\\(?:\\sw\\|\\s_\\)+")
                  (member (match-string 0) '("let" "with"))
                  ;; Confirm the innermost form is the parent's first
                  ;; argument (the binding list), not a body form.
                  (progn
                    (goto-char (match-end 0))
                    (forward-comment (point-max))
                    (= (point) inner-pos))))))))

(defun nucleus-indent-cond (indent-point state)
  "Indent a Nucleus cond form.
Nucleus cond clauses are flat (test result test result ...), not wrapped
in parens. Test clauses align with the first test; result clauses sit two
columns to the right of the test column."
  (save-excursion
    (let ((containing-col (save-excursion
                            (goto-char (elt state 1))
                            (current-column))))
      (goto-char (1+ (elt state 1)))
      (forward-sexp 1)
      (forward-comment (point-max))
      (if (>= (point) indent-point)
          (+ containing-col 2)
        (let ((test-col (current-column))
              (count 0))
          (while (and (< (point) indent-point)
                      (ignore-errors (forward-sexp 1) t))
            (setq count (1+ count))
            (forward-comment (point-max)))
          (if (zerop (mod count 2))
              test-col
            (+ test-col 2)))))))

(defun nucleus-indent-function (indent-point state)
  "Nucleus indentation function.
Returns an integer column or nil; nil lets `lisp-indent-line' fall back to
its default alignment."
  (save-excursion
    (let ((oparen (elt state 1)))
      ;; oparen is nil at top level (no containing paren) -> default indent.
      (and oparen
           (progn
             (goto-char (1+ oparen))
             (let ((head (and (looking-at "\\(?:\\sw\\|\\s_\\)+")
                              (match-string 0)))
                   (containing-col (save-excursion
                                     (goto-char oparen)
                                     (current-column))))
               (cond
                ((null head) nil)
                ((equal head "cond")
                 (nucleus-indent-cond indent-point state))
                ((equal head "match")
                 (+ containing-col 2))
                ((equal head "let")
                 (nucleus-indent-let indent-point state containing-col))
                ((equal head "with")
                 (nucleus-indent-let indent-point state containing-col))
                ((nucleus-indent-let-binding-list-p state)
                 ;; Indent-point is inside a let/with binding list.  The
                 ;; innermost paren IS the binding-list paren, so
                 ;; containing-col is bl-open-col.
                 (goto-char (1+ oparen))
                 (nucleus-indent-let-bindings indent-point containing-col))
                (t
                 (let ((entry (and head (assoc head nucleus-indent-specials))))
                   (if entry
                       (+ containing-col (cdr entry))
                     nil))))))))))

(defun nucleus--comment-line-indent ()
  "Heuristic column for a Nucleus comment-only line.
A comment usually introduces the following form, so prefer the next
non-blank line's indentation; if that line is a closing paren (a
dedent) or there is none, fall back to the previous non-blank line's
indentation.  This avoids the `lisp-indent-line' / `indent-for-comment'
re-entry loop, which would otherwise hang `indent-region' on a
comment-only line."
  (save-excursion
    (let ((here (point)))
      (save-excursion
        (forward-line 1)
        (while (and (not (eobp)) (looking-at "\\s-*$"))
          (forward-line 1))
        (let* ((next-blank (eobp))
               (next-indent (unless next-blank (current-indentation)))
               (next-closer (unless next-blank
                              (save-excursion
                                (skip-syntax-forward " ")
                                (looking-at ")")))))
          (if (and next-indent (not next-closer))
              next-indent
            (goto-char here)
            (forward-line -1)
            (while (and (not (bobp)) (looking-at "\\s-*$"))
              (forward-line -1))
            (if (bobp) 0 (current-indentation))))))))

(defun nucleus-indent-line (&optional arg)
  "Indent a line of Nucleus code.
Code lines delegate to `lisp-indent-line' (which consults
`nucleus-indent-function').  A comment-only line -- whose first
non-whitespace is `;' -- is indented to the previous non-blank line's
column instead, dodging the `lisp-indent-line' / `indent-for-comment'
re-entry loop that hangs `indent-region'."
  (if (save-excursion
        (beginning-of-line)
        (skip-syntax-forward " ")
        (looking-at ";"))
      (indent-line-to (nucleus--comment-line-indent))
    (lisp-indent-line arg)))

(defcustom nucleus-mode-enable-interaction t
  "If non-nil, enable `nucleus-interaction-mode' in `nucleus-mode' buffers.
The interaction mode binds eval / completion / describe / locate /
macroexpand commands that talk to an inferior `nucleusc -i' REPL."
  :type 'boolean
  :group 'nucleus)

(autoload 'nucleus-repl "nucleus-repl"
  "Start (or visit) the inferior Nucleus REPL." t)
(autoload 'run-nucleus "nucleus-repl"
  "Start (or visit) the inferior Nucleus REPL." t)
(autoload 'nucleus-interaction-mode "nucleus-repl"
  "Minor mode layering REPL-driven commands onto a Nucleus source buffer." t)

(defvar nucleus-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-z") #'nucleus-switch-to-repl)
    map)
  "Base keymap for `nucleus-mode'.  `nucleus-interaction-mode' adds more.")

(declare-function nucleus-switch-to-repl "nucleus-repl")
(autoload 'nucleus-switch-to-repl "nucleus-repl" nil t)

;;;###autoload
(define-derived-mode nucleus-mode prog-mode "Nucleus"
  "Major mode for editing Nucleus (.nuc) files."
  :syntax-table nucleus-mode-syntax-table
  (setq-local comment-start "; ")
  (setq-local comment-end "")
  (setq-local font-lock-defaults '(nucleus-font-lock-keywords))
  (setq-local indent-line-function #'nucleus-indent-line)
  (setq-local lisp-indent-function #'nucleus-indent-function)
  (setq-local parse-sexp-ignore-comments t)
  (when nucleus-mode-enable-interaction
    (nucleus-interaction-mode 1)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.nuc\\'" . nucleus-mode))

(provide 'nucleus-mode)
;;; nucleus-mode.el ends here
