;;; package-tutor.el --- Auto-generate an org tutorial for any package -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Charlie Holland

;; Author: Charlie Holland <mister.chiply@gmail.com>
;; Maintainer: Charlie Holland <mister.chiply@gmail.com>
;; URL: https://github.com/chiply/package-tutor
;; x-release-please-start-version
;; Version: 0.1.1
;; x-release-please-end
;; Package-Requires: ((emacs "29.1"))
;; Keywords: help, docs, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Point `package-tutor' at any feature (loaded, or installed and
;; loaded on demand) and it gathers that package's user-facing surface
;; -- commands, customization options, hooks, faces, macros and config
;; functions -- and renders them into a single org-mode buffer that
;; reads like a tutorial:
;;
;;   - Each command is an *executable* `emacs-lisp' babel block: put
;;     point in the block and press `C-c C-c' to run the command.
;;   - Each option gets a babel block that opens `customize-variable'.
;;   - Where the package ships a README, the relevant section for a
;;     given symbol is offered as a followable `package-tutor-readme:'
;;     org link.
;;   - Where the package ships an Info manual, each symbol links to its
;;     exact manual node (resolved from the manual's indexes) via org's
;;     built-in `info:' link.
;;   - Each symbol gets a portable `Source:' link that jumps to its
;;     definition via `find-function'/`find-variable'.  The link stores
;;     only the symbol, so a saved tutorial resolves the source on
;;     whatever machine opens it.
;;   - `like-this' references in docstrings become source links to the
;;     package's own symbols.
;;   - The `;;; Commentary:' header (via `lisp-mnt') becomes an
;;     Overview heading, and a Contents section links to each section.
;;   - A curated `<feature>-tutorial.org' guide, if present, is woven in
;;     near the top (see `package-tutor-overlay-directory').
;;
;; Quick start:
;;
;;   (use-package package-tutor
;;     :ensure t
;;     :commands (package-tutor))
;;
;;   M-x package-tutor RET <feature> RET
;;
;; This package relies only on Emacs built-ins (org, lisp-mnt, info,
;; cl-lib).  It does not integrate with anything else.
;;
;; How symbols are gathered: every interned symbol whose name equals
;; the feature name or begins with "<feature>-" / "<feature>/" is
;; classified -- commands (`commandp'), macros (`macrop'), hooks
;; (name ending -hook/-functions), options (`custom-variable-p'),
;; functions (`fboundp') and faces (`facep').  Internal symbols (those
;; containing "--") are skipped unless `package-tutor-include-internal'
;; is non-nil.
;;
;; Entry points: `M-x package-tutor' (completes over loaded features
;; and installed packages); `T' in the package menu
;; (`package-tutor-from-package-menu'); and `T' / `M-x
;; package-tutor-for-symbol-at-point' to tutor the package owning the
;; symbol at point (e.g. in a help buffer).  In a tutorial buffer,
;; `C-c C-r' regenerates it and `C-c C-s' saves it to a file.

;;; Code:

