;;; packages.el --- postgresql-traces Layer packages File  -*- lexical-binding: nil; -*-
;;
;; Copyright (c) 2012-2025 Sylvain Benner & Contributors
;;
;; Author: jackgris
;; URL: https://github.com/syl20bnr/spacemacs
;;
;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(setq postgresql-traces-packages
      '((postgresql-traces :location local)))

(defun postgresql-traces/init-postgresql-traces ()
  (use-package postgresql-traces
    :defer t
    :mode (("postgres_lesson_.*\\.log\\'" . postgresql-trace-mode)
           ("\\.pgtrace\\'" . postgresql-trace-mode))
    :init
    (spacemacs/declare-prefix-for-mode 'postgresql-trace-mode "mg" "goto")
    (spacemacs/declare-prefix-for-mode 'postgresql-trace-mode "mo" "outline")
    (spacemacs/set-leader-keys-for-major-mode 'postgresql-trace-mode
      "%" 'postgresql-trace-jump-to-matching-entry
      "gn" 'postgresql-trace-next-entry
      "gp" 'postgresql-trace-previous-entry
      "oh" 'outline-hide-subtree
      "os" 'outline-show-subtree
      "oa" 'outline-show-all
      "oi" 'postgresql-trace-show-summary)))
