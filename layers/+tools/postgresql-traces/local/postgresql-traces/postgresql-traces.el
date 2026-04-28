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

(defvar-local postgresql-trace--match-overlays nil
  "Overlays used to highlight matching PostgreSQL trace entries.")

(defvar postgresql-trace-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'postgresql-trace-next-entry)
    (define-key map (kbd "p") #'postgresql-trace-previous-entry)
    (define-key map (kbd "%") #'postgresql-trace-jump-to-matching-entry)
    (define-key map (kbd "C-l") #'recenter-top-bottom)
    (define-key map (kbd "TAB") #'outline-toggle-children)
    (define-key map (kbd "S-TAB") #'outline-show-all)
    map)
  "Keymap for `postgresql-trace-mode'.")

(defun postgresql-trace--line-entry ()
  "Return trace entry data for the current line.

The return value is (PID DEPTH DIRECTION FUNCTION START END), or nil when the
current line is not a function entry or exit."
  (save-excursion
    (beginning-of-line)
    (when (looking-at postgresql-trace--entry-regexp)
      (list (match-string-no-properties 2)
            (match-string-no-properties 3)
            (match-string-no-properties 5)
            (match-string-no-properties 6)
            (line-beginning-position)
            (line-end-position)))))

(defun postgresql-trace--matching-entry-regexp (pid depth direction function)
  "Build regexp matching PID DEPTH DIRECTION FUNCTION on one trace line."
  (concat "^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]\\.[0-9]+"
          " +P@" (regexp-quote pid) "@" (regexp-quote depth)
          " +|+" (regexp-quote direction)
          (regexp-quote function)
          "\\(?:[[:space:]]\\|$\\)"))

(defun postgresql-trace--matching-entry-position ()
  "Return the matching trace entry line bounds, or nil."
  (pcase-let ((`(,pid ,depth ,direction ,function ,_start ,_end)
               (postgresql-trace--line-entry)))
    (when direction
      (let ((regexp (postgresql-trace--matching-entry-regexp
                     pid depth (if (string= direction ">") "<" ">") function)))
        (save-excursion
          (if (string= direction ">")
              (progn
                (end-of-line)
                (when (re-search-forward regexp nil t)
                  (save-excursion
                    (goto-char (match-beginning 0))
                    (list (line-beginning-position) (line-end-position)))))
            (beginning-of-line)
            (when (re-search-backward regexp nil t)
              (save-excursion
                (goto-char (match-beginning 0))
                (list (line-beginning-position) (line-end-position))))))))))

(defun postgresql-trace--clear-match-overlays ()
  "Remove current trace match overlays."
  (mapc #'delete-overlay postgresql-trace--match-overlays)
  (setq postgresql-trace--match-overlays nil))

(defun postgresql-trace--make-match-overlay (start end face)
  "Create a trace match overlay from START to END using FACE."
  (let ((overlay (make-overlay start end)))
    (overlay-put overlay 'face face)
    (overlay-put overlay 'priority 1000)
    (push overlay postgresql-trace--match-overlays)))

(defun postgresql-trace-highlight-matching-entry ()
  "Highlight the trace entry matching the line at point."
  (postgresql-trace--clear-match-overlays)
  (let ((entry (postgresql-trace--line-entry))
        (match (postgresql-trace--matching-entry-position)))
    (when entry
      (postgresql-trace--make-match-overlay
       (nth 4 entry) (nth 5 entry)
       (if match 'show-paren-match 'show-paren-mismatch))
      (when match
        (postgresql-trace--make-match-overlay
         (car match) (cadr match) 'show-paren-match)))))

(defun postgresql-trace-jump-to-matching-entry ()
  "Jump between matching PostgreSQL trace call and return entries."
  (interactive)
  (let ((match (postgresql-trace--matching-entry-position)))
    (if match
        (goto-char (car match))
      (user-error "No matching PostgreSQL trace entry found"))))

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
  (add-hook 'post-command-hook #'postgresql-trace-highlight-matching-entry nil t)
  (outline-minor-mode 1))

;;;###autoload
(add-to-list 'auto-mode-alist '("postgres_lesson_.*\\.log\\'" . postgresql-trace-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.pgtrace\\'" . postgresql-trace-mode))

(provide 'postgresql-traces)

;;; postgresql-traces.el ends here
