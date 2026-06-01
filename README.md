# package-tutor

Generate an interactive **org-mode tutorial** for any Emacs package.

Emacs ships `help-with-tutorial`, and packages like `meow` ship
`meow-tutor` — but those are hand-written. `package-tutor` instead
*introspects* a package and assembles its user-facing surface into a
single org buffer that you can read, run, and explore.

For the chosen feature it gathers:

- **Commands** (`commandp`) — each rendered as an *executable*
  `emacs-lisp` babel block. Put point in the block and press `C-c C-c`
  to run the command.
- **Options** (`custom-variable-p`) — shown with their current value
  and a babel block that opens `customize-variable`.
- **Hooks** (name ending `-hook`/`-functions`) and **Faces** (`facep`)
  — extension and appearance points, with their docs.
- **Macros** (`macrop`) and **Functions** — shown with their calling
  signature and documentation.
- A **Key:** line per command, resolved from the package's own keymaps
  (e.g. `<feature>-mode-map`) so bindings show even when the mode is
  inactive; menu entries are filtered out.
- An **Overview** taken from the package's `;;; Commentary:` header
  (via `lisp-mnt`).
- A followable **`package-tutor-readme:` org link** to the README
  section most relevant to each symbol, when the package ships a README.
- A followable **`info:` org link** to each symbol's exact node in the
  package's Info manual, when one exists (resolved from the manual's
  Function/Variable/Command indexes).
- A **`Source:` link** that jumps to each symbol's definition. The link
  is portable — it stores only the symbol, and the location is resolved
  on whatever machine opens the tutorial.
- **Docstring cross-links** — `` `like-this' `` references in
  documentation become source links to the package's own symbols.
- A **Contents** section with per-section entry counts, for orientation
  in large packages.
- An optional **curated guide** (`<feature>-tutorial.org`) woven in near
  the top, so you can hand-author narrative the generated reference then
  follows.

It relies only on Emacs built-ins (`org`, `lisp-mnt`, `info`,
`cl-lib`) and does not integrate with anything else.

## Usage

```elisp
(use-package package-tutor
  :ensure t
  :commands (package-tutor))