(require 'cl-lib)
(require 'lisp-mnt)

;; Forward declarations -- `ol' (part of org), `info' and `find-func'
;; are required lazily.
(declare-function org-link-set-parameters "ol" (type &rest parameters))
(declare-function Info-find-file "info" (filename &optional noerror))
(declare-function Info-index-nodes "info" (&optional file))
(declare-function Info-find-node "info"
                  (filename nodename &optional no-going-back strict-case noerror))
(declare-function Info-mode "info" ())
(declare-function find-function "find-func" (function))
(declare-function find-variable "find-func" (variable))
(declare-function find-function-other-window "find-func" (function))
(declare-function find-variable-other-window "find-func" (variable))
(declare-function find-face-definition "find-func" (face))
(declare-function package-desc-name "package" (cl-x))
(declare-function tabulated-list-get-id "tabulated-list" (&optional pos))
(declare-function org-get-heading "org"
                  (&optional no-tags no-todo no-priority no-comment))

(defgroup package-tutor nil
  "Auto-generated org tutorials for Emacs packages."
  :group 'help
  :prefix "package-tutor-")

(defcustom package-tutor-include-macros t
  "When non-nil, include a Macros section in the tutorial."
  :type 'boolean)

(defcustom package-tutor-include-functions t
  "When non-nil, include a Functions section for non-interactive functions."
  :type 'boolean)

(defcustom package-tutor-include-internal nil
  "When non-nil, include internal symbols (those whose name contains \"--\")."
  :type 'boolean)

(defcustom package-tutor-include-hooks t
  "When non-nil, include a Hooks section.
Hooks are variables whose name ends in `-hook' or `-functions'."
  :type 'boolean)

(defcustom package-tutor-include-faces t
  "When non-nil, include a Faces section listing the package's faces."
  :type 'boolean)

(defcustom package-tutor-include-info t
  "When non-nil, link symbols to their Info manual node when one exists.
The manual is located with `Info-find-file' (see
`package-tutor-info-manual-alist'); each symbol is matched against the
manual's Function, Variable and Command indexes."
  :type 'boolean)

(defcustom package-tutor-info-manual-alist nil
  "Alist mapping a feature symbol to its Info manual name.
Consulted before falling back to the feature's own name.  Use this
when a package's manual is named differently from the feature, e.g.
\\='((magit-section . \"magit\"))."
  :type '(alist :key-type symbol :value-type string))

(defcustom package-tutor-include-source t
  "When non-nil, add a `Source:' link jumping to each symbol's definition.
The link stores only the symbol and whether it is a function or a
variable; the location is resolved on the local machine when followed,
via `find-function'/`find-variable'.  This keeps generated tutorials
portable: a saved tutorial works on any machine where the package is
installed, regardless of install path or version."
  :type 'boolean)

(defcustom package-tutor-source-other-window t
  "When non-nil, `Source:' links open the definition in another window.
This keeps the tutorial visible alongside the source.  When nil, the
source replaces the tutorial in the current window."
  :type 'boolean)

(defcustom package-tutor-confirm-babel t
  "Buffer-local value for `org-confirm-babel-evaluate' in tutorial buffers.
The default t makes Emacs ask before running a command block, which
is the safe choice.  Set to nil to run command blocks without a
prompt."
  :type '(choice (const :tag "Always confirm" t)
                 (const :tag "Never confirm" nil)
                 (function :tag "Predicate")))

(defcustom package-tutor-buffer-name-format "*package-tutor: %s*"
  "Format string for tutorial buffer names.  Receives the feature name."
  :type 'string)

(defcustom package-tutor-value-max-length 200
  "Maximum number of characters shown for an option's current value."
  :type 'natnum)

(defcustom package-tutor-command-order 'crud
  "How to order commands within the Commands section.

`crud'         Group commands by their detected lifecycle role and
               present them under Create / Read / Update / Delete /
               Other sub-headings, in that order.
`alphabetical' A single flat list sorted by name.

CRUD detection is heuristic: it matches verb tokens in the command
name against `package-tutor-crud-verbs'.  Most packages follow
verb-noun naming, but mis-classifications are expected for unusual
names -- tune `package-tutor-crud-verbs' to taste."
  :type '(choice (const :tag "Group by CRUD lifecycle" crud)
                 (const :tag "Alphabetical" alphabetical)))

(defcustom package-tutor-crud-verbs
  '((create . ("add" "create" "new" "make" "insert" "set" "capture"
               "record" "store" "register" "import" "generate" "define"
               "push" "enqueue" "init" "yank"))
    (read   . ("list" "show" "display" "view" "find" "goto" "jump"
               "open" "visit" "browse" "describe" "print" "search"
               "select" "next" "previous" "prev" "preview" "get"
               "peek" "info" "menu" "occur" "count"))
    (update . ("edit" "rename" "update" "modify" "change" "move"
               "replace" "annotate" "relocate" "toggle" "sort"
               "rotate" "swap" "reorder" "promote" "demote" "refile"
               "increment" "decrement"))
    (delete . ("delete" "remove" "kill" "clear" "purge" "reset"
               "drop" "clean" "wipe" "destroy" "unset" "trash"
               "discard" "flush")))
  "Alist mapping a CRUD category to the verb tokens that signal it.
Each command name is split on hyphens and slashes; if any resulting
token (compared case-insensitively) is in a category's list, the
command is assigned to that category.  Categories are tested in the
order given by `package-tutor-crud-priority'."
  :type '(alist :key-type (choice (const create) (const read)
                                  (const update) (const delete))
                :value-type (repeat string)))

(defcustom package-tutor-crud-priority '(delete create update read)
  "Order in which CRUD categories are tested when a name matches several.
The first matching category in this list wins."
  :type '(repeat symbol))

(defcustom package-tutor-crud-section-order '(create update read delete other)
  "Order in which commands are presented under Commands, by CRUD category.
Commands are listed as a single flat sequence ordered by category;
within a category they are sorted by name.  Update is placed before
Read by default because many \"update\" verbs (set, toggle, edit) also
create state.  Categories omitted from this list are not shown."
  :type '(repeat (choice (const create) (const update) (const read)
                         (const delete) (const other))))

(defcustom package-tutor-sort-priority-regexp "-mode\\'"
  "Regexp floating matching symbols to the top of each section.
Within every section, symbols whose name matches this regexp are
listed before those that do not; the two groups are each sorted
alphabetically.  The default, \"-mode\\\\='\", floats mode entry points
\(commands and functions ending in `-mode') to the top.  Set to nil for
plain alphabetical order with no priority group."
  :type '(choice (const :tag "No priority group" nil)
                 (regexp :tag "Priority regexp")))

(defcustom package-tutor-show-counts t
  "When non-nil, append an entry count to each section heading."
  :type 'boolean)

(defcustom package-tutor-include-contents t
  "When non-nil, insert a Contents section linking to each section."
  :type 'boolean)

(defcustom package-tutor-initial-visibility 'showeverything
  "Initial org folding of the tutorial buffer, via the `#+startup:' keyword.
`showeverything' expands all; `content' shows every heading folded (a
good outline for large packages); `overview' shows only top sections."
  :type '(choice (const showeverything) (const content) (const overview)))

(defcustom package-tutor-link-docstring-symbols t
  "When non-nil, turn `like-this' docstring references into source links.
Only symbols that belong to the package being rendered are linked."
  :type 'boolean)

(defcustom package-tutor-overlay-directory nil
  "Directory searched for a curated `<feature>-tutorial.org' guide.
When such a file is found (here, or beside the package's own source),
its contents are inserted near the top of the generated tutorial.  This
lets you hand-author narrative and exercises that the generated
reference material then follows."
  :type '(choice (const :tag "None" nil) directory))

(defcustom package-tutor-include-overlay t
  "When non-nil, prepend a curated guide file when one exists.
See `package-tutor-overlay-directory'."
  :type 'boolean)

(defcustom package-tutor-save-directory
  (locate-user-emacs-file "package-tutorials/")
  "Directory `package-tutor-save' writes tutorials to."
  :type 'directory)


;;;; Symbol gathering and classification

(defun package-tutor--name-match-p (name prefix)
  "Return non-nil when symbol NAME belongs to package PREFIX."
  (or (string= name prefix)
      (string-prefix-p (concat prefix "-") name)
      (string-prefix-p (concat prefix "/") name)))

(defun package-tutor--sort (syms)
  "Return SYMS sorted for display.
Symbols whose name matches `package-tutor-sort-priority-regexp' sort
before the rest; within each group sorting is alphabetical by name."
  (let ((re package-tutor-sort-priority-regexp))
    (sort syms
          (lambda (a b)
            (let* ((an (symbol-name a))
                   (bn (symbol-name b))
                   (ap (and re (string-match-p re an) t))
                   (bp (and re (string-match-p re bn) t)))
              (if (eq ap bp)
                  (string< an bn)
                ;; A priority match sorts first.
                ap))))))

(defun package-tutor--hook-p (sym)
  "Return non-nil when SYM is a hook variable (name ends -hook/-functions)."
  (let ((name (symbol-name sym)))
    (and (or (string-suffix-p "-hook" name)
             (string-suffix-p "-functions" name))
         (or (boundp sym) (get sym 'variable-documentation)))))

(defun package-tutor--collect (prefix)
  "Collect user-facing symbols for package PREFIX.
Return a plist with keys :commands :options :hooks :faces :macros
:functions, each a sorted list of symbols."
  (let (cmds opts hooks faces macros funcs)
    (mapatoms
     (lambda (sym)
       (let ((name (symbol-name sym)))
         (when (and (package-tutor--name-match-p name prefix)
                    (or package-tutor-include-internal
                        (not (string-search "--" name))))
           (cond
            ((commandp sym) (push sym cmds))
            ((and (fboundp sym) (macrop sym)) (push sym macros))
            ;; Hooks before options so custom hooks land in Hooks.
            ((package-tutor--hook-p sym) (push sym hooks))
            ((custom-variable-p sym) (push sym opts))
            ((fboundp sym) (push sym funcs))
            ((facep sym) (push sym faces)))))))
    (list :commands   (package-tutor--sort cmds)
          :options    (package-tutor--sort opts)
          :hooks      (package-tutor--sort hooks)
          :faces      (package-tutor--sort faces)
          :macros     (package-tutor--sort macros)
          :functions  (package-tutor--sort funcs))))

(defun package-tutor--feature-keymaps (prefix)
  "Return the keymaps bound to variables whose name matches PREFIX.
Used to resolve key bindings even when the package's mode is inactive."
  (let (maps)
    (mapatoms
     (lambda (sym)
       (when (and (package-tutor--name-match-p (symbol-name sym) prefix)
                  (boundp sym)
                  (keymapp (symbol-value sym)))
         (push (symbol-value sym) maps))))
    maps))


;;;; CRUD classification

(defun package-tutor--crud-category (sym)
  "Return SYM's CRUD category: `create', `read', `update', `delete', or `other'.
The name is split into tokens on \"-\" and \"/\" and matched against
`package-tutor-crud-verbs', testing categories in
`package-tutor-crud-priority' order."
  (let ((tokens (split-string (downcase (symbol-name sym)) "[-/]" t)))
    (or (cl-loop for cat in package-tutor-crud-priority
                 for verbs = (cdr (assq cat package-tutor-crud-verbs))
                 when (cl-intersection tokens verbs :test #'string=)
                 return cat)
        'other)))

(defun package-tutor--group-by-crud (cmds)
  "Group command symbols CMDS into an alist keyed by CRUD category."
  (let (groups)
    (dolist (sym cmds)
      (push sym (alist-get (package-tutor--crud-category sym) groups)))
    groups))


;;;; Per-symbol details

(defun package-tutor--doc (sym kind)
  "Return the documentation string for SYM of KIND."
  (string-trim
   (or (pcase kind
         ((or 'command 'function 'macro) (documentation sym))
         ((or 'option 'hook) (documentation-property sym 'variable-documentation))
         ('face (documentation-property sym 'face-documentation)))
       "Undocumented.")))

(defun package-tutor--signature (sym)
  "Return a readable calling signature for function SYM."
  (let ((arglist (ignore-errors (help-function-arglist sym t))))
    (cond
     ((listp arglist) (format "%S" (cons sym arglist)))
     (arglist (format "(%s %s)" sym arglist))
     (t (format "(%s ...)" sym)))))

(defvar package-tutor--keymap-list nil
  "List of the rendered package's keymaps, dynamically bound while rendering.")

(defun package-tutor--real-key-p (key)
  "Return non-nil when KEY is a real key sequence, not a menu entry.
Rejects menu-bar/tool-bar/tab-bar prefixes and menu-item events (whose
symbol names contain spaces, e.g. `Go to next problem')."
  (cl-notany (lambda (e)
               (or (memq e '(menu-bar tool-bar tab-bar))
                   (and (symbolp e) (string-search " " (symbol-name e)))))
             (append key nil)))

(defun package-tutor--key (sym)
  "Return a key description for command SYM, or nil.
Searches the package's own keymaps (`package-tutor--keymap-list') and
the global map, so bindings are found even when the package's mode is
not currently active.  Menu-bar and similar pseudo-key bindings are
ignored so only real key sequences are reported."
  (let* ((maps (append package-tutor--keymap-list (list (current-global-map))))
         (key (cl-find-if #'package-tutor--real-key-p
                          (where-is-internal sym maps))))
    (and key (key-description key))))

(defun package-tutor--value-string (sym)
  "Return a one-line printed representation of option SYM's value."
  (when (boundp sym)
    (let ((s (replace-regexp-in-string
              "\n" " " (prin1-to-string (symbol-value sym)))))
      (if (> (length s) package-tutor-value-max-length)
          (concat (substring s 0 package-tutor-value-max-length) "…")
        s))))


;;;; Rendering state (dynamically bound by `package-tutor--render')

;; Bound during a render so the per-entry helpers can reach the feature
;; and its doc sources without threading them through every call.
(defvar package-tutor--feature nil
  "Feature symbol currently being rendered.")
(defvar package-tutor--readme nil
  "README file for the feature being rendered, or nil.")
(defvar package-tutor--readme-sections nil
  "Parsed README sections (list of (TITLE . BODY)) for the rendered feature.")
(defvar package-tutor--info-manual nil
  "Info manual name for the feature being rendered, or nil.")
(defvar package-tutor--info-index nil
  "Hash table mapping symbol name to Info node, or nil.")
(defvar package-tutor--symbol-kinds nil
  "Hash table mapping a package symbol name to its source-link kind string.")

(defvar-local package-tutor--buffer-feature nil
  "In a tutorial buffer, the feature it documents.  Used by refresh/save.")


;;;; README discovery and section matching

(defun package-tutor--readme-file (feature)
  "Return the README file shipped alongside FEATURE, or nil."
  (let* ((lib (locate-library (symbol-name feature)))
         (dir (and lib (file-name-directory lib))))
    (when dir
      (car (sort (directory-files dir t "\\`[Rr][Ee][Aa][Dd][Mm][Ee]")
                 #'string<)))))

(defun package-tutor--commentary (feature)
  "Return the trimmed `;;; Commentary:' text for FEATURE, or nil."
  (let* ((lib (locate-library (symbol-name feature)))
         (el (and lib (concat (file-name-sans-extension lib) ".el"))))
    (when (and el (file-readable-p el))
      (let ((c (ignore-errors (lm-commentary el))))
        (when (and c (not (string-empty-p (string-trim c))))
          (string-trim c))))))

(defun package-tutor--parse-readme-sections (file)
  "Parse README FILE once into a list of (TITLE . BODY) conses.
BODY includes the heading line through to just before the next heading.
Headings are recognised in both org (\"* \") and Markdown (\"# \") form.
Returns nil when FILE is missing or unreadable."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (let* ((md (member (downcase (or (file-name-extension file) ""))
                         '("md" "markdown")))
             (hre (if md "^\\(#+\\)[ \t]+\\(.*\\)$"
                    "^\\(\\*+\\)[ \t]+\\(.*\\)$"))
             headings sections)
        (goto-char (point-min))
        (while (re-search-forward hre nil t)
          (push (list (match-beginning 0) (string-trim (match-string 2)))
                headings))
        (setq headings (nreverse headings))
        (let ((n (length headings)))
          (cl-loop for i from 0 below n
                   for start = (car (nth i headings))
                   for title = (cadr (nth i headings))
                   for end = (if (< (1+ i) n)
                                 (car (nth (1+ i) headings))
                               (point-max))
                   do (push (cons title (buffer-substring-no-properties start end))
                            sections)))
        (nreverse sections)))))

(defun package-tutor--readme-section-for-symbol (symname &optional sections)
  "Return the title of the first README section mentioning SYMNAME, or nil.
SECTIONS is a list of (TITLE . BODY) conses; it defaults to the
dynamically bound `package-tutor--readme-sections'."
  (let ((symre (regexp-quote symname)))
    (cl-loop for (title . body) in (or sections package-tutor--readme-sections)
             when (string-match-p symre body)
             return title)))

(defun package-tutor--readme-link (sym)
  "Return a `package-tutor-readme:' link for SYM, or nil when no section matches.
Uses `package-tutor--readme-sections' and `package-tutor--feature'."
  (when-let* ((section (package-tutor--readme-section-for-symbol (symbol-name sym))))
    (format "README: [[package-tutor-readme:%s::%s][%s]]\n\n"
            package-tutor--feature section section)))


;;;; Info manual integration

(defun package-tutor--manual-name (feature)
  "Return the Info manual name for FEATURE if such a manual exists, else nil.
Tries `package-tutor-info-manual-alist' first, then FEATURE's name."
  (require 'info)
  (let ((name (or (cdr (assq feature package-tutor-info-manual-alist))
                  (symbol-name feature))))
    (when (ignore-errors (Info-find-file name t))
      name)))

(defun package-tutor--info-index-build (file)
  "Return a hash table mapping symbol name to Info node, built from FILE.
All of the manual's index nodes are scanned (manuals name them
inconsistently -- \"Index\", \"Function Index\", etc.).  Concept entries
that contain spaces never match a symbol lookup, so they are harmless.
Symbol-style index nodes (Function/Variable/Command) are scanned last
so their nodes win any collision with a concept entry.  The scan runs
in a private buffer and never disturbs the user's `*info*' buffer."
  (require 'info)
  (let* ((map (make-hash-table :test 'equal))
         (nodes (ignore-errors (Info-index-nodes file)))
         (symbolp (lambda (n) (string-match-p "Function\\|Variable\\|Command" n)))
         (ordered (append (cl-remove-if symbolp nodes)
                          (cl-remove-if-not symbolp nodes))))
    (with-temp-buffer
      ;; A dedicated name keeps `Info-find-node' (which reuses the
      ;; current Info-mode buffer) away from the shared "*info*" buffer.
      (rename-buffer " *package-tutor-info-scan*" t)
      (Info-mode)
      (dolist (node ordered)
        (ignore-errors (Info-find-node file node))
        (goto-char (point-min))
        (while (re-search-forward
                "^\\* \\([^:\n]+\\): +\\(.+?\\)\\.\\(?: *(line.*)\\)?[ \t]*$"
                nil t)
          (puthash (match-string-no-properties 1)
                   (match-string-no-properties 2) map))))
    map))

(defun package-tutor--info-link (sym)
  "Return an org `info:' link string for SYM, or nil when it is not indexed.
Uses the manual and index bound during rendering."
  (when (and package-tutor--info-manual package-tutor--info-index)
    (when-let* ((node (gethash (symbol-name sym) package-tutor--info-index)))
      (format "Manual: [[info:%s#%s][%s]]\n\n"
              package-tutor--info-manual node node))))


;;;; Source links (portable across machines)

(defun package-tutor--source-link (sym kind)
  "Return a portable `package-tutor-source:' link to SYM's definition, or nil.
KIND selects the finder: options and variables use `find-variable',
everything else uses `find-function'.  The link encodes only the
symbol and finder, so it resolves wherever the package is installed."
  (when package-tutor-include-source
    (format "Source: [[package-tutor-source:%s/%s][source]]\n\n"
            (pcase kind
              ((or 'option 'variable 'hook) "var")
              ('face "face")
              (_ "fn"))
            sym)))

;;;###autoload
(defun package-tutor-source-follow (path &optional _arg)
  "Follow a `package-tutor-source:' link with PATH of the form \"KIND/SYMBOL\".
KIND is \"var\", \"fn\" or \"face\".  The definition is located on the
current machine, so the link is portable across machines and versions."
  (require 'find-func)
  (pcase-let* ((`(,kind ,name) (split-string path "/"))
               (sym (and name (intern name))))
    (unless (and sym (or (fboundp sym) (boundp sym) (facep sym)))
      (user-error "`%s' is not defined here -- is the package installed?" name))
    (condition-case err
        (pcase (cons kind package-tutor-source-other-window)
          (`("face" . ,_) (find-face-definition sym))
          (`("var" . nil) (find-variable sym))
          ('("var" . t)   (find-variable-other-window sym))
          (`(,_ . nil)    (find-function sym))
          (_              (find-function-other-window sym)))
      (error (user-error "Cannot locate source for `%s': %s"
                         name (error-message-string err))))))


;;;; The `package-tutor-readme:' org link type

(defun package-tutor--goto-section (title)
  "Move point to the heading whose text is TITLE in the current buffer."
  (goto-char (point-min))
  (when (re-search-forward
         (concat "^[*#]+[ \t]+" (regexp-quote title) "[ \t]*$") nil t)
    (beginning-of-line)
    (when (and (derived-mode-p 'org-mode) (fboundp 'org-fold-show-context))
      (ignore-errors (org-fold-show-context)))
    (recenter 0)))

;;;###autoload
(defun package-tutor-readme-follow (path &optional _arg)
  "Follow a `package-tutor-readme:' link with PATH \"FEATURE::SECTION\".
SECTION is optional; without it the README is opened at its top."
  (let* ((parts (split-string path "::"))
         (feature (intern (car parts)))
         (section (and (cadr parts) (string-trim (cadr parts))))
         (file (package-tutor--readme-file feature)))
    (unless (and file (file-exists-p file))
      (user-error "No README found for `%s'" feature))
    (find-file-other-window file)
    (when (and section (not (string-empty-p section)))
      (package-tutor--goto-section section))))

(defun package-tutor--register-link ()
  "Register the `package-tutor-readme:' and `package-tutor-source:' link types."
  (require 'ol)
  (org-link-set-parameters "package-tutor-readme" :follow #'package-tutor-readme-follow)
  (org-link-set-parameters "package-tutor-source" :follow #'package-tutor-source-follow))

;;;###autoload
(with-eval-after-load 'ol
  ;; Autoloaded so the link types resolve when a saved tutorial is
  ;; opened in a fresh session, before this file has otherwise loaded.
  (org-link-set-parameters "package-tutor-readme" :follow #'package-tutor-readme-follow)
  (org-link-set-parameters "package-tutor-source" :follow #'package-tutor-source-follow))


;;;; Rendering

(defun package-tutor--indent (text &optional n)
  "Indent every line of TEXT by N (default 2) spaces.
This keeps docstring lines that begin with \"*\" or \"#\" from being
parsed as org structure."
  (let ((pad (make-string (or n 2) ?\s)))
    (replace-regexp-in-string "^" pad text)))

(defun package-tutor--section-title (title count)
  "Return TITLE with COUNT appended when `package-tutor-show-counts' is on."
  (if package-tutor-show-counts (format "%s (%d)" title count) title))

(defun package-tutor--insert-contents (specs)
  "Insert a Contents section linking to each (TITLE . COUNT) in SPECS.
Entries with a zero count are omitted."
  (let ((shown (cl-remove-if (lambda (s) (zerop (cdr s))) specs)))
    (when shown
      (insert "* Contents\n\n")
      (dolist (s shown)
        (let ((heading (package-tutor--section-title (car s) (cdr s))))
          (insert (format "- [[*%s][%s]]\n" heading heading))))
      (insert "\n"))))

(defun package-tutor--link-kind (kind)
  "Map an entry KIND to a `package-tutor-source:' finder tag (\"fn\"/\"var\"/\"face\")."
  (pcase kind
    ((or 'option 'variable 'hook) "var")
    ('face "face")
    (_ "fn")))

(defun package-tutor--linkify-doc (text)
  "Turn `like-this' references in TEXT into `package-tutor-source:' links.
Only symbols in `package-tutor--symbol-kinds' (i.e. this package's own
symbols) are linked; other quoted references are left untouched."
  (if (or (not package-tutor-link-docstring-symbols)
          (not package-tutor--symbol-kinds))
      text
    (replace-regexp-in-string
     ;; Opening quote may be ASCII grave or curly left; closing may be
     ;; ASCII apostrophe or curly right (per `text-quoting-style').
     "[`‘]\\([a-zA-Z0-9/_*+-]+\\)['’]"
     (lambda (m)
       (let* ((name (match-string 1 m))
              (kind (gethash name package-tutor--symbol-kinds)))
         (if kind
             (format "[[package-tutor-source:%s/%s][%s]]" kind name name)
           m)))
     text t t)))

(defun package-tutor--overlay-file (feature)
  "Return a curated `<feature>-tutorial.org' guide file for FEATURE, or nil.
Searches `package-tutor-overlay-directory' then the package's own dir."
  (when package-tutor-include-overlay
    (let* ((base (format "%s-tutorial.org" feature))
           (lib (locate-library (symbol-name feature)))
           (dirs (list package-tutor-overlay-directory
                       (and lib (file-name-directory lib)))))
      (cl-loop for dir in dirs
               when (and dir (file-readable-p (expand-file-name base dir)))
               return (expand-file-name base dir)))))

(defun package-tutor--src-block (sym kind)
  "Return an executable babel block for SYM of KIND, or nil."
  (pcase kind
    ('command
     (format "#+begin_src emacs-lisp :results none\n(call-interactively #'%s)\n#+end_src\n"
             sym))
    ('option
     (format "#+begin_src emacs-lisp :results none\n(customize-variable '%s)\n#+end_src\n"
             sym))
    (_ nil)))

(defun package-tutor--insert-entry (sym kind &optional level)
  "Insert the org entry for SYM (of KIND) into the current buffer.
LEVEL is the org heading depth (number of leading stars), default 2.
The feature and its doc sources are taken from the dynamically bound
`package-tutor--feature', `package-tutor--readme' and Info variables."
  (insert (format "%s %s\n\n" (make-string (or level 2) ?*) sym))
  (pcase kind
    ('command
     (let ((key (package-tutor--key sym)))
       (when key (insert (format "- Key: ~%s~\n\n" key)))))
    ((or 'function 'macro)
     (insert (format "- Signature: ~%s~\n\n" (package-tutor--signature sym))))
    ((or 'option 'hook)
     (let ((v (package-tutor--value-string sym)))
       (when v (insert (format "- Current value: ~%s~\n\n" v))))))
  (insert (package-tutor--indent
           (package-tutor--linkify-doc (package-tutor--doc sym kind)))
          "\n\n")
  (when-let* ((link (package-tutor--info-link sym)))
    (insert link))
  (when-let* ((link (package-tutor--readme-link sym)))
    (insert link))
  (when-let* ((link (package-tutor--source-link sym kind)))
    (insert link))
  (when-let* ((src (package-tutor--src-block sym kind)))
    (insert src "\n")))

(defun package-tutor--insert-section (title syms kind)
  "Insert a TITLE section listing SYMS (of KIND)."
  (when syms
    (insert (format "* %s\n\n" (package-tutor--section-title title (length syms))))
    (dolist (sym syms)
      (package-tutor--insert-entry sym kind))))

(defun package-tutor--priority-partition (syms)
  "Split SYMS into (PRIORITY . REST) by `package-tutor-sort-priority-regexp'.
PRIORITY holds the symbols whose name matches; REST holds the others.
When the regexp is nil, PRIORITY is empty and REST is all of SYMS."
  (let ((re package-tutor-sort-priority-regexp))
    (if (not re)
        (cons nil syms)
      (let (priority rest)
        (dolist (sym syms)
          (if (string-match-p re (symbol-name sym))
              (push sym priority)
            (push sym rest)))
        (cons (nreverse priority) (nreverse rest))))))

(defun package-tutor--insert-commands (cmds)
  "Insert the Commands section for CMDS, honouring `package-tutor-command-order'.
Under CRUD ordering, commands matching `package-tutor-sort-priority-regexp'
\(by default those ending in `-mode') lead the whole section, ahead of
the CRUD groups."
  (when cmds
    (insert (format "* %s\n\n"
                    (package-tutor--section-title "Commands" (length cmds))))
    (pcase package-tutor-command-order
      ('crud
       (pcase-let* ((`(,priority . ,rest) (package-tutor--priority-partition cmds))
                    (groups (package-tutor--group-by-crud rest)))
         ;; Priority (e.g. `-mode') commands lead the entire section.
         (dolist (sym (package-tutor--sort priority))
           (package-tutor--insert-entry sym 'command 2))
         (dolist (cat package-tutor-crud-section-order)
           (dolist (sym (package-tutor--sort (cdr (assq cat groups))))
             (package-tutor--insert-entry sym 'command 2)))))
      (_
       ;; Alphabetical mode: `package-tutor--sort' already floats the
       ;; priority group to the front of the flat list.
       (dolist (sym (package-tutor--sort cmds))
         (package-tutor--insert-entry sym 'command 2))))))

(defun package-tutor--build-symbol-kinds (sets)
  "Return a hash of symbol name -> source-link kind from collected SETS."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (pair '((:commands . command) (:macros . macro)
                    (:functions . function) (:options . option)
                    (:hooks . hook) (:faces . face)))
      (dolist (sym (plist-get sets (car pair)))
        (puthash (symbol-name sym) (package-tutor--link-kind (cdr pair)) h)))
    h))

(defun package-tutor--render (feature)
  "Return the org tutorial text for FEATURE as a string."
  (let* ((sets (package-tutor--collect (symbol-name feature)))
         (cmds   (plist-get sets :commands))
         (opts   (plist-get sets :options))
         (hooks  (plist-get sets :hooks))
         (faces  (plist-get sets :faces))
         (macros (plist-get sets :macros))
         (funcs  (plist-get sets :functions))
         (package-tutor--feature feature)
         (package-tutor--symbol-kinds (package-tutor--build-symbol-kinds sets))
         (package-tutor--keymap-list
          (package-tutor--feature-keymaps (symbol-name feature)))
         (package-tutor--readme (package-tutor--readme-file feature))
         (package-tutor--readme-sections
          (package-tutor--parse-readme-sections package-tutor--readme))
         (package-tutor--info-manual
          (and package-tutor-include-info
               (package-tutor--manual-name feature)))
         (package-tutor--info-index
          (when-let* ((manual package-tutor--info-manual)
                      (file (ignore-errors (Info-find-file manual t))))
            (package-tutor--info-index-build file)))
         (overlay (package-tutor--overlay-file feature)))
    (with-temp-buffer
      (insert (format "#+title: Tutorial: %s\n" feature))
      (insert (format "#+startup: %s\n\n" package-tutor-initial-visibility))
      (when-let* ((c (package-tutor--commentary feature)))
        (insert "* Overview\n\n" (package-tutor--indent c) "\n\n"))
      (when package-tutor--info-manual
        (insert (format "Manual: [[info:%s][%s (Info)]]\n\n"
                        package-tutor--info-manual package-tutor--info-manual)))
      (when package-tutor--readme
        ;; Use the symbolic `package-tutor-readme:' link (re-resolved at
        ;; follow time) rather than an absolute file path, so the
        ;; tutorial stays portable across machines.
        (insert (format "README: [[package-tutor-readme:%s][%s]]\n\n"
                        feature
                        (file-name-nondirectory package-tutor--readme))))
      ;; Curated guide (hand-authored narrative), inserted verbatim.
      (when overlay
        (insert-file-contents overlay)
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert "\n"))
      (when package-tutor-include-contents
        (package-tutor--insert-contents
         (delq nil
               (list (cons "Commands" (length cmds))
                     (cons "Options" (length opts))
                     (and package-tutor-include-hooks (cons "Hooks" (length hooks)))
                     (and package-tutor-include-faces (cons "Faces" (length faces)))
                     (and package-tutor-include-macros (cons "Macros" (length macros)))
                     (and package-tutor-include-functions
                          (cons "Functions" (length funcs)))))))
      (package-tutor--insert-commands cmds)
      (package-tutor--insert-section "Options" opts 'option)
      (when package-tutor-include-hooks
        (package-tutor--insert-section "Hooks" hooks 'hook))
      (when package-tutor-include-faces
        (package-tutor--insert-section "Faces" faces 'face))
      (when package-tutor-include-macros
        (package-tutor--insert-section "Macros" macros 'macro))
      (when package-tutor-include-functions
        (package-tutor--insert-section "Functions" funcs 'function))
      (buffer-string))))


;;;; Entry point

(defun package-tutor--candidate-features ()
  "Return completion candidates: loaded features plus installed packages.
Including installed-but-unloaded packages means you can tutor a package
without having loaded it first; `package-tutor' loads it on demand."
  (let ((cands (mapcar #'symbol-name features)))
    (when (bound-and-true-p package-alist)
      (dolist (entry package-alist)
        (push (symbol-name (car entry)) cands)))
    (when (bound-and-true-p package-activated-list)
      (dolist (p package-activated-list)
        (push (symbol-name p) cands)))
    (sort (delete-dups cands) #'string<)))

(defun package-tutor--read-feature ()
  "Read a feature/package name, defaulting to the symbol at point."
  (intern
   (completing-read
    "Package/feature: "
    (package-tutor--candidate-features)
    nil nil nil nil
    (when-let* ((s (symbol-at-point)))
      (and (or (featurep s) (memq s (bound-and-true-p package-activated-list)))
           (symbol-name s))))))

;;;###autoload
(defun package-tutor-from-package-menu ()
  "Open a tutorial for the package at point in `package-menu-mode'."
  (interactive)
  (let ((desc (tabulated-list-get-id)))
    (unless desc (user-error "No package at point"))
    (package-tutor (package-desc-name desc))))

;;;###autoload
(with-eval-after-load 'package
  ;; Bind T in the package menu, but never clobber an existing binding.
  (when (and (boundp 'package-menu-mode-map)
             (not (lookup-key package-menu-mode-map "T")))
    (define-key package-menu-mode-map "T" #'package-tutor-from-package-menu)))

;;;; Tutorial buffer mode and actions

(defvar package-tutor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-r") #'package-tutor-refresh)
    (define-key map (kbd "C-c C-s") #'package-tutor-save)
    map)
  "Keymap for `package-tutor-mode'.")

(defun package-tutor--revert (&rest _)
  "Revert function for tutorial buffers: regenerate from the feature."
  (when package-tutor--buffer-feature
    (package-tutor-refresh)))

(define-derived-mode package-tutor-mode org-mode "Pkg-Tutor"
  "Major mode for `package-tutor' buffers, derived from `org-mode'.
Org navigation, folding, and command-block evaluation all apply.

\\{package-tutor-mode-map}"
  (setq-local org-confirm-babel-evaluate package-tutor-confirm-babel)
  (setq-local revert-buffer-function #'package-tutor--revert))

(defun package-tutor-refresh ()
  "Regenerate the current tutorial, keeping point near the same heading."
  (interactive)
  (unless package-tutor--buffer-feature
    (user-error "Not a package-tutor buffer"))
  (let ((feature package-tutor--buffer-feature)
        (heading (and (derived-mode-p 'org-mode)
                      (ignore-errors (org-get-heading t t t t)))))
    (package-tutor feature)
    (when heading
      (goto-char (point-min))
      (when (re-search-forward
             (concat "^\\*+ +" (regexp-quote heading) "[ \t]*$") nil t)
        (beginning-of-line)
        (recenter 0)))))

(defun package-tutor-save (&optional file)
  "Write the current tutorial to FILE.
With a prefix argument, prompt for FILE; otherwise default to
\"<feature>.org\" under `package-tutor-save-directory'.  Because the
tutorial's links are symbolic, the saved file works on any machine
where the package is installed."
  (interactive
   (list (when current-prefix-arg
           (read-file-name "Save tutorial to: " package-tutor-save-directory))))
  (unless package-tutor--buffer-feature
    (user-error "Not a package-tutor buffer"))
  (let ((file (or file
                  (expand-file-name
                   (format "%s.org" package-tutor--buffer-feature)
                   package-tutor-save-directory))))
    (make-directory (file-name-directory file) t)
    (write-region (point-min) (point-max) file)
    (message "Saved tutorial to %s" file)
    file))

(defun package-tutor--symbol-feature (sym)
  "Return the feature/library that defines SYM, as a symbol, or nil."
  (when-let* ((file (cond ((fboundp sym) (symbol-file sym 'defun))
                          ((boundp sym) (symbol-file sym 'defvar))
                          (t (symbol-file sym)))))
    (intern (file-name-base file))))

;;;###autoload
(defun package-tutor-for-symbol-at-point ()
  "Open a tutorial for the package that defines the symbol at point."
  (interactive)
  (let* ((sym (symbol-at-point))
         (feature (and sym (package-tutor--symbol-feature sym))))
    (unless feature
      (user-error "No package found for symbol at point"))
    (package-tutor feature)))

;;;###autoload
(with-eval-after-load 'help-mode
  (when (and (boundp 'help-mode-map)
             (not (lookup-key help-mode-map "T")))
    (define-key help-mode-map "T" #'package-tutor-for-symbol-at-point)))

;;;###autoload
(defun package-tutor (feature)
  "Generate and display an Org tutorial for FEATURE.

The tutorial gathers FEATURE's commands, options, macros and
functions, renders each as an org heading with its documentation,
links any matching README section, and wraps every command in an
executable `emacs-lisp' babel block."
  (interactive (list (package-tutor--read-feature)))
  (unless (featurep feature)
    (require feature nil t))
  (let ((sets (package-tutor--collect (symbol-name feature))))
    (unless (cl-some (lambda (k) (plist-get sets k))
                     '(:commands :options :hooks :faces :macros :functions))
      (user-error "No user-facing symbols found for `%s' -- is it loaded under that name?"
                  feature)))
  (package-tutor--register-link)
  (let ((buf (get-buffer-create (format package-tutor-buffer-name-format feature)))
        (text (package-tutor--render feature)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text))
      (goto-char (point-min))
      (package-tutor-mode)
      (setq package-tutor--buffer-feature feature))
    (pop-to-buffer buf)
    buf))

(provide 'package-tutor)
;;; package-tutor.el ends here
