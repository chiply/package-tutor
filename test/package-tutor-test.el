;;; package-tutor-test.el --- ERT smoke tests for package-tutor -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'info)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory
                (or load-file-name buffer-file-name)))))
(require 'package-tutor)


;;;; Fixtures
;;
;; A synthetic "package" named `pkgtut-fixture' exercising each bucket.

(defcustom pkgtut-fixture-greeting "hi"
  "A fixture option."
  :type 'string
  :group 'package-tutor)

(defun pkgtut-fixture-do-thing ()
  "Do the fixture thing interactively."
  (interactive)
  'done)

(defun pkgtut-fixture-add-thing ()
  "Create a fixture thing."
  (interactive)
  'added)

(defun pkgtut-fixture-delete-thing ()
  "Delete a fixture thing."
  (interactive)
  'deleted)

(defun pkgtut-fixture-show-thing ()
  "Show a fixture thing."
  (interactive)
  'shown)

(defun pkgtut-fixture-rename-thing ()
  "Rename a fixture thing."
  (interactive)
  'renamed)

(defun pkgtut-fixture-mode ()
  "A fixture mode command (name ends in -mode)."
  (interactive)
  'toggled)

(defvar pkgtut-fixture-some-hook nil
  "A fixture hook variable.")

(defface pkgtut-fixture-face '((t :weight bold))
  "A fixture face."
  :group 'package-tutor)

(defvar pkgtut-fixture-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "C-c C-t") #'pkgtut-fixture-do-thing)
    m)
  "A fixture keymap binding a fixture command.")

(defun pkgtut-fixture-helper-fn (x)
  "A non-interactive fixture function taking X."
  x)

(defmacro pkgtut-fixture-with-thing (&rest body)
  "A fixture macro wrapping BODY."
  `(progn ,@body))

(defun pkgtut-fixture--internal ()
  "An internal fixture function that must be skipped."
  nil)


;;;; Name matching

(ert-deftest pkgtut/name-match ()
  (should (package-tutor--name-match-p "foo" "foo"))
  (should (package-tutor--name-match-p "foo-bar" "foo"))
  (should (package-tutor--name-match-p "foo/bar" "foo"))
  (should-not (package-tutor--name-match-p "foobar" "foo"))
  (should-not (package-tutor--name-match-p "barfoo" "foo")))


;;;; Sorting

