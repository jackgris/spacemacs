;;; postgresql-traces.el --- Major mode for PostgreSQL internal trace logs -*- lexical-binding: t; -*-

;; This file is not part of GNU Emacs.

;;; Commentary:
;; Major mode for traces that look like:
;; 09:35:55.975509 P@20942@03 |||>exec_simple_query
;; 09:35:55.975445 P@20942@03 |||info: query string:select 1;

;;; Code:

(require 'outline)
(require 'subr-x)

(defgroup postgresql-trace nil
  "View PostgreSQL internal trace logs."
  :group 'tools)

(defconst postgresql-trace--entry-regexp
  "^\\([0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\.[0-9]+\\) +P@\\([0-9]+\\)@\\([0-9]+\\) +\\(|+\\)\\([><]\\)\\([^[:space:]]+\\)"
  "Regexp matching a PostgreSQL trace function entry or exit.")

(defconst postgresql-trace--info-regexp
  "^\\([0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\.[0-9]+\\) +P@\\([0-9]+\\)@\\([0-9]+\\) +\\(|+\\)\\(info:\\) ?\\(.*\\)"
  "Regexp matching a PostgreSQL trace info line.")

(defconst postgresql-trace--outline-regexp
  "^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\.[0-9]+ +P@[0-9]+@\\([0-9]+\\) +|+>"
  "Regexp matching trace call lines for `outline-minor-mode'.")

(defconst postgresql-trace--call-regexp
  "^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\.[0-9]+ +P@[0-9]+@[0-9]+ +|+>\\([^[:space:]]+\\)"
  "Regexp matching trace call lines with the function name captured.")

(defvar postgresql-trace-font-lock-keywords
  `((,postgresql-trace--entry-regexp
     (1 font-lock-constant-face)
     (2 font-lock-type-face)
     (3 font-lock-builtin-face)
     (4 font-lock-comment-face)
     (5 (if (string= (match-string 5) ">")
            'font-lock-keyword-face
          'shadow))
     (6 font-lock-function-name-face))
    (,postgresql-trace--info-regexp
     (1 font-lock-constant-face)
     (2 font-lock-type-face)
     (3 font-lock-builtin-face)
     (4 font-lock-comment-face)
     (5 font-lock-doc-face)
     (6 font-lock-string-face)))
  "Font lock rules for `postgresql-trace-mode'.")

(defvar postgresql-trace-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'postgresql-trace-next-entry)
    (define-key map (kbd "p") #'postgresql-trace-previous-entry)
    (define-key map (kbd "TAB") #'outline-toggle-children)
    (define-key map (kbd "S-TAB") #'outline-show-all)
    map)
  "Keymap for `postgresql-trace-mode'.")

(defun postgresql-trace--outline-level ()
  "Return the current trace call depth for `outline-minor-mode'."
  (save-excursion
    (beginning-of-line)
    (if (looking-at postgresql-trace--outline-regexp)
        (string-to-number (match-string 1))
      0)))

(defun postgresql-trace-next-entry ()
  "Move to the next PostgreSQL trace function entry or exit."
  (interactive)
  (end-of-line)
  (re-search-forward postgresql-trace--entry-regexp nil t)
  (beginning-of-line))

(defun postgresql-trace-previous-entry ()
  "Move to the previous PostgreSQL trace function entry or exit."
  (interactive)
  (beginning-of-line)
  (re-search-backward postgresql-trace--entry-regexp nil t))

(defun postgresql-trace--count-matches (regexp)
  "Count REGEXP matches in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward regexp nil t)
        (setq count (1+ count)))
      count)))

(defun postgresql-trace-show-summary ()
  "Show a small summary for the current PostgreSQL trace buffer."
  (interactive)
  (let ((source (buffer-name))
        (calls (postgresql-trace--count-matches postgresql-trace--outline-regexp))
        (returns (postgresql-trace--count-matches "^[0-9:.]+ +P@[0-9]+@[0-9]+ +|+<"))
        (infos (postgresql-trace--count-matches postgresql-trace--info-regexp))
        (queries '()))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "info: query string:\\(.*\\)$" nil t)
        (push (string-trim (match-string 1)) queries)))
    (with-current-buffer (get-buffer-create "*PostgreSQL Trace Summary*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Trace: %s\n\n" source))
        (insert (format "Calls:   %d\n" calls))
        (insert (format "Returns: %d\n" returns))
        (insert (format "Info:    %d\n" infos))
        (when queries
          (insert "\nQueries:\n")
          (dolist (query (nreverse queries))
            (insert (format "- %s\n" query))))
        (special-mode))
      (pop-to-buffer (current-buffer)))))

(defun postgresql-trace--setup-imenu ()
  "Set up `imenu' for `postgresql-trace-mode'."
  (setq imenu-generic-expression
        `(("Calls" ,postgresql-trace--call-regexp 1))))

;;;###autoload
(define-derived-mode postgresql-trace-mode special-mode "PgTrace"
  "Major mode for PostgreSQL internal trace logs."
  (setq-local font-lock-defaults '(postgresql-trace-font-lock-keywords))
  (setq-local outline-regexp postgresql-trace--outline-regexp)
  (setq-local outline-level #'postgresql-trace--outline-level)
  (setq-local truncate-lines t)
  (postgresql-trace--setup-imenu)
  (outline-minor-mode 1))

;;;###autoload
(add-to-list 'auto-mode-alist '("postgres_lesson_.*\\.log\\'" . postgresql-trace-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.pgtrace\\'" . postgresql-trace-mode))

(provide 'postgresql-traces)

;;; postgresql-traces.el ends here
