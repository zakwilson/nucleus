;;; nucleus-repl.el --- Inferior REPL and interaction for Nucleus -*- lexical-binding: t; -*-

;; Provides:
;;   `run-nucleus' / `nucleus-repl'  — start/visit the inferior REPL.
;;   `nucleus-repl-mode'             — comint-derived major mode for the REPL.
;;   `nucleus-interaction-mode'      — minor mode layering eval / completion /
;;                                     describe / locate / macroexpand commands
;;                                     onto a `nucleus-mode' source buffer.
;;
;; The REPL is driven entirely through the introspection forms already
;; exposed by `nucleusc -i' (`defined?', `kind-of', `type-of', `dir',
;; `apropos', `complete', `locate', `expansion-of', `last-error', `doc',
;; ...).  No bespoke wire protocol is involved.

(require 'comint)
(require 'compile)
(require 'subr-x)

(defgroup nucleus-repl nil
  "Inferior Nucleus REPL."
  :group 'nucleus
  :prefix "nucleus-repl-")

(defcustom nucleus-repl-program "nucleusc"
  "Program name (or path) used to launch the inferior REPL."
  :type 'string
  :group 'nucleus-repl)

(defcustom nucleus-repl-program-args '("-i" "--repl-format=json")
  "Argument list passed to `nucleus-repl-program'."
  :type '(repeat string)
  :group 'nucleus-repl)

(defcustom nucleus-repl-buffer-name "*nucleus-repl*"
  "Name of the buffer hosting the inferior Nucleus REPL."
  :type 'string
  :group 'nucleus-repl)

(defcustom nucleus-repl-query-timeout 5.0
  "Seconds `nucleus-repl--query' waits for a response before giving up."
  :type 'number
  :group 'nucleus-repl)

(defconst nucleus-repl-prompt-regexp "^\\(?:nuc\\|\\.\\.\\.\\)> "
  "Matches the primary and continuation prompts emitted by `nucleusc -i'.")

(defconst nucleus-repl--json-error-regexp
  "{\"file\":\"\\([^\"]+\\)\",\"line\":\\([0-9]+\\)"
  "Matches the leading fields of a `--repl-format=json' error frame.
Groups 1 and 2 carry the source file and line number for
`compilation-shell-minor-mode'.")


;;; -------- Inferior process management --------------------------------------

(defun nucleus-repl--process ()
  "Return the live process for the Nucleus REPL buffer, or nil."
  (let ((buf (get-buffer nucleus-repl-buffer-name)))
    (and buf (get-buffer-process buf))))

;;;###autoload
(defun nucleus-repl ()
  "Start (or visit) the inferior Nucleus REPL in `nucleus-repl-buffer-name'."
  (interactive)
  (let ((buf (get-buffer-create nucleus-repl-buffer-name)))
    (unless (comint-check-proc buf)
      (apply #'make-comint-in-buffer
             "nucleus-repl" buf nucleus-repl-program nil
             nucleus-repl-program-args)
      (with-current-buffer buf
        (nucleus-repl-mode)))
    (pop-to-buffer buf)))

;;;###autoload
(defalias 'run-nucleus #'nucleus-repl)


;;; -------- Major mode -------------------------------------------------------

(defvar nucleus-repl-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "TAB") #'completion-at-point)
    map)
  "Keymap for `nucleus-repl-mode'.")

(define-derived-mode nucleus-repl-mode comint-mode "Nucleus-REPL"
  "Major mode for an inferior Nucleus REPL.
Runs `nucleusc -i --repl-format=json' under comint.  Errors emitted as
JSON frames are made navigable via `compilation-shell-minor-mode'."
  (setq-local comint-prompt-regexp nucleus-repl-prompt-regexp)
  (setq-local comint-prompt-read-only t)
  (setq-local comint-input-ignoredups t)
  (setq-local paragraph-start nucleus-repl-prompt-regexp)
  (add-hook 'completion-at-point-functions
            #'nucleus-completion-at-point nil t)
  ;; Make JSON error frames clickable.
  (setq-local compilation-error-regexp-alist
              `((,nucleus-repl--json-error-regexp 1 2)))
  (compilation-shell-minor-mode 1))


;;; -------- Synchronous request/response helper ------------------------------

(defun nucleus-repl--strip-echo (text form)
  "Remove a leading line equal to FORM from TEXT, if present.
Pty echo can prepend the dispatched form to the captured output."
  (let ((echoed (concat form "\n")))
    (if (string-prefix-p echoed text)
        (substring text (length echoed))
      text)))

(defun nucleus-repl--query (form)
  "Send FORM (a string, no trailing newline) to the REPL and return its output.
The trailing prompt line is stripped.  Signals a `user-error' if no
REPL is running or the response does not arrive within
`nucleus-repl-query-timeout' seconds.

Installs a lightweight temporary process filter for the duration of the
query so each PTY chunk does not run through the full comint filter
chain (compilation, prompt detection, read-only properties, etc.) — for
short introspection forms that filter chain dominated end-to-end time.
Captured output is replayed through the original filter at the end so
the REPL buffer reflects the exchange."
  (let ((proc (nucleus-repl--process)))
    (unless proc
      (user-error "No Nucleus REPL is running (M-x run-nucleus)"))
    (let* ((orig-filter (process-filter proc))
           (capture "")
           (done nil)
           ;; Match prompt at end of capture, anchored either to string
           ;; start or to a preceding newline.  Cannot reuse
           ;; `nucleus-repl-prompt-regexp' verbatim: it begins with `^',
           ;; which `string-match-p' treats as "start of string only" —
           ;; not "after a newline" — so the prompt tail would never
           ;; match and every query waited the full timeout.
           (tail-regexp
            "\\(?:\\`\\|\n\\)\\(?:nuc\\|\\.\\.\\.\\)> \\'")
           (deadline (+ (float-time) nucleus-repl-query-timeout)))
      (set-process-filter
       proc
       (lambda (_p chunk)
         (setq capture (concat capture chunk))
         (when (string-match-p tail-regexp capture)
           (setq done t))))
      (unwind-protect
          (progn
            (process-send-string proc (concat form "\n"))
            (while (and (not done) (< (float-time) deadline))
              (accept-process-output proc 1.0 nil t)))
        (set-process-filter proc orig-filter)
        (when (and orig-filter (not (string-empty-p capture)))
          (funcall orig-filter proc capture)))
      (let* ((stripped (nucleus-repl--strip-echo capture form))
             (without-prompt
              (replace-regexp-in-string
               "\n?\\(?:nuc\\|\\.\\.\\.\\)> \\'" "" stripped)))
        without-prompt))))


;;; -------- Source-buffer command implementations ----------------------------

(defun nucleus-repl--ensure-running ()
  "Start the REPL if not already running.  Block briefly for the first prompt.
Detects the prompt by inspecting the last few characters of the REPL
buffer rather than `looking-back': comint installs a `field' text
property on the prompt, which makes `line-beginning-position' return
point itself (the field boundary), giving `looking-back' a zero-width
search range that never matches."
  (unless (nucleus-repl--process)
    (save-window-excursion (nucleus-repl)))
  (let ((proc (nucleus-repl--process))
        (deadline (+ (float-time) 5.0)))
    (unless proc (user-error "Failed to start Nucleus REPL"))
    (with-current-buffer (process-buffer proc)
      (while (and (< (float-time) deadline)
                  (let ((tail (buffer-substring-no-properties
                               (max (point-min) (- (point-max) 8))
                               (point-max))))
                    (not (string-match-p
                          "\\(?:\\`\\|\n\\)\\(?:nuc\\|\\.\\.\\.\\)> \\'"
                          tail))))
        (accept-process-output proc 1.0 nil t)))))

(defun nucleus-repl--send (text)
  "Send TEXT to the REPL, ensuring it is running and adding a trailing newline."
  (nucleus-repl--ensure-running)
  (let ((proc (nucleus-repl--process)))
    (comint-send-string
     proc (if (string-suffix-p "\n" text) text (concat text "\n")))))

(defun nucleus-repl--last-sexp-bounds ()
  "Return (START . END) of the sexp immediately before point."
  (save-excursion
    (let ((end (point)))
      (backward-sexp)
      (cons (point) end))))

(defun nucleus-repl--defun-bounds ()
  "Return (START . END) of the enclosing top-level form."
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (cons (point) end))))

(defun nucleus-eval-last-sexp ()
  "Send the sexp before point to the inferior REPL."
  (interactive)
  (let* ((bounds (nucleus-repl--last-sexp-bounds))
         (text (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (nucleus-repl--send text)))

(defun nucleus-eval-defun ()
  "Send the enclosing top-level form to the inferior REPL."
  (interactive)
  (let* ((bounds (nucleus-repl--defun-bounds))
         (text (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (nucleus-repl--send text)))

(defun nucleus-eval-region (beg end)
  "Send the region between BEG and END to the inferior REPL."
  (interactive "r")
  (nucleus-repl--send (buffer-substring-no-properties beg end)))

(defun nucleus-load-buffer ()
  "Send the entire buffer to the inferior REPL."
  (interactive)
  (nucleus-repl--send (buffer-substring-no-properties (point-min) (point-max))))

(defun nucleus-switch-to-repl ()
  "Pop to the REPL buffer, starting one if necessary."
  (interactive)
  (nucleus-repl))


;;; -------- Symbol queries ---------------------------------------------------

(defun nucleus-repl--symbol-at-point ()
  "Return the Nucleus symbol at point as a string, or nil."
  (let ((s (thing-at-point 'symbol t)))
    (and s (substring-no-properties s))))

(defun nucleus-repl--read-symbol (prompt)
  "Read a Nucleus symbol from the minibuffer, defaulting to symbol at point."
  (let* ((default (nucleus-repl--symbol-at-point))
         (input (read-string
                 (if default
                     (format "%s (default %s): " prompt default)
                   (format "%s: " prompt))
                 nil nil default)))
    (if (string-empty-p input) default input)))

(defun nucleus-describe-symbol (sym)
  "Show kind, type, and source location for SYM in `*nucleus-doc*'."
  (interactive (list (nucleus-repl--read-symbol "Describe")))
  (nucleus-repl--ensure-running)
  (let ((kind   (nucleus-repl--query (format "(kind-of %s)" sym)))
        (type   (nucleus-repl--query (format "(type-of %s)" sym)))
        (locate (nucleus-repl--query (format "(locate %s)" sym)))
        (buf    (get-buffer-create "*nucleus-doc*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Symbol: %s\n\n" sym))
        (insert "Kind:\n" kind "\n\n")
        (insert "Type:\n" type "\n\n")
        (insert "Location:\n" locate "\n"))
      (goto-char (point-min))
      (special-mode))
    (display-buffer buf)))

(defun nucleus-find-definition (sym)
  "Jump to the definition of SYM using the REPL's `locate' query."
  (interactive (list (nucleus-repl--read-symbol "Find definition")))
  (nucleus-repl--ensure-running)
  (let ((response (nucleus-repl--query (format "(locate %s)" sym))))
    (cond
     ((string-match "\\([^ \n:]+\\):\\([0-9]+\\)" response)
      (let ((file (match-string 1 response))
            (line (string-to-number (match-string 2 response))))
        (xref-push-marker-stack)
        (find-file file)
        (goto-char (point-min))
        (forward-line (1- line))))
     ((string-match-p "<unbound>" response)
      (user-error "Unbound symbol: %s" sym))
     (t
      (user-error "No source location for %s (%s)"
                  sym (string-trim response))))))

(defun nucleus-type-of ()
  "Send the sexp at point through `(type-of ...)' and echo the result."
  (interactive)
  (nucleus-repl--ensure-running)
  (let* ((bounds (or (bounds-of-thing-at-point 'sexp)
                     (nucleus-repl--last-sexp-bounds)))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (response (nucleus-repl--query (format "(type-of %s)" form))))
    (message "%s" (string-trim response))))

(defun nucleus-macroexpand ()
  "Expand the sexp at point with `(expansion-of ...)' in `*nucleus-macroexpand*'."
  (interactive)
  (nucleus-repl--ensure-running)
  (let* ((bounds (or (bounds-of-thing-at-point 'sexp)
                     (nucleus-repl--last-sexp-bounds)))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (response (nucleus-repl--query (format "(expansion-of %s)" form)))
         (buf (get-buffer-create "*nucleus-macroexpand*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (string-trim-right response) "\n"))
      (goto-char (point-min))
      (when (fboundp 'nucleus-mode) (nucleus-mode)))
    (display-buffer buf)))

(defun nucleus-apropos (substring)
  "Run `(apropos \"SUBSTRING\")' in the REPL and show the result."
  (interactive "sApropos: ")
  (nucleus-repl--ensure-running)
  (let ((response (nucleus-repl--query (format "(apropos \"%s\")" substring)))
        (buf (get-buffer-create "*nucleus-apropos*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Apropos: %s\n\n" substring))
        (insert response))
      (goto-char (point-min))
      (special-mode))
    (display-buffer buf)))


;;; -------- Completion at point ----------------------------------------------

(defvar nucleus-repl--complete-cache nil
  "Cons (PREFIX . CANDIDATES) cached for one command loop.")

(defun nucleus-repl--complete (prefix)
  "Return a list of completion candidates for PREFIX via `(complete \"...\")'."
  (if (and (consp nucleus-repl--complete-cache)
           (equal (car nucleus-repl--complete-cache) prefix)
           (eq this-command last-command))
      (cdr nucleus-repl--complete-cache)
    (let* ((response (nucleus-repl--query (format "(complete \"%s\")" prefix)))
           (lines (split-string response "\n" t "[ \t]+"))
           (names (delq nil
                        (mapcar (lambda (l)
                                  (let ((trimmed (string-trim l)))
                                    (and (not (string-empty-p trimmed))
                                         (not (string-match-p "^<" trimmed))
                                         trimmed)))
                                lines))))
      (setq nucleus-repl--complete-cache (cons prefix names))
      names)))

(defun nucleus-completion-at-point ()
  "`completion-at-point' backend that asks the running REPL for matches."
  (when (nucleus-repl--process)
    (let ((bounds (bounds-of-thing-at-point 'symbol)))
      (when bounds
        (let* ((start (car bounds))
               (end (cdr bounds))
               (prefix (buffer-substring-no-properties start end)))
          (when (>= (length prefix) 1)
            (list start end
                  (completion-table-dynamic
                   (lambda (_p) (nucleus-repl--complete prefix)))
                  :exclusive 'no)))))))


;;; -------- Interaction minor mode -------------------------------------------

(defvar nucleus-interaction-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-x C-e") #'nucleus-eval-last-sexp)
    (define-key map (kbd "C-M-x")   #'nucleus-eval-defun)
    (define-key map (kbd "C-c C-c") #'nucleus-eval-defun)
    (define-key map (kbd "C-c C-r") #'nucleus-eval-region)
    (define-key map (kbd "C-c C-k") #'nucleus-load-buffer)
    (define-key map (kbd "C-c C-z") #'nucleus-switch-to-repl)
    (define-key map (kbd "C-c C-d") #'nucleus-describe-symbol)
    (define-key map (kbd "M-.")     #'nucleus-find-definition)
    (define-key map (kbd "M-,")     #'xref-pop-marker-stack)
    (define-key map (kbd "C-c C-m") #'nucleus-macroexpand)
    (define-key map (kbd "C-c C-t") #'nucleus-type-of)
    (define-key map (kbd "C-c C-a") #'nucleus-apropos)
    map)
  "Keymap for `nucleus-interaction-mode'.")

;;;###autoload
(define-minor-mode nucleus-interaction-mode
  "Minor mode layering REPL-driven commands onto a Nucleus source buffer."
  :lighter " Nuc-Int"
  :keymap nucleus-interaction-mode-map
  (if nucleus-interaction-mode
      (add-hook 'completion-at-point-functions
                #'nucleus-completion-at-point nil t)
    (remove-hook 'completion-at-point-functions
                 #'nucleus-completion-at-point t)))

(provide 'nucleus-repl)
;;; nucleus-repl.el ends here