```

```
M-x package-tutor RET <feature> RET
```

You'll be prompted for a package or feature. Completion offers both
**loaded features and installed packages**, so you can tutor a package
you haven't loaded yet — `package-tutor` loads it on demand. It
defaults to the symbol at point when that names a feature/package. The
tutorial opens in a buffer named `*package-tutor: <feature>*`.

Other entry points:

- **`T`** on any package in the package menu (`M-x list-packages`) opens
  its tutorial (`package-tutor-from-package-menu`).
- **`T`** in a `*Help*` buffer (or `M-x package-tutor-for-symbol-at-point`
  anywhere) opens the tutorial for the package that defines the symbol
  at point.

Both bindings are added only if `T` is otherwise free in that map.

Inside the buffer (a `package-tutor-mode` buffer, derived from org):

- `C-c C-c` in a command block runs the command (`org-confirm-babel-evaluate`
  asks first by default — see below).
- `C-c C-o` / `RET` on a `package-tutor-readme:`, `info:` or
  `package-tutor-source:` link follows it.
- `C-c C-r` regenerates the tutorial (`package-tutor-refresh`); `C-c C-s`
  saves it to a file (`package-tutor-save`).
- Normal org folding (`TAB` / `S-TAB`) and heading motion (`C-c C-n` /
  `C-c C-p`) navigate the outline; the Contents section links to each
  section.

## How symbols are gathered

Every interned symbol whose name equals the feature name or begins with
`<feature>-` or `<feature>/` is collected and classified. Internal
symbols (those whose name contains `--`) are skipped unless
`package-tutor-include-internal` is non-nil. This prefix convention is
followed by nearly all Emacs packages; for a package that doesn't, the
gathered set may be incomplete.

## Customization

| Option | Default | Meaning |
|---|---|---|
| `package-tutor-command-order` | `crud` | `crud` groups commands under Create/Read/Update/Delete/Other sub-headings; `alphabetical` is a flat sorted list. |
| `package-tutor-crud-verbs` | _(see source)_ | Alist of verb tokens that signal each CRUD category. Tune this to fix mis-classifications. |
| `package-tutor-crud-priority` | `(delete create update read)` | Order categories are tested when a name matches several. |
| `package-tutor-crud-section-order` | `(create update read delete other)` | Order commands are listed under Commands, by CRUD category. Omit a category to hide it. |
| `package-tutor-sort-priority-regexp` | `"-mode\\'"` | Symbols matching this float to the top of each section. `nil` for plain alphabetical. |
| `package-tutor-include-info` | `t` | Link each symbol to its Info manual node when a manual exists. |
| `package-tutor-include-source` | `t` | Add a `Source:` link jumping to each symbol's definition. |
| `package-tutor-source-other-window` | `t` | Open `Source:` links in another window so the tutorial stays visible. |
| `package-tutor-info-manual-alist` | `nil` | Map a feature to its Info manual name when they differ, e.g. `((magit-section . "magit"))`. |
| `package-tutor-include-hooks` | `t` | Include a Hooks section (`-hook`/`-functions` variables). |
| `package-tutor-include-faces` | `t` | Include a Faces section. |
| `package-tutor-include-macros` | `t` | Include a Macros section. |
| `package-tutor-include-functions` | `t` | Include a Functions section. |
| `package-tutor-include-internal` | `nil` | Include `--` internal symbols. |
| `package-tutor-show-counts` | `t` | Append an entry count to each section heading. |
| `package-tutor-include-contents` | `t` | Insert a Contents section linking to each section. |
| `package-tutor-initial-visibility` | `showeverything` | Initial folding (`#+startup:`): `showeverything`, `content`, or `overview`. |
| `package-tutor-link-docstring-symbols` | `t` | Turn `` `like-this' `` docstring references into source links. |
| `package-tutor-overlay-directory` | `nil` | Directory searched for a curated `<feature>-tutorial.org` guide. |
| `package-tutor-include-overlay` | `t` | Prepend a curated guide file when one exists. |
| `package-tutor-save-directory` | `~/.emacs.d/package-tutorials/` | Where `package-tutor-save` writes tutorials. |
| `package-tutor-confirm-babel` | `t` | Buffer-local `org-confirm-babel-evaluate`. Set `nil` to run command blocks without a prompt. |
| `package-tutor-buffer-name-format` | `"*package-tutor: %s*"` | Tutorial buffer name. |
| `package-tutor-value-max-length` | `200` | Max characters shown for an option's value. |

## Sorting

Each section is ordered as follows.

**Within every section** the sort has two tiers, applied by
`package-tutor--sort`:

1. **Priority group first.** Symbols whose name matches
   `package-tutor-sort-priority-regexp` are listed ahead of the rest.
   The default regexp is `"-mode\\'"`, so mode entry points (commands
   and functions ending in `-mode`, e.g. `flymake-mode`) float to the
   top of their section. Set the option to `nil` for no priority group.
2. **Alphabetical within each tier.** The priority group and the
   remainder are each sorted by name.

So a section containing `foo-enable`, `foo-mode`, `foo-bar-mode` and
`foo-reset` is ordered: `foo-bar-mode`, `foo-mode` (the `-mode` tier,
alphabetised), then `foo-enable`, `foo-reset`.

**Options, Macros and Functions** use this two-tier sort directly.

**Commands** are special (see below). Under CRUD ordering the priority
group is pulled out to lead the *entire* Commands section — so all
`-mode` commands appear first, ahead of every CRUD group — and the
remaining commands are then partitioned by CRUD category, alphabetical
within each.

## Command ordering (CRUD)

By default commands are presented in lifecycle order rather than
alphabetically — as a single flat list under *Commands* ordered
**Create → Update → Read → Delete → Other** (with the priority group,
e.g. `-mode` commands, leading the whole section as described under
Sorting). So for `bookmark` you see `bookmark-set` before
`bookmark-delete`, which reads more like a tutorial. (Update precedes
Read because many "update" verbs — `set`, `toggle`, `edit` — also
create state; change the order with `package-tutor-crud-section-order`.)

The category is detected heuristically from the verb tokens in the
command name (split on `-` and `/`): `set`/`insert`/`add` → Create,
`jump`/`list`/`find` → Read, `rename`/`toggle`/`move` → Update,
`delete`/`remove`/`kill` → Delete. Names with no recognised verb fall
into *Other*. Because this is name-based, expect occasional misses
(e.g. `bookmark-save` lands in *Other*) — extend `package-tutor-crud-verbs`
to teach it new verbs, or set `package-tutor-command-order` to
`alphabetical` to turn grouping off.

## Info manual integration

When a package ships an Info manual, `package-tutor` adds doc links of
even higher fidelity than the README. It:

1. Locates the manual with `Info-find-file`, trying
   `package-tutor-info-manual-alist` first, then the feature's own name.
2. Builds a symbol → node map by scanning the manual's index nodes
   (Function/Variable/Command indexes win collisions; spaced concept
   entries are ignored). The scan runs in a private buffer and never
   touches your shared `*info*` buffer.
3. Adds a `Manual:` link to the manual in the header, and a per-symbol
   `Manual: [[info:<manual>#<node>][<node>]]` link wherever the symbol
   is indexed.

Following uses org's built-in `info:` link type — no extra setup. If a
package's manual is named differently from the feature (e.g. the
feature is `magit-section` but the manual is `magit`), add an entry to
`package-tutor-info-manual-alist`. Set `package-tutor-include-info` to
`nil` to skip Info entirely.

## Source links and portability

Every symbol gets a `Source:` link to its definition. Rather than baking
in an absolute path (which would break on another machine), the link
stores only the symbol and whether it is a function or a variable:

```
Source: [[package-tutor-source:fn/flymake-mode][source]]
```

Following it resolves the location *on the local machine* with
`find-function`/`find-variable`, opening in another window by default
so the tutorial stays visible (set `package-tutor-source-other-window`
to `nil` to reuse the current window). This makes a saved or shared
tutorial
**portable**: it works on any machine where the package is installed,
regardless of the install path or even the package version (the finder
searches for the defining form, not a fixed line number). The only
requirement is that the symbol actually be present where you click —
otherwise the link reports that the package isn't installed.

For the same reason, the header README link uses the symbolic
`package-tutor-readme:` link type (re-resolved at follow time) rather
than an absolute path, so nothing in a generated tutorial is tied to
the machine that produced it.

## Curated guides

Auto-generated content is a great *reference*, but it can't supply
narrative or ordering — that part is editorial. So if a file named
`<feature>-tutorial.org` exists in `package-tutor-overlay-directory`
(or beside the package's own source), its contents are inserted near
the top of the generated tutorial, before the Contents section. Write
the introduction, the "start here" walkthrough, and any exercises by
hand; let the generated Commands/Options/etc. sections follow as the
complete reference. Set `package-tutor-include-overlay` to `nil` to
ignore guides.

## Saving and refreshing

`package-tutor-mode` buffers bind `C-c C-r` to `package-tutor-refresh`
(regenerate in place, keeping point near the same heading — handy after
changing an option or your config) and `C-c C-s` to `package-tutor-save`
(write to `package-tutor-save-directory`, or a prompted path with a
prefix argument). Because every link is symbolic, a saved tutorial
remains fully functional on any machine where the package is installed.

## The `package-tutor-readme:` link type

`package-tutor` registers an org link type `package-tutor-readme:` of
the form `package-tutor-readme:FEATURE::SECTION` (namespaced to avoid
clashing with other packages). Following it locates the package's
README (any `README*` file beside the package's `.el`) and jumps to the
named section. The README is parsed into sections once per render, and
the section for each symbol is the first whose body mentions it.

## Limitations

- Only **loaded** packages are fully introspectable; autoloaded-but-not-
  yet-loaded symbols won't appear until the package loads. (Selecting an
  unloaded package at the prompt loads it first.)
- Keybindings are resolved from the package's own keymaps plus the
  global map, not the user's full set of active maps — so a key the user
  bound in some unrelated active minor-mode map won't show, but the
  package's own `<feature>-mode-map` bindings will, even when inactive.
- README matching is heuristic (literal symbol mention), and depends on
  the README being shipped alongside the `.el`.
- Output quality tracks docstring quality.

## Tests

```
emacs -Q --batch -L . -L test -l ert -l test/package-tutor-test.el \
  -f ert-run-tests-batch-and-exit
```
