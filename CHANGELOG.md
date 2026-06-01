# Changelog

## [0.1.1](https://github.com/chiply/package-tutor/compare/v0.1.0...v0.1.1) (2026-06-01)


### Features

* initial release of package-tutor ([bd88c56](https://github.com/chiply/package-tutor/commit/bd88c56e60e48358786dec35abcf88a3aa52c3fc))

## 0.1.0

Initial release.

- Generate an org-mode tutorial for any feature/package: commands,
  options, hooks, faces, macros and functions, gathered by name prefix
  and classified.
- Each command is an executable `emacs-lisp` babel block; each option
  gets a `customize-variable` block.
- CRUD lifecycle ordering of commands (Create/Update/Read/Delete/Other),
  with `-mode` commands leading; two-tier alphabetical sort elsewhere.
- Per-symbol cross-references: `package-tutor-readme:` links to the
  matching README section, `info:` links to the Info-manual node, and
  portable `package-tutor-source:` links to the definition.
- `like-this' docstring references become source links.
- Contents section with per-section counts; configurable folding.
- Optional curated `<feature>-tutorial.org` guide woven in.
- Entry points: `M-x package-tutor` (loaded features and installed
  packages), `T` in the package menu, and
  `package-tutor-for-symbol-at-point` (bound to `T` in help buffers).
- `package-tutor-mode` buffers: `C-c r` refresh, `C-c s` save.
- Relies only on built-in Emacs libraries.
