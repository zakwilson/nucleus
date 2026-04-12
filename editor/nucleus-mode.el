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
  '("defn" "defvar" "defconst" "defenum" "defstruct" "include" "extern"))

(defvar nucleus-special-forms
  '("let" "cond" "while" "do" "return" "set!" "inc!"
    "cast" "sizeof" "alloca" "char" "addr-of" "deref"
    "ptr-set!" "ptr+" "aref" "aset!" "and" "or" "not"
    "." ".set!"))

(defvar nucleus-builtin-types
  '("i1" "i8" "i16" "i32" "i64" "ptr" "void" "int" "bool"))

(defvar nucleus-constants
  '("null" "true" "false"))

(defvar nucleus-font-lock-keywords
  (let ((toplevel-re (regexp-opt nucleus-toplevel-keywords 'symbols))
        (special-re (regexp-opt nucleus-special-forms 'symbols))
        (type-re (regexp-opt nucleus-builtin-types 'symbols))
        (const-re (regexp-opt nucleus-constants 'symbols)))
    `((,(concat "(" toplevel-re) 1 font-lock-keyword-face)
      (,(concat "(" special-re) 1 font-lock-keyword-face)
      (,type-re . font-lock-type-face)
      (,const-re . font-lock-constant-face)
      ("\\<[A-Z][A-Z0-9_-]*\\>" . font-lock-constant-face)
      ("(defn\\s-+\\([^ :)]+\\)" 1 font-lock-function-name-face)
      ("(defstruct\\s-+\\([^ :)]+\\)" 1 font-lock-type-face)
      ("(defenum\\s-+\\([^ :)]+\\)" 1 font-lock-type-face)
      ("(defvar\\s-+\\([^ :)]+\\)" 1 font-lock-variable-name-face)
      ("(defconst\\s-+\\([^ :)]+\\)" 1 font-lock-variable-name-face)
      (":\\([^ )\n]+\\)" 1 font-lock-type-face))))

(defvar nucleus-indent-specials
  '(("defn" . 2) ("let" . 2) ("if" . 2) ("while" . 2)
    ("do" . 1) ("defstruct" . 2) ("defenum" . 2))
  "Alist of form names to their special body indent offset.")

(defun nucleus-indent-function (indent-point state)
  "Indent like common Lisp but with Nucleus-specific overrides."
  (let ((normal-indent (current-column)))
    (goto-char (1+ (elt state 1)))
    (let ((head (and (looking-at "\\(?:\\sw\\|\\s_\\)+")
                     (match-string 0))))
      (if-let ((entry (and head (assoc head nucleus-indent-specials))))
          (let ((containing-col (save-excursion
                                  (goto-char (elt state 1))
                                  (current-column))))
            (+ containing-col (cdr entry)))
        (lisp-indent-calcmethod 1 indent-point state)))))

;;;###autoload
(define-derived-mode nucleus-mode prog-mode "Nucleus"
  "Major mode for editing Nucleus (.nuc) files."
  :syntax-table nucleus-mode-syntax-table
  (setq-local comment-start "; ")
  (setq-local comment-end "")
  (setq-local font-lock-defaults '(nucleus-font-lock-keywords))
  (setq-local indent-line-function #'lisp-indent-line)
  (setq-local lisp-indent-function #'nucleus-indent-function)
  (setq-local parse-sexp-ignore-comments t))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.nuc\\'" . nucleus-mode))

(provide 'nucleus-mode)
;;; nucleus-mode.el ends here