(ert-deftest pkgtut/sort-mode-first ()
  ;; -mode entries float to the top; each group sorts alphabetically.
  (should (equal '(a-mode z-mode b-cmd c-fn)
                 (package-tutor--sort '(c-fn b-cmd z-mode a-mode)))))

(ert-deftest pkgtut/sort-no-priority ()
  ;; nil regexp -> plain alphabetical order.
  (let ((package-tutor-sort-priority-regexp nil))
    (should (equal '(a-mode b-cmd c-fn z-mode)
                   (package-tutor--sort '(c-fn b-cmd z-mode a-mode))))))

(ert-deftest pkgtut/sort-custom-priority ()
  (let ((package-tutor-sort-priority-regexp "\\`enable-"))
    (should (equal '(enable-x b-thing c-thing)
                   (package-tutor--sort '(c-thing enable-x b-thing))))))


;;;; Collection / classification

(ert-deftest pkgtut/collect-classifies ()
  (let ((sets (package-tutor--collect "pkgtut-fixture")))
    (should (memq 'pkgtut-fixture-do-thing (plist-get sets :commands)))
    (should (memq 'pkgtut-fixture-greeting (plist-get sets :options)))
    (should (memq 'pkgtut-fixture-with-thing (plist-get sets :macros)))
    (should (memq 'pkgtut-fixture-helper-fn (plist-get sets :functions)))
    ;; A command must not also leak into the functions bucket.
    (should-not (memq 'pkgtut-fixture-do-thing (plist-get sets :functions)))))

(ert-deftest pkgtut/collect-hooks-and-faces ()
  (let ((sets (package-tutor--collect "pkgtut-fixture")))
    (should (memq 'pkgtut-fixture-some-hook (plist-get sets :hooks)))
    (should (memq 'pkgtut-fixture-face (plist-get sets :faces)))
    ;; A hook must not also leak into options.
    (should-not (memq 'pkgtut-fixture-some-hook (plist-get sets :options)))))

(ert-deftest pkgtut/render-hooks-and-faces-sections ()
  (let ((out (package-tutor--render 'pkgtut-fixture)))
    (should (string-match-p "^\\* Hooks" out))
    (should (string-match-p "pkgtut-fixture-some-hook" out))
    (should (string-match-p "^\\* Faces" out))
    (should (string-match-p "pkgtut-fixture-face" out))))


;;;; Keymap-aware key resolution

(ert-deftest pkgtut/feature-keymaps ()
  (let ((maps (package-tutor--feature-keymaps "pkgtut-fixture")))
    (should (cl-some #'keymapp maps))
    (should (where-is-internal 'pkgtut-fixture-do-thing maps t))))

(ert-deftest pkgtut/key-from-package-keymap ()
  ;; Resolved from the package's own keymap even with no active mode.
  (let ((package-tutor--keymap-list
         (package-tutor--feature-keymaps "pkgtut-fixture")))
    (should (equal "C-c C-t" (package-tutor--key 'pkgtut-fixture-do-thing)))))


;;;; Entry-point candidates

(ert-deftest pkgtut/candidate-features-includes-loaded ()
  (should (member "package-tutor" (package-tutor--candidate-features))))


;;;; Collection / classification (continued)

(ert-deftest pkgtut/collect-skips-internal ()
  (let ((package-tutor-include-internal nil))
    (let ((sets (package-tutor--collect "pkgtut-fixture")))
      (should-not (memq 'pkgtut-fixture--internal
                        (plist-get sets :functions)))))
  (let ((package-tutor-include-internal t))
    (let ((sets (package-tutor--collect "pkgtut-fixture")))
      (should (memq 'pkgtut-fixture--internal
                    (plist-get sets :functions))))))


;;;; Per-symbol details

(ert-deftest pkgtut/doc ()
  (should (string-match-p "fixture thing"
                          (package-tutor--doc 'pkgtut-fixture-do-thing 'command)))
  (should (string-match-p "fixture option"
                          (package-tutor--doc 'pkgtut-fixture-greeting 'option))))

(ert-deftest pkgtut/signature ()
  (should (string-match-p "pkgtut-fixture-helper-fn x"
                          (package-tutor--signature 'pkgtut-fixture-helper-fn))))

(ert-deftest pkgtut/value-string-truncates ()
  (let ((package-tutor-value-max-length 5)
        (pkgtut-fixture-greeting "abcdefghij"))
    (should (string-suffix-p "…"
                             (package-tutor--value-string 'pkgtut-fixture-greeting)))))


;;;; Rendering

(ert-deftest pkgtut/render-structure ()
  (let ((out (package-tutor--render 'pkgtut-fixture)))
    (should (string-match-p "^#\\+title: Tutorial: pkgtut-fixture" out))
    (should (string-match-p "^\\* Commands" out))
    (should (string-match-p "^\\* Options" out))
    ;; Command babel block is executable and calls the command.
    (should (string-match-p
             "begin_src emacs-lisp :results none\n(call-interactively #'pkgtut-fixture-do-thing)"
             out))
    ;; Option babel block opens customize.
    (should (string-match-p
             "(customize-variable 'pkgtut-fixture-greeting)" out))))

(ert-deftest pkgtut/render-indents-docstrings ()
  ;; A docstring beginning with "*" must be indented so org does not
  ;; read it as a heading.
  (should (string-prefix-p "  * star" (package-tutor--indent "* star"))))


;;;; CRUD classification

(ert-deftest pkgtut/crud-category ()
  (should (eq 'create (package-tutor--crud-category 'bookmark-set)))
  (should (eq 'create (package-tutor--crud-category 'org-roam-node-insert)))
  (should (eq 'read   (package-tutor--crud-category 'bookmark-jump)))
  (should (eq 'read   (package-tutor--crud-category 'bookmark-in-project-jump-next)))
  (should (eq 'update (package-tutor--crud-category 'bookmark-rename)))
  (should (eq 'delete (package-tutor--crud-category 'bookmark-delete)))
  (should (eq 'other  (package-tutor--crud-category 'bookmark-bmenu-mode))))

(ert-deftest pkgtut/crud-priority ()
  ;; "delete" outranks "create" by default priority.
  (let ((package-tutor-crud-priority '(delete create update read)))
    (should (eq 'delete (package-tutor--crud-category 'foo-add-then-delete))))
  ;; Flipping priority flips the winner.
  (let ((package-tutor-crud-priority '(create delete update read)))
    (should (eq 'create (package-tutor--crud-category 'foo-add-then-delete)))))

(ert-deftest pkgtut/render-crud-order ()
  ;; CRUD ordering is a flat list (no sub-headings) with the create
  ;; command before the delete one.
  (let* ((package-tutor-command-order 'crud)
         (out (package-tutor--render 'pkgtut-fixture)))
    (should-not (string-match-p "^\\*\\* Create" out))
    (should (< (string-match "pkgtut-fixture-add-thing" out)
               (string-match "pkgtut-fixture-delete-thing" out)))))

(ert-deftest pkgtut/render-crud-section-order ()
  ;; Default order is Create, Update, Read, Delete, Other -- asserted
  ;; via the commands themselves, since there are no sub-headings.
  (let* ((package-tutor-command-order 'crud)
         (out (package-tutor--render 'pkgtut-fixture)))
    (should (< (string-match "pkgtut-fixture-add-thing" out)     ; create
               (string-match "pkgtut-fixture-rename-thing" out)  ; update
               (string-match "pkgtut-fixture-show-thing" out)    ; read
               (string-match "pkgtut-fixture-delete-thing" out)  ; delete
               (string-match "pkgtut-fixture-do-thing" out)))))  ; other

(ert-deftest pkgtut/render-mode-leads-commands ()
  ;; A -mode command leads the whole Commands section, ahead of the
  ;; first CRUD group (create).
  (let* ((package-tutor-command-order 'crud)
         (out (package-tutor--render 'pkgtut-fixture)))
    (should (< (string-match "pkgtut-fixture-mode" out)
               (string-match "pkgtut-fixture-add-thing" out)))))

(ert-deftest pkgtut/render-alphabetical-order ()
  (let* ((package-tutor-command-order 'alphabetical)
         (out (package-tutor--render 'pkgtut-fixture)))
    ;; add < delete alphabetically.
    (should (< (string-match "pkgtut-fixture-add-thing" out)
               (string-match "pkgtut-fixture-delete-thing" out)))))


;;;; README section matching

(ert-deftest pkgtut/readme-section-markdown ()
  (let ((file (make-temp-file "pkgtut-readme" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "# Intro\n\nNothing here.\n\n"
                    "## Usage\n\nCall `pkgtut-fixture-do-thing` to act.\n\n"
                    "## Options\n\nSet pkgtut-fixture-greeting to taste.\n"))
          (let ((sections (package-tutor--parse-readme-sections file)))
            (should (equal "Usage"
                           (package-tutor--readme-section-for-symbol
                            "pkgtut-fixture-do-thing" sections)))
            (should (equal "Options"
                           (package-tutor--readme-section-for-symbol
                            "pkgtut-fixture-greeting" sections)))
            (should-not (package-tutor--readme-section-for-symbol
                         "pkgtut-fixture-nonexistent" sections))))
      (delete-file file))))

(ert-deftest pkgtut/readme-section-org ()
  (let ((file (make-temp-file "pkgtut-readme" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Intro\n\nNothing.\n\n"
                    "* Commands\n\nUse pkgtut-fixture-do-thing here.\n"))
          (should (equal "Commands"
                         (package-tutor--readme-section-for-symbol
                          "pkgtut-fixture-do-thing"
                          (package-tutor--parse-readme-sections file)))))
      (delete-file file))))

(ert-deftest pkgtut/readme-link-format ()
  (let ((file (make-temp-file "pkgtut-readme" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "## Usage\n\nCall pkgtut-fixture-do-thing.\n"))
          (let ((package-tutor--feature 'pkgtut-fixture)
                (package-tutor--readme-sections
                 (package-tutor--parse-readme-sections file)))
            (should (equal
                     "README: [[package-tutor-readme:pkgtut-fixture::Usage][Usage]]\n\n"
                     (package-tutor--readme-link 'pkgtut-fixture-do-thing)))
            ;; No section -> no link.
            (should-not (package-tutor--readme-link 'pkgtut-fixture-greeting))))
      (delete-file file))))

;;;; Info manual integration
;;
;; These exercise the real Info machinery against the bundled `org'
;; manual, which ships Function/Variable/Command indexes.

(ert-deftest pkgtut/info-manual-name ()
  (should (equal "org" (package-tutor--manual-name 'org)))
  (should-not (package-tutor--manual-name 'pkgtut-no-such-manual-xyz)))

(ert-deftest pkgtut/info-manual-name-alist ()
  (let ((package-tutor-info-manual-alist '((pkgtut-fixture . "org"))))
    ;; A feature with no manual of its own resolves via the alist.
    (should (equal "org" (package-tutor--manual-name 'pkgtut-fixture)))))

(ert-deftest pkgtut/info-index-build ()
  (let* ((file (Info-find-file "org" t))
         (idx (package-tutor--info-index-build file)))
    (should (> (hash-table-count idx) 100))
    ;; A known command and a known option resolve to non-empty nodes.
    (should (stringp (gethash "org-capture" idx)))
    (should (stringp (gethash "org-todo-keywords" idx)))))

(ert-deftest pkgtut/info-index-does-not-clobber-shared-info ()
  ;; Building the index must not disturb a user's *info* buffer.
  (with-current-buffer (get-buffer-create "*info*")
    (erase-buffer)
    (insert "SENTINEL"))
  (package-tutor--info-index-build (Info-find-file "org" t))
  (should (equal "SENTINEL"
                 (with-current-buffer "*info*" (buffer-string)))))

(ert-deftest pkgtut/info-link-format ()
  (let ((package-tutor--info-manual "org")
        (package-tutor--info-index
         (let ((h (make-hash-table :test 'equal)))
           (puthash "org-capture" "Activation" h)
           h)))
    (should (equal "Manual: [[info:org#Activation][Activation]]\n\n"
                   (package-tutor--info-link 'org-capture)))
    ;; Not indexed -> no link.
    (should-not (package-tutor--info-link 'org-not-indexed))
    ;; Disabled when no manual is bound.
    (let ((package-tutor--info-manual nil))
      (should-not (package-tutor--info-link 'org-capture)))))

;;;; Source links

(ert-deftest pkgtut/source-link-format ()
  (let ((package-tutor-include-source t))
    (should (equal "Source: [[package-tutor-source:fn/pkgtut-fixture-do-thing][source]]\n\n"
                   (package-tutor--source-link 'pkgtut-fixture-do-thing 'command)))
    (should (equal "Source: [[package-tutor-source:var/pkgtut-fixture-greeting][source]]\n\n"
                   (package-tutor--source-link 'pkgtut-fixture-greeting 'option))))
  (let ((package-tutor-include-source nil))
    (should-not (package-tutor--source-link 'pkgtut-fixture-do-thing 'command))))

(ert-deftest pkgtut/source-follow-dispatch ()
  (let (called)
    (cl-letf (((symbol-function 'find-function)
               (lambda (s) (setq called (list 'fn s))))
              ((symbol-function 'find-variable)
               (lambda (s) (setq called (list 'var s))))
              ((symbol-function 'find-function-other-window)
               (lambda (s) (setq called (list 'fn-ow s))))
              ((symbol-function 'find-variable-other-window)
               (lambda (s) (setq called (list 'var-ow s)))))
      ;; Same-window mode.
      (let ((package-tutor-source-other-window nil))
        (package-tutor-source-follow "fn/pkgtut-fixture-do-thing")
        (should (equal called '(fn pkgtut-fixture-do-thing)))
        (package-tutor-source-follow "var/pkgtut-fixture-greeting")
        (should (equal called '(var pkgtut-fixture-greeting))))
      ;; Other-window mode (the default).
      (let ((package-tutor-source-other-window t))
        (package-tutor-source-follow "fn/pkgtut-fixture-do-thing")
        (should (equal called '(fn-ow pkgtut-fixture-do-thing)))
        (package-tutor-source-follow "var/pkgtut-fixture-greeting")
        (should (equal called '(var-ow pkgtut-fixture-greeting)))))))

(ert-deftest pkgtut/source-follow-unknown-signals ()
  ;; A symbol not present on this machine errors rather than guessing.
  (should-error (package-tutor-source-follow "fn/pkgtut-unknown-symbol-xyz")))

(ert-deftest pkgtut/render-includes-source ()
  (let ((out (package-tutor--render 'pkgtut-fixture)))
    (should (string-match-p "package-tutor-source:fn/pkgtut-fixture-do-thing" out))
    (should (string-match-p "package-tutor-source:var/pkgtut-fixture-greeting" out))))

(ert-deftest pkgtut/render-readme-header-is-portable ()
  ;; The header README link must be the symbolic `package-tutor-readme:'
  ;; form, never an absolute file path (which would not survive moving
  ;; machines).
  (let* ((dir (make-temp-file "pkgtut-pkg" t))
         (readme (expand-file-name "README.md" dir)))
    (unwind-protect
        (progn
          (with-temp-file readme (insert "# Title\n\nbody\n"))
          (cl-letf (((symbol-function 'package-tutor--readme-file)
                     (lambda (_feature) readme)))
            (let ((out (package-tutor--render 'pkgtut-fixture)))
              (should (string-match-p
                       "README: \\[\\[package-tutor-readme:pkgtut-fixture\\]" out))
              (should-not (string-match-p "\\[\\[file:" out)))))
      (delete-directory dir t))))

;;;; Contents, counts and visibility

(ert-deftest pkgtut/section-title ()
  (let ((package-tutor-show-counts t))
    (should (equal "Commands (3)" (package-tutor--section-title "Commands" 3))))
  (let ((package-tutor-show-counts nil))
    (should (equal "Commands" (package-tutor--section-title "Commands" 3)))))

(ert-deftest pkgtut/render-contents-and-counts ()
  (let ((out (package-tutor--render 'pkgtut-fixture)))
    (should (string-match-p "^\\* Contents" out))
    (should (string-match-p "^\\* Commands ([0-9]+)" out))
    ;; Contents links to the (counted) Commands heading.
    (should (string-match-p "\\[\\[\\*Commands ([0-9]+)\\]" out))))

(ert-deftest pkgtut/render-counts-can-be-disabled ()
  (let* ((package-tutor-show-counts nil)
         (out (package-tutor--render 'pkgtut-fixture)))
    (should (string-match-p "^\\* Commands$" out))
    (should-not (string-match-p "^\\* Commands (" out))))

(ert-deftest pkgtut/render-startup-visibility ()
  (let ((package-tutor-initial-visibility 'content))
    (should (string-match-p "^#\\+startup: content$"
                            (package-tutor--render 'pkgtut-fixture)))))


;;;; Docstring symbol links

(ert-deftest pkgtut/linkify-doc ()
  (let ((package-tutor--symbol-kinds (make-hash-table :test 'equal)))
    (puthash "foo-cmd" "fn" package-tutor--symbol-kinds)
    (puthash "foo-opt" "var" package-tutor--symbol-kinds)
    ;; ASCII grave/apostrophe quoting.
    (let ((out (package-tutor--linkify-doc
                "Use `foo-cmd' and `foo-opt' and `bar'.")))
      (should (string-match-p "\\[\\[package-tutor-source:fn/foo-cmd\\]\\[foo-cmd\\]\\]" out))
      (should (string-match-p "\\[\\[package-tutor-source:var/foo-opt\\]\\[foo-opt\\]\\]" out))
      ;; Symbols not belonging to the package are left untouched.
      (should (string-match-p "`bar'" out)))
    ;; Curly quoting, as produced by `documentation'.
    (let ((out (package-tutor--linkify-doc "Use ‘foo-cmd’ here.")))
      (should (string-match-p "\\[\\[package-tutor-source:fn/foo-cmd\\]\\[foo-cmd\\]\\]" out)))))

(ert-deftest pkgtut/linkify-doc-disabled ()
  (let ((package-tutor-link-docstring-symbols nil)
        (package-tutor--symbol-kinds (make-hash-table :test 'equal)))
    (puthash "foo-cmd" "fn" package-tutor--symbol-kinds)
    (should (equal "`foo-cmd'" (package-tutor--linkify-doc "`foo-cmd'")))))


;;;; Curated overlay

(ert-deftest pkgtut/overlay-file-and-render ()
  (let* ((dir (make-temp-file "pkgtut-ov" t))
         (package-tutor-overlay-directory dir)
         (ovfile (expand-file-name "pkgtut-fixture-tutorial.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file ovfile (insert "* Guide\n\nHand-authored intro.\n"))
          (should (equal ovfile (package-tutor--overlay-file 'pkgtut-fixture)))
          (should (string-match-p "Hand-authored intro"
                                  (package-tutor--render 'pkgtut-fixture))))
      (delete-directory dir t))))

(ert-deftest pkgtut/overlay-disabled ()
  (let* ((dir (make-temp-file "pkgtut-ov" t))
         (package-tutor-overlay-directory dir)
         (package-tutor-include-overlay nil))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "pkgtut-fixture-tutorial.org" dir)
            (insert "intro"))
          (should-not (package-tutor--overlay-file 'pkgtut-fixture)))
      (delete-directory dir t))))


;;;; Entry by symbol, refresh and save

(ert-deftest pkgtut/symbol-feature ()
  ;; A symbol defined by this package resolves to its library name.
  (should (eq 'package-tutor (package-tutor--symbol-feature 'package-tutor))))

(ert-deftest pkgtut/refresh-requires-tutorial-buffer ()
  (with-temp-buffer
    (should-error (package-tutor-refresh))))

(ert-deftest pkgtut/empty-package-signals ()
  ;; A feature with no user-facing symbols errors rather than opening a
  ;; blank tutorial.
  (should-error (package-tutor 'pkgtut-no-such-feature-xyz)))

(ert-deftest pkgtut/save-writes-file ()
  (let* ((dir (make-temp-file "pkgtut-save" t))
         (package-tutor-save-directory dir))
    (unwind-protect
        (with-temp-buffer
          (setq package-tutor--buffer-feature 'pkgtut-fixture)
          (insert "tutorial body")
          (let ((file (package-tutor-save)))
            (should (file-exists-p file))
            (should (equal "pkgtut-fixture.org" (file-name-nondirectory file)))
            (with-temp-buffer
              (insert-file-contents file)
              (should (string-match-p "tutorial body" (buffer-string))))))
      (delete-directory dir t))))

(ert-deftest pkgtut/save-requires-tutorial-buffer ()
  (with-temp-buffer
    (should-error (package-tutor-save))))

(provide 'package-tutor-test)
;;; package-tutor-test.el ends here
